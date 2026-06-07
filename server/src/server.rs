use crate::{
    CLEANUP_INTERVAL, WS_PREFIX_SYSTEM_MEMBERS, WS_PREFIX_SYSTEM_ROOMS,
    consts::{MAX_ROOMS_PER_SESSION, MAX_SESSIONS},
    message::{Client, ClientMetadata, Room, WsChatServer},
};
use actix::prelude::*;
use rand::{RngExt, rng};
use std::collections::{HashMap, hash_map::Entry::Vacant};

impl WsChatServer {
    pub fn is_valid_room_name(name: &str) -> bool {
        let trimmed = name.trim();
        !trimmed.is_empty()
            && trimmed.chars().count() <= 64
            && trimmed
                .chars()
                .all(|c| c.is_alphanumeric() || c == '-' || c == '_' || c == ' ')
    }

    pub fn take_room(&mut self, session_id: &str, room_name: &str) -> Option<Room> {
        log::debug!(target: "Websocket","Getting room: {room_name}");
        let session_id = self.rooms.get_mut(session_id)?;
        let room = session_id.get_mut(room_name)?;
        let room = std::mem::take(room);
        Some(room)
    }

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

    pub fn send_join_message(
        &mut self,
        session_id: &str,
        room_name: &str,
        msg: &str,
        _src: usize,
    ) -> Option<()> {
        log::debug!(
            target: "Websocket",
            "Sending join message to room {room_name}: {msg}"
        );

        if let Some(room) = self.rooms.get_mut(session_id)?.get_mut(room_name) {
            let client_ids: Vec<usize> = room.keys().cloned().collect();

            for id in client_ids {
                if let Some(client) = room.get(&id) {
                    if client.tx.send(msg.to_owned()).is_ok() {
                        log::debug!(
                            target: "Websocket",
                            "Join Message sent to client {id}, staying in room: {room_name}"
                        );
                    } else {
                        log::debug!(
                            target: "Websocket",
                            "Failed to send join message to client {id}, removing from room: {room_name}"
                        );
                        room.remove(&id);
                    }
                }
            }

            Some(())
        } else {
            log::debug!(
                target: "Websocket",
                "Room {room_name} not found in session {session_id}"
            );
            None
        }
    }

    pub fn broadcast_room_list(&self, session_id: &str) {
        if let Some(users) = self.rooms.get(session_id) {
            let room_list = users.keys().cloned().collect::<Vec<String>>().join(", ");
            let message = format!("{WS_PREFIX_SYSTEM_ROOMS} {room_list}");

            for room in users.values() {
                for client in room.values() {
                    if client.tx.send(message.clone()).is_err() {
                        log::debug!(
                            target: "Websocket",
                            "Failed to send room list to {}: client may have disconnected",
                            client.name
                        );
                    }
                }
            }
        }
    }

    pub fn broadcast_room_members(&self, session_id: &str, room_name: &str) {
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

            for client_metadata in room.values() {
                if client_metadata.tx.send(member_message.clone()).is_err() {
                    log::debug!(
                        target: "Websocket",
                        "Failed to send member list to client {}, client may have disconnected",
                        client_metadata.name
                    );
                }
            }
        }
    }

    pub fn remove_empty_rooms(&mut self, session_id: &str) {
        if let Some(rooms) = self.rooms.get_mut(session_id) {
            rooms.retain(|name, room| !room.is_empty() || name == "main");

            let total_users = rooms.values().flat_map(|r| r.keys()).count();
            if total_users == 0 {
                self.rooms.remove(session_id);
                log::debug!(
                    target: "Websocket",
                    "Session {session_id} has no more users and is being removed"
                );
            }
        }
        self.broadcast_room_list(session_id);
    }

    pub fn start_cleanup_interval(&self, ctx: &mut Context<Self>) {
        ctx.run_interval(CLEANUP_INTERVAL, |act, _| {
            act.cleanup_stale_sessions();
        });
    }

    fn cleanup_stale_sessions(&mut self) {
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
    }

    pub fn users_share_room(&self, session_id: &str, user1: &str, user2: &str) -> bool {
        if let Some(rooms) = self.rooms.get(session_id) {
            for room in rooms.values() {
                let user1_in_room = room.values().any(|cm| cm.name == user1);
                let user2_in_room = room.values().any(|cm| cm.name == user2);

                if user1_in_room && user2_in_room {
                    return true;
                }
            }
        }
        false
    }

    pub fn relay_message_to_user(
        &self,
        session_id: &str,
        to_user: &str,
        message: String,
        from_user: &str,
    ) {
        if to_user == from_user {
            log::debug!(
                target: "Websocket",
                "Skipping self-relay from {from_user} to {to_user}"
            );
            return;
        }

        if let Some(rooms) = self.rooms.get(session_id) {
            for room in rooms.values() {
                for client in room.values() {
                    if client.name == to_user {
                        if let Err(e) = client.tx.send(message) {
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
                        return;
                    }
                }
            }
        }

        log::debug!(
            target: "Websocket",
            "Could not find target user {to_user} in session {session_id} to relay message from {from_user}"
        );
    }
}

impl Actor for WsChatServer {
    type Context = Context<Self>;

    fn started(&mut self, ctx: &mut Self::Context) {
        self.start_cleanup_interval(ctx);
    }
}

impl SystemService for WsChatServer {
    fn service_started(&mut self, _ctx: &mut Context<Self>) {
        log::info!(target: "Websocket","WsChatServer started");
    }
}

impl Supervised for WsChatServer {
    fn restarting(&mut self, _ctx: &mut Context<Self>) {
        log::info!(target: "Websocket","WsChatServer restarting");
    }
}
