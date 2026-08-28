use crate::{
    WS_PREFIX_SIGNAL_MESSAGE, WS_PREFIX_SYSTEM_ERROR, WS_PREFIX_SYSTEM_JOIN,
    WS_PREFIX_SYSTEM_MEMBERS, WS_PREFIX_SYSTEM_ROOMS,
    consts::{DEFAULT_ROOM, MAX_ROOMS_PER_SESSION, MAX_SESSIONS},
};
use rand::{RngExt, rng};
use std::{
    collections::{HashMap, hash_map::Entry::Vacant},
    sync::{Arc, Mutex, MutexGuard},
};
use tokio::sync::mpsc::Sender;

/// Sender used by the server to push outbound text frames to a client's task.
pub(crate) type Client = Sender<String>;
pub(crate) type Room = HashMap<usize, ClientMetadata>;

/// Owns all room and session state — the single source of truth for which
/// clients are in which rooms. Mutated only through a [`ChatServerHandle`].
#[derive(Default)]
pub struct WsChatServer {
    /// `Map<session_id, Map<room_name, Map<client_id, ClientMetadata>>>`
    pub rooms: HashMap<String, HashMap<String, Room>>,
}

pub struct ClientMetadata {
    pub tx: Client,   // outbound channel to the client
    pub name: String, // client name
}

/// Cheap, cloneable handle to the shared [`WsChatServer`].
#[derive(Clone, Default)]
pub struct ChatServerHandle {
    inner: Arc<Mutex<WsChatServer>>,
}

impl ChatServerHandle {
    fn lock(&self) -> MutexGuard<'_, WsChatServer> {
        // Recover a poisoned lock instead of cascading one connection's panic
        // to every other connection sharing this handle.
        self.inner
            .lock()
            .unwrap_or_else(|poisoned| poisoned.into_inner())
    }

    /// Join `room_name`, returning the assigned client id (`0` if rejected).
    pub(crate) fn join_room(
        &self,
        session_id: &str,
        room_name: &str,
        client_name: &str,
        client: Client,
    ) -> usize {
        self.lock()
            .join_room(session_id, room_name, client_name, client)
    }

    /// Remove client `id` from `room_name` and broadcast the updated rosters.
    pub(crate) fn leave_room(&self, session_id: &str, room_name: &str, id: usize) {
        self.lock().leave_room(session_id, room_name, id);
    }

    /// List the rooms currently open in `session_id`.
    pub(crate) fn list_rooms(&self, session_id: &str) -> Vec<String> {
        self.lock().list_rooms(session_id)
    }

    /// Drop all rooms for a session once its last client has gone.
    pub(crate) fn cleanup_session(&self, session_id: &str) {
        self.lock().cleanup_session(session_id);
    }

    /// Relay a signaling payload to `to_user` if it shares a room with `from_user`.
    pub(crate) fn validate_and_relay_signal(
        &self,
        session_id: &str,
        from_user: &str,
        to_user: &str,
        payload: &str,
        signal_type: &str,
    ) {
        self.lock()
            .validate_and_relay_signal(session_id, from_user, to_user, payload, signal_type);
    }

    /// Prune sessions whose rooms are all empty.
    pub(crate) fn cleanup_stale_sessions(&self) {
        self.lock().cleanup_stale_sessions();
    }
}

impl WsChatServer {
    fn join_room(
        &mut self,
        session_id: &str,
        room_name: &str,
        client_name: &str,
        client: Client,
    ) -> usize {
        match self.add_client_to_room(
            session_id,
            room_name,
            None,
            client.clone(),
            client_name.to_owned(),
        ) {
            Some(id) => {
                let room_size = self
                    .rooms
                    .get(session_id)
                    .and_then(|rooms| rooms.get(room_name))
                    .map_or(0, |room| room.len());

                sentry::logger_info!(room_size = room_size as u64, "room.joined");

                let join_msg = format!("{client_name} {WS_PREFIX_SYSTEM_JOIN} {room_name}");
                self.send_join_message(session_id, room_name, &join_msg);
                self.broadcast_room_members(session_id, room_name);
                id
            }
            None => {
                if client
                    .try_send(format!(
                        "{WS_PREFIX_SYSTEM_ERROR} Room limit or session limit reached"
                    ))
                    .is_err()
                {
                    log::debug!(
                        target: "Websocket",
                        "Could not notify client of room/session limit: already disconnected"
                    );
                }
                0
            }
        }
    }

    fn leave_room(&mut self, session_id: &str, room_name: &str, id: usize) {
        if let Some(rooms) = self.rooms.get_mut(session_id)
            && let Some(room) = rooms.get_mut(room_name)
        {
            room.remove(&id);

            if room.is_empty() && room_name != DEFAULT_ROOM {
                rooms.remove(room_name);
                log::debug!(
                    target: "Websocket",
                    "Room '{room_name}' removed from session {session_id}"
                );
            }

            self.broadcast_room_list(session_id);
            self.broadcast_room_members(session_id, room_name);

            log::debug!(
                target: "Websocket",
                "User {} in {} left room {}. Rooms: {:?}",
                id,
                session_id,
                room_name,
                self.rooms
                    .values()
                    .map(|r| r.keys().cloned().collect::<Vec<String>>())
                    .collect::<Vec<Vec<String>>>()
            );
        } else {
            log::debug!(
                target: "Websocket",
                "Leave for unknown room '{room_name}' in session {session_id}"
            );
        }
    }

    fn list_rooms(&self, session_id: &str) -> Vec<String> {
        match self.rooms.get(session_id) {
            Some(rooms_map) => rooms_map.keys().cloned().collect(),
            None => {
                log::debug!(target: "Websocket", "No rooms found for session {session_id}");
                Vec::new()
            }
        }
    }

    fn cleanup_session(&mut self, session_id: &str) {
        if self.rooms.remove(session_id).is_some() {
            log::debug!(target: "Websocket", "Removed all rooms for session {session_id}");
        } else {
            log::debug!(target: "Websocket", "Cleanup requested for unknown session {session_id}");
        }
    }

    fn validate_and_relay_signal(
        &self,
        session_id: &str,
        from_user: &str,
        to_user: &str,
        payload: &str,
        signal_type: &str,
    ) {
        let tx = sentry::Hub::current().client().map(|_| {
            let tx = sentry::start_transaction(sentry::TransactionContext::new(
                "signaling.relay",
                "websocket.signal",
            ));
            tx.set_tag("signal.type", signal_type);
            tx
        });

        if from_user == to_user {
            log::debug!(target: "Websocket", "Skipping self-relay from {from_user} to {to_user}");
            if let Some(tx) = tx {
                tx.set_status(sentry::protocol::SpanStatus::Ok);
                tx.finish();
            }
            return;
        }

        let relay_msg = format!("{WS_PREFIX_SIGNAL_MESSAGE} {payload}");
        let status = if self.relay_to_shared_room(session_id, from_user, to_user, relay_msg) {
            sentry::protocol::SpanStatus::Ok
        } else {
            log::warn!(target: "Websocket", "Attempted signal to user not in same room");
            sentry::protocol::SpanStatus::PermissionDenied
        };
        if let Some(tx) = tx {
            tx.set_status(status);
            tx.finish();
        }
    }

    /// Sends `message` to `to_user` if they share a room with `from_user`, in a
    /// single pass over the session's rooms. Returns whether such a room was found.
    fn relay_to_shared_room(
        &self,
        session_id: &str,
        from_user: &str,
        to_user: &str,
        message: String,
    ) -> bool {
        let Some(rooms) = self.rooms.get(session_id) else {
            return false;
        };

        let target_tx = rooms.values().find_map(|room| {
            if !room.values().any(|cm| cm.name == from_user) {
                return None;
            }
            room.values()
                .find(|cm| cm.name == to_user)
                .map(|cm| cm.tx.clone())
        });

        match target_tx {
            Some(tx) => {
                if let Err(e) = tx.try_send(message) {
                    log::error!(
                        target: "Websocket",
                        "Failed to relay signal from {from_user} to {to_user}: {e:?}"
                    );
                } else {
                    log::debug!(
                        target: "Websocket",
                        "Successfully relayed signal from {from_user} to {to_user}"
                    );
                }
                true
            }
            None => false,
        }
    }

    /// Validates a room name (used by the session command parser).
    pub(crate) fn is_valid_room_name(name: &str) -> bool {
        let trimmed = name.trim();
        !trimmed.is_empty()
            && trimmed.chars().count() <= 64
            && trimmed
                .chars()
                .all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == ' ')
    }

    /// Adds a client to a room, enforcing the room/session limits.
    pub fn add_client_to_room(
        &mut self,
        session_id: &str,
        room_name: &str,
        id: Option<usize>,
        client: Client,
        name: String,
    ) -> Option<usize> {
        let id = id.unwrap_or_else(|| rng().random_range(0..usize::MAX));

        if let Some(room) = self.rooms.get_mut(session_id)
            && let Some(existing_room) = room.get_mut(room_name)
        {
            return if let Vacant(e) = existing_room.entry(id) {
                log::debug!(target: "Websocket", "Adding client to room: {}", room_name);
                e.insert(ClientMetadata { tx: client, name });
                Some(id)
            } else {
                log::debug!(
                    target: "Websocket",
                    "Client {} already in room: {}, skipping addition",
                    id,
                    room_name
                );
                Some(id)
            };
        }

        if let Some(rooms) = self.rooms.get(session_id)
            && rooms.len() >= MAX_ROOMS_PER_SESSION
        {
            log::warn!(
                target: "Websocket",
                "Session {session_id} exceeded max rooms limit ({MAX_ROOMS_PER_SESSION})"
            );
            return None;
        }

        if !self.rooms.contains_key(session_id) && self.rooms.len() >= MAX_SESSIONS {
            log::warn!(
                target: "Websocket",
                "Max sessions limit reached ({MAX_SESSIONS}), rejecting new session"
            );
            return None;
        }

        let mut room: Room = HashMap::new();
        room.insert(id, ClientMetadata { tx: client, name });

        self.rooms
            .entry(session_id.to_string())
            .or_default()
            .insert(room_name.to_owned(), room);

        self.broadcast_room_list(session_id);
        Some(id)
    }

    fn send_join_message(&self, session_id: &str, room_name: &str, msg: &str) {
        log::debug!(target: "Websocket", "Sending join message to room {room_name}: {msg}");

        match self
            .rooms
            .get(session_id)
            .and_then(|rooms| rooms.get(room_name))
        {
            Some(room) => Self::send_to_clients(room.values(), msg),
            None => log::debug!(
                target: "Websocket",
                "Room {room_name} not found in session {session_id}"
            ),
        }
    }

    fn broadcast_room_list(&self, session_id: &str) {
        if let Some(users) = self.rooms.get(session_id) {
            let room_list = users.keys().cloned().collect::<Vec<String>>().join(", ");
            let message = format!("{WS_PREFIX_SYSTEM_ROOMS} {room_list}");
            Self::send_to_clients(users.values().flat_map(|room| room.values()), &message);
        }
    }

    fn broadcast_room_members(&self, session_id: &str, room_name: &str) {
        if let Some(users) = self.rooms.get(session_id)
            && let Some(room) = users.get(room_name)
        {
            let member_list: Vec<String> = room
                .values()
                .map(|client_metadata| client_metadata.name.clone())
                .collect();
            log::debug!(
                target: "Websocket",
                "Broadcasting members of room {}: {:?}",
                room_name,
                member_list
            );
            let member_message = format!("{} {}", WS_PREFIX_SYSTEM_MEMBERS, member_list.join(", "));
            Self::send_to_clients(room.values(), &member_message);
        }
    }

    /// Pushes `message` to each client, shedding (logging) any whose bounded
    /// outbound channel is full or closed.
    fn send_to_clients<'a>(clients: impl Iterator<Item = &'a ClientMetadata>, message: &str) {
        for client in clients {
            if client.tx.try_send(message.to_owned()).is_err() {
                log::debug!(
                    target: "Websocket",
                    "Dropped frame to {}: outbound channel full or closed",
                    client.name
                );
            }
        }
    }

    pub(crate) fn cleanup_stale_sessions(&mut self) {
        let empty_sessions: Vec<String> = self
            .rooms
            .iter()
            .filter(|(_, rooms_map)| rooms_map.values().all(|room| room.is_empty()))
            .map(|(session_id, _)| session_id.clone())
            .collect();

        for session_id in empty_sessions {
            log::debug!(target: "Websocket","Cleanup: Removing empty session {session_id}");
            self.rooms.remove(&session_id);
        }

        log::debug!(
            target: "Websocket",
            "Current server state: {} active sessions",
            self.rooms.len()
        );
        sentry::logger_info!(count = self.rooms.len() as u64, "sessions.active");
    }
}
