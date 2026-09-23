use crate::{
    CLEANUP_INTERVAL, CONTENT_TYPE_TEXT_PLAIN, ChatServerHandle, SAFE_CHARSET, SESSION_CODE_LENGTH,
    SESSION_EXPIRATION_TIME, ServerConfig, ServerError,
    consts::{MAX_SESSIONS, OUTBOUND_CHANNEL_CAPACITY},
    session::WsChatSession,
};
use actix_rt::{spawn, time};
use actix_web::{Error, HttpRequest, HttpResponse, web::Payload};
use rand::{RngExt, rng};
use std::{
    collections::{HashMap, hash_map::Entry},
    sync::{Arc, LockResult, Mutex, MutexGuard},
    time::{Duration, Instant},
};
use tokio::sync::mpsc::channel;
use uuid::Uuid;

/// Stores the session's UUID and whether it's private.
#[derive(Clone, Copy)]
struct SessionData {
    uuid: Uuid,
    is_private: bool,
}

/// When an unused private code stops resolving.
#[derive(Clone, Copy)]
struct PrivateExpiration {
    uuid: Uuid,
    deadline: Instant,
}

/// Session keys, client counts and expiry deadlines, changed together under one lock.
#[derive(Default)]
struct SessionRegistry {
    /// Maps a key (host and IP for public, generated code for private sessions)
    /// to its session data.
    key_to_session: HashMap<String, SessionData>,
    /// How many WebSocket clients reference each UUID.
    client_counts: HashMap<Uuid, usize>,
    /// Private codes that expire unless a client joins before the deadline.
    private_expirations: HashMap<String, PrivateExpiration>,
}

#[derive(Clone)]
pub struct SessionStore {
    /// Shared room/session state, replacing the former WsChatServer actor.
    pub(crate) chat_server: ChatServerHandle,
    registry: Arc<Mutex<SessionRegistry>>,
    /// How long a private code survives with nobody connected.
    expiration: Duration,
}

impl Default for SessionStore {
    fn default() -> Self {
        Self::with_expiration(SESSION_EXPIRATION_TIME)
    }
}

impl SessionStore {
    /// A store whose private codes expire after `expiration` with nobody connected.
    pub fn with_expiration(expiration: Duration) -> Self {
        Self {
            chat_server: ChatServerHandle::default(),
            registry: Arc::default(),
            expiration,
        }
    }

    /// Creates a private session under a new code that expires if nobody joins it.
    pub fn create_private_session(&self) -> Result<String, ServerError> {
        let mut registry = Self::lock_or_log(self.registry.lock(), "session_registry")
            .ok_or(ServerError::InternalServerError)?;
        Self::prune_expired(&mut registry);
        if registry.key_to_session.len() >= MAX_SESSIONS {
            log::warn!(
                target: "Websocket",
                "Max sessions limit reached ({MAX_SESSIONS}), rejecting session creation"
            );
            return Err(ServerError::BadRequest(
                "Server capacity reached. Try again later.".to_string(),
            ));
        }

        let code = loop {
            let code = Self::generate_random_code(SESSION_CODE_LENGTH);
            if let Entry::Vacant(entry) = registry.key_to_session.entry(code.clone()) {
                let uuid = Uuid::new_v4();
                entry.insert(SessionData {
                    uuid,
                    is_private: true,
                });
                registry.private_expirations.insert(
                    code.clone(),
                    PrivateExpiration {
                        uuid,
                        deadline: Instant::now() + self.expiration,
                    },
                );
                break code;
            }
        };
        drop(registry);

        sentry::logger_info!(kind = "private", "session.created");
        Ok(code)
    }

    /// Looks up (or creates) a session UUID for the given key.
    /// The caller must indicate whether this is a private session.
    /// - If the session exists, its client count is incremented and its UUID returned.
    /// - If not found and strict_mode is false, a new session is auto‑created.
    /// - If strict_mode is true, None is returned (resulting in a 404).
    pub fn get_or_create_session_uuid(
        &self,
        key: &str,
        strict_mode: bool,
        is_private: bool,
    ) -> Option<Uuid> {
        let mut registry = Self::lock_or_log(self.registry.lock(), "session_registry")?;
        Self::prune_expired(&mut registry);

        if let Some(data) = registry.key_to_session.get(key).copied() {
            if is_private {
                registry.private_expirations.remove(key);
            }
            let count = registry.client_counts.entry(data.uuid).or_default();
            *count += 1;
            log::debug!(target: "Websocket", "Session {} now has {count} clients", data.uuid);
            return Some(data.uuid);
        }

        if strict_mode {
            log::warn!(target: "Websocket", "Rejected private join: unknown session code");
            log::debug!(target: "Websocket", "Key '{key}' not found in strict mode");
            return None;
        }

        let uuid = Uuid::new_v4();
        registry
            .key_to_session
            .insert(key.to_string(), SessionData { uuid, is_private });
        registry.client_counts.insert(uuid, 1);
        drop(registry);

        sentry::logger_info!(
            kind = if is_private { "private" } else { "public" },
            "session.created"
        );
        Some(uuid)
    }

    /// Starts a WebSocket session using the stored session UUID.
    pub(crate) fn start_websocket(
        &self,
        config: &ServerConfig,
        req: &HttpRequest,
        stream: Payload,
        key: &str,
        strict_mode: bool,
        is_private: bool,
    ) -> Result<HttpResponse, Error> {
        match self.get_or_create_session_uuid(key, strict_mode, is_private) {
            Some(uuid) => match actix_ws::handle(req, stream) {
                Ok((response, session, msg_stream)) => {
                    let (tx, rx) = channel::<String>(OUTBOUND_CHANNEL_CAPACITY);
                    let server = self.chat_server.clone();
                    let state =
                        WsChatSession::new(&uuid.to_string(), config.auto_join, self.clone());

                    let handle = spawn(state.run(session, msg_stream, rx, tx, server));
                    spawn(async move {
                        if let Err(e) = handle.await {
                            log::error!(target: "Websocket", "Session task terminated abnormally: {e}");
                        }
                    });

                    Ok(response)
                }
                Err(e) => {
                    // The client count was already incremented while resolving the
                    // UUID; undo it here since no session task will run to do so.
                    log::error!(target: "Websocket", "WebSocket handshake failed: {e}");
                    self.remove_client(&uuid);
                    Err(e)
                }
            },
            None => Ok(Self::unknown_session_response()),
        }
    }

    /// The 404 returned for a private code that is malformed, unknown or expired.
    pub(crate) fn unknown_session_response() -> HttpResponse {
        HttpResponse::NotFound()
            .content_type(CONTENT_TYPE_TEXT_PLAIN)
            .body("Unknown session code")
    }

    /// Spawns a background task that prunes empty rooms and expired private codes.
    pub fn spawn_cleanup_task(&self) {
        let store = self.clone();
        spawn(async move {
            let mut rooms = time::interval(CLEANUP_INTERVAL);
            let mut expirations = time::interval(store.expiration);
            loop {
                tokio::select! {
                    _ = rooms.tick() => store.chat_server.cleanup_stale_sessions(),
                    _ = expirations.tick() => store.prune_expired_now(),
                }
            }
        });
    }

    /// Decrements the client count. When it reaches zero, a public key is removed
    /// and a private code expires after the reconnect grace period.
    pub fn remove_client(&self, uuid: &Uuid) {
        let Some(mut registry) = Self::lock_or_log(self.registry.lock(), "session_registry") else {
            return;
        };
        let Some(count) = registry.client_counts.get_mut(uuid) else {
            log::debug!(
                target: "Websocket",
                "Attempted to remove client from unknown session {uuid}"
            );
            return;
        };
        *count = count.saturating_sub(1);
        log::debug!(target: "Websocket", "Session {uuid} now has {count} clients");
        if *count > 0 {
            return;
        }

        registry.client_counts.remove(uuid);
        // Inside the lock, so a client rejoining the same key can't have its
        // rooms removed by this teardown.
        self.chat_server.cleanup_session(&uuid.to_string());
        log::debug!(target: "Websocket", "Cleaned up rooms for session {uuid}");

        let deadline = Instant::now() + self.expiration;
        let keys: Vec<(String, bool)> = registry
            .key_to_session
            .iter()
            .filter(|(_, data)| data.uuid == *uuid)
            .map(|(key, data)| (key.clone(), data.is_private))
            .collect();
        for (key, is_private) in keys {
            if is_private {
                registry.private_expirations.insert(
                    key,
                    PrivateExpiration {
                        uuid: *uuid,
                        deadline,
                    },
                );
            } else {
                registry.key_to_session.remove(&key);
                log::debug!(target: "Websocket", "Public session code {key} removed");
            }
        }
    }

    fn prune_expired_now(&self) {
        if let Some(mut registry) = Self::lock_or_log(self.registry.lock(), "session_registry") {
            Self::prune_expired(&mut registry);
        }
    }

    /// Drops private codes whose deadline passed while no client was connected.
    fn prune_expired(registry: &mut SessionRegistry) {
        let now = Instant::now();
        let expired: Vec<(String, Uuid)> = registry
            .private_expirations
            .iter()
            .filter(|(_, expiration)| expiration.deadline <= now)
            .map(|(key, expiration)| (key.clone(), expiration.uuid))
            .collect();

        for (key, uuid) in expired {
            registry.private_expirations.remove(&key);
            let is_same_session = registry
                .key_to_session
                .get(&key)
                .is_some_and(|data| data.uuid == uuid);
            if is_same_session && !registry.client_counts.contains_key(&uuid) {
                registry.key_to_session.remove(&key);
                log::debug!(target: "Websocket", "Private session code {key} expired");
            }
        }
    }

    /// Locks `result`, logging and returning `None` if the mutex is poisoned.
    fn lock_or_log<'a, T>(
        result: LockResult<MutexGuard<'a, T>>,
        name: &str,
    ) -> Option<MutexGuard<'a, T>> {
        match result {
            Ok(guard) => Some(guard),
            Err(e) => {
                log::error!(target: "Websocket", "Failed to acquire lock on {name} (poisoned): {e:?}");
                None
            }
        }
    }

    /// Generates a random alphanumeric code.
    pub(crate) fn generate_random_code(length: usize) -> String {
        let mut rng = rng();
        (0..length)
            .map(|_| {
                let idx = rng.random_range(0..SAFE_CHARSET.len());
                SAFE_CHARSET[idx] as char
            })
            .collect()
    }
}
