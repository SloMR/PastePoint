use crate::{
    CONTENT_TYPE_TEXT_PLAIN, SAFE_CHARSET, SESSION_EXPIRATION_TIME, ServerConfig, WsChatServer,
    WsChatSession, message::CleanupSession,
};
use actix::SystemService;
use actix_rt::{spawn, task, time};
use actix_web::{Error, HttpRequest, HttpResponse, web::Payload};
use rand::{RngExt, rng};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, Mutex,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio::sync::mpsc::unbounded_channel;
use uuid::Uuid;

/// Stores the session's UUID and whether it's private.
#[derive(Clone, Copy)]
pub struct SessionData {
    pub uuid: Uuid,
    pub is_private: bool,
}

#[derive(Default, Clone)]
pub struct SessionStore {
    /// Maps a key (IP for public or generated code for private sessions)
    /// to its session data.
    pub key_to_session: Arc<Mutex<HashMap<String, SessionData>>>,
    /// Tracks how many WebSocket clients reference each UUID.
    pub uuid_client_counts: Arc<Mutex<HashMap<Uuid, AtomicUsize>>>,
    /// For private sessions, tracks expired codes.
    pub expired_private_codes: Arc<Mutex<HashSet<String>>>,
    /// For private sessions, tracks scheduled expirations.
    pub scheduled_expirations: Arc<Mutex<HashMap<String, task::JoinHandle<()>>>>,
}

impl SessionStore {
    /// Returns true if the private session code has been marked expired.
    fn is_code_expired(&self, key: &str) -> bool {
        self.expired_private_codes
            .lock()
            .expect("lock poisoned")
            .contains(key)
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
    ) -> Option<String> {
        // For private sessions, check if the code is expired.
        if is_private && self.is_code_expired(key) {
            log::debug!(target: "Websocket", "Private session code {key} is expired");
            return None;
        }

        // Make sure to always cancel any scheduled expiration when reconnecting
        if is_private {
            let mut scheduled = self.scheduled_expirations.lock().expect("lock poisoned");
            if let Some(handle) = scheduled.remove(key) {
                handle.abort();
                log::debug!("Cancelled scheduled expiration for {key}");
            }
        }

        {
            let map = match self.key_to_session.lock() {
                Ok(guard) => guard,
                Err(e) => {
                    log::error!(
                        target: "Websocket",
                        "Failed to acquire lock on key_to_session: {e:?}"
                    );
                    return None;
                }
            };
            if let Some(data) = map.get(key) {
                self.increment_client_count(data.uuid);
                return Some(data.uuid.to_string());
            }
        }

        if strict_mode {
            return None;
        }

        let new_uuid = Uuid::new_v4();
        let new_data = SessionData {
            uuid: new_uuid,
            is_private,
        };
        {
            let mut map = match self.key_to_session.lock() {
                Ok(guard) => guard,
                Err(e) => {
                    log::error!(
                        target: "Websocket",
                        "Failed to acquire lock on key_to_session: {e:?}"
                    );
                    return None;
                }
            };
            map.insert(key.to_string(), new_data);
        }
        self.increment_client_count(new_uuid);
        Some(new_uuid.to_string())
    }

    /// Starts a WebSocket session using the stored session UUID.
    pub fn start_websocket(
        &self,
        config: &ServerConfig,
        req: &HttpRequest,
        stream: Payload,
        key: &str,
        strict_mode: bool,
        is_private: bool,
    ) -> Result<HttpResponse, Error> {
        match self.get_or_create_session_uuid(key, strict_mode, is_private) {
            Some(uuid_str) => match Uuid::parse_str(&uuid_str) {
                Ok(_) => {
                    let (response, session, msg_stream) = actix_ws::handle(req, stream)
                        .inspect_err(|e| {
                            log::error!(target: "Websocket", "WebSocket handshake failed: {e}");
                        })?;

                    let (tx, rx) = unbounded_channel::<String>();
                    let server = WsChatServer::from_registry();
                    let state = WsChatSession::new(&uuid_str, config.auto_join, self.clone());

                    let handle =
                        actix_web::rt::spawn(state.run(session, msg_stream, rx, tx, server));
                    actix_web::rt::spawn(async move {
                        if let Err(e) = handle.await {
                            log::error!(target: "Websocket", "Session task terminated abnormally: {e}");
                        }
                    });

                    Ok(response)
                }
                Err(_) => {
                    log::error!(target: "Websocket", "Invalid UUID returned: {uuid_str}");
                    Ok(HttpResponse::InternalServerError()
                        .content_type(CONTENT_TYPE_TEXT_PLAIN)
                        .body("Server configuration error"))
                }
            },
            None => {
                log::warn!(
                    target: "Websocket",
                    "Key '{key}' not found in strict mode, returning 404"
                );
                Ok(HttpResponse::NotFound()
                    .content_type(CONTENT_TYPE_TEXT_PLAIN)
                    .body("Unknown session code"))
            }
        }
    }

    /// Increments the client count for the session with the given UUID.
    fn increment_client_count(&self, uuid: Uuid) {
        let mut counts = match self.uuid_client_counts.lock() {
            Ok(guard) => guard,
            Err(e) => {
                log::error!(
                    target: "Websocket",
                    "Failed to acquire lock on uuid_client_counts: {e:?}"
                );
                return;
            }
        };
        let counter = counts.entry(uuid).or_default();
        let new_count = counter.fetch_add(1, Ordering::SeqCst) + 1;
        log::debug!(target: "Websocket", "Session {uuid} now has {new_count} clients");
    }

    /// Decrements the client count. If it reaches zero for a private session,
    /// the key is removed and marked as expired.
    pub fn remove_client(&self, uuid: &Uuid) {
        let mut counts = self.uuid_client_counts.lock().expect("lock poisoned");
        if let Some(counter) = counts.get_mut(uuid) {
            let prev = counter.fetch_sub(1, Ordering::SeqCst);
            let new_count = prev.saturating_sub(1);
            log::debug!(
                target: "Websocket",
                "Client count for session {uuid} decreased from {prev} to {new_count}"
            );
            if new_count == 0 {
                counts.remove(uuid);

                if WsChatServer::from_registry()
                    .try_send(CleanupSession(uuid.to_string()))
                    .is_ok()
                {
                    log::debug!(target: "Websocket", "Sent cleanup request for session {uuid}");
                }

                let map = self.key_to_session.lock().expect("lock poisoned");
                let keys: Vec<(String, bool)> = map
                    .iter()
                    .filter(|(_, data)| data.uuid == *uuid)
                    .map(|(k, data)| (k.clone(), data.is_private))
                    .collect();
                drop(map);

                for (key, is_private) in keys {
                    if !is_private {
                        let mut map = self.key_to_session.lock().expect("lock poisoned");
                        map.remove(&key);
                        log::debug!(target: "Websocket", "Public session code {key} removed");
                    } else {
                        let store_clone = self.clone();
                        let key_clone = key.clone();

                        let handle = spawn(async move {
                            time::sleep(SESSION_EXPIRATION_TIME).await;

                            let mut scheduled = store_clone
                                .scheduled_expirations
                                .lock()
                                .expect("lock poisoned");

                            if scheduled.remove(&key_clone).is_some() {
                                let mut map =
                                    store_clone.key_to_session.lock().expect("lock poisoned");

                                if map.remove(&key_clone).is_some() {
                                    let mut expired = store_clone
                                        .expired_private_codes
                                        .lock()
                                        .expect("lock poisoned");
                                    expired.insert(key_clone.clone());
                                    log::debug!("Private session code {key_clone} expired");
                                }
                            }
                        });

                        self.scheduled_expirations
                            .lock()
                            .expect("lock poisoned")
                            .insert(key.clone(), handle);
                    }
                }
            }
        } else {
            log::debug!(
                target: "Websocket",
                "Attempted to remove client from unknown session {uuid}"
            );
        }
    }

    /// Generates a random alphanumeric code.
    pub fn generate_random_code(length: usize) -> String {
        let mut rng = rng();
        (0..length)
            .map(|_| {
                let idx = rng.random_range(0..SAFE_CHARSET.len());
                SAFE_CHARSET[idx] as char
            })
            .collect()
    }
}
