use crate::{
    CLEANUP_INTERVAL, CONTENT_TYPE_TEXT_PLAIN, ChatServerHandle, SAFE_CHARSET,
    SESSION_EXPIRATION_TIME, ServerConfig, consts::OUTBOUND_CHANNEL_CAPACITY,
    session::WsChatSession,
};
use actix_rt::{spawn, task, time};
use actix_web::{Error, HttpRequest, HttpResponse, web::Payload};
use rand::{RngExt, rng};
use std::{
    collections::{HashMap, HashSet},
    sync::{
        Arc, LockResult, Mutex, MutexGuard,
        atomic::{AtomicUsize, Ordering},
    },
};
use tokio::sync::mpsc::channel;
use uuid::Uuid;

/// Stores the session's UUID and whether it's private.
#[derive(Clone, Copy)]
pub(crate) struct SessionData {
    pub(crate) uuid: Uuid,
    pub(crate) is_private: bool,
}

#[derive(Default, Clone)]
pub struct SessionStore {
    /// Shared room/session state, replacing the former WsChatServer actor.
    pub(crate) chat_server: ChatServerHandle,
    /// Maps a key (IP for public or generated code for private sessions)
    /// to its session data.
    pub(crate) key_to_session: Arc<Mutex<HashMap<String, SessionData>>>,
    /// Tracks how many WebSocket clients reference each UUID.
    uuid_client_counts: Arc<Mutex<HashMap<Uuid, AtomicUsize>>>,
    /// For private sessions, tracks expired codes.
    expired_private_codes: Arc<Mutex<HashSet<String>>>,
    /// For private sessions, tracks scheduled expirations.
    scheduled_expirations: Arc<Mutex<HashMap<String, task::JoinHandle<()>>>>,
}

impl SessionStore {
    /// Returns true if the private session code has been marked expired.
    fn is_code_expired(&self, key: &str) -> bool {
        let Some(expired) =
            Self::lock_or_log(self.expired_private_codes.lock(), "expired_private_codes")
        else {
            // Fail closed: if we can't read the expiry set, treat the code as
            // expired so a poisoned lock can't be used to bypass expiration.
            return true;
        };
        expired.contains(key)
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
        // For private sessions, check if the code is expired.
        if is_private && self.is_code_expired(key) {
            log::debug!(target: "Websocket", "Private session code {key} is expired");
            return None;
        }

        // Make sure to always cancel any scheduled expiration when reconnecting
        if is_private
            && let Some(mut scheduled) =
                Self::lock_or_log(self.scheduled_expirations.lock(), "scheduled_expirations")
            && let Some(handle) = scheduled.remove(key)
        {
            handle.abort();
            log::debug!("Cancelled scheduled expiration for {key}");
        }

        {
            let map = Self::lock_or_log(self.key_to_session.lock(), "key_to_session")?;
            if let Some(data) = map.get(key) {
                self.increment_client_count(data.uuid);
                return Some(data.uuid);
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
            let mut map = Self::lock_or_log(self.key_to_session.lock(), "key_to_session")?;
            map.insert(key.to_string(), new_data);
        }
        self.increment_client_count(new_uuid);
        Some(new_uuid)
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

    /// Spawns a background task that periodically prunes empty sessions.
    pub fn spawn_cleanup_task(&self) {
        let chat_server = self.chat_server.clone();
        spawn(async move {
            let mut ticker = time::interval(CLEANUP_INTERVAL);
            loop {
                ticker.tick().await;
                chat_server.cleanup_stale_sessions();
            }
        });
    }

    /// Increments the client count for the session with the given UUID.
    fn increment_client_count(&self, uuid: Uuid) {
        let Some(mut counts) =
            Self::lock_or_log(self.uuid_client_counts.lock(), "uuid_client_counts")
        else {
            return;
        };
        let counter = counts.entry(uuid).or_default();
        let new_count = counter.fetch_add(1, Ordering::SeqCst) + 1;
        log::debug!(target: "Websocket", "Session {uuid} now has {new_count} clients");
    }

    /// Decrements the client count. If it reaches zero for a private session,
    /// the key is removed and marked as expired.
    pub(crate) fn remove_client(&self, uuid: &Uuid) {
        let Some(mut counts) =
            Self::lock_or_log(self.uuid_client_counts.lock(), "uuid_client_counts")
        else {
            return;
        };
        if let Some(counter) = counts.get_mut(uuid) {
            let prev = counter.fetch_sub(1, Ordering::SeqCst);
            let new_count = prev.saturating_sub(1);
            log::debug!(
                target: "Websocket",
                "Client count for session {uuid} decreased from {prev} to {new_count}"
            );
            if new_count == 0 {
                counts.remove(uuid);

                self.chat_server.cleanup_session(&uuid.to_string());
                log::debug!(target: "Websocket", "Cleaned up rooms for session {uuid}");

                let Some(map) = Self::lock_or_log(self.key_to_session.lock(), "key_to_session")
                else {
                    return;
                };
                let keys: Vec<(String, bool)> = map
                    .iter()
                    .filter(|(_, data)| data.uuid == *uuid)
                    .map(|(k, data)| (k.clone(), data.is_private))
                    .collect();
                drop(map);

                for (key, is_private) in keys {
                    if !is_private {
                        let Some(mut map) =
                            Self::lock_or_log(self.key_to_session.lock(), "key_to_session")
                        else {
                            continue;
                        };
                        map.remove(&key);
                        log::debug!(target: "Websocket", "Public session code {key} removed");
                    } else {
                        let store_clone = self.clone();
                        let key_clone = key.clone();

                        let handle = spawn(async move {
                            time::sleep(SESSION_EXPIRATION_TIME).await;

                            let Some(mut scheduled) = Self::lock_or_log(
                                store_clone.scheduled_expirations.lock(),
                                "scheduled_expirations",
                            ) else {
                                return;
                            };

                            if scheduled.remove(&key_clone).is_some() {
                                let Some(mut map) = Self::lock_or_log(
                                    store_clone.key_to_session.lock(),
                                    "key_to_session",
                                ) else {
                                    return;
                                };

                                if map.remove(&key_clone).is_some() {
                                    let Some(mut expired) = Self::lock_or_log(
                                        store_clone.expired_private_codes.lock(),
                                        "expired_private_codes",
                                    ) else {
                                        return;
                                    };
                                    expired.insert(key_clone.clone());
                                    log::debug!("Private session code {key_clone} expired");
                                }
                            }
                        });

                        if let Some(mut scheduled) = Self::lock_or_log(
                            self.scheduled_expirations.lock(),
                            "scheduled_expirations",
                        ) {
                            scheduled.insert(key.clone(), handle);
                        }
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
