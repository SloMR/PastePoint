use crate::{
    HEARTBEAT_INTERVAL, HEARTBEAT_TIMEOUT, SessionStore, WS_PREFIX_KEEP_ALIVE,
    WS_PREFIX_SIGNAL_MESSAGE, WS_PREFIX_SYSTEM_ERROR, WS_PREFIX_SYSTEM_NAME,
    WS_PREFIX_SYSTEM_ROOMS, WS_PREFIX_USER_COMMAND, WS_PREFIX_USER_DISCONNECTED,
    chat_server::{ChatServerHandle, Client, WsChatServer},
    consts::{
        DEFAULT_ROOM, MAX_CONTINUATION_SIZE, MAX_FRAME_SIZE, MAX_SIGNAL_SIZE,
        MAX_WS_MESSAGES_PER_SEC,
    },
    error::ServerError,
};
use actix_ws::{AggregatedMessage, MessageStream, Session};
use fake::{
    Fake,
    faker::name::{en::FirstName, en::LastName},
};
use futures_util::StreamExt;
use serde_json::Value;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::Receiver;
use tokio::time::MissedTickBehavior;

/// Per-connection state for one WebSocket client, driven by [`WsChatSession::run`].
pub(crate) struct WsChatSession {
    session_id: String,              // session id
    id: usize,                       // client id
    room: String,                    // room name
    name: String,                    // client name
    auto_join: bool,                 // flag to control auto-join
    session_store: SessionStore,     // reference to SessionStore
    last_heartbeat: Option<Instant>, // last heartbeat time
    message_count: usize,            // rate limiting: messages in current window
    rate_limit_reset: Instant,       // rate limiting: when to reset counter
}

/// A parsed `[UserCommand]` sent by a client.
enum UserCommand<'a> {
    /// `/list` — list rooms in the session.
    List,
    /// `/join <room>` — `None` when no room name was supplied.
    Join(Option<&'a str>),
    /// `/name` — echo the client's assigned name.
    Name,
    /// Anything unrecognized.
    Unknown,
}

impl<'a> UserCommand<'a> {
    fn parse(input: &'a str) -> Self {
        let mut parts = input.trim().splitn(2, ' ');
        match parts.next().unwrap_or("") {
            "/list" => UserCommand::List,
            "/join" => UserCommand::Join(parts.next().map(str::trim)),
            "/name" => UserCommand::Name,
            _ => UserCommand::Unknown,
        }
    }
}

impl WsChatSession {
    pub(crate) fn new(session_id: &str, auto_join: bool, session_store: SessionStore) -> Self {
        let first_name = FirstName().fake::<String>();
        let last_name = LastName().fake::<String>();
        let name = format!("{first_name} {last_name}");

        WsChatSession {
            session_id: session_id.to_owned(),
            id: 0,
            room: "".to_owned(),
            name,
            auto_join,
            session_store,
            last_heartbeat: None,
            message_count: 0,
            rate_limit_reset: Instant::now() + Duration::from_secs(1),
        }
    }

    pub(crate) async fn run(
        mut self,
        mut session: Session,
        msg_stream: MessageStream,
        mut outbound: Receiver<String>,
        tx: Client,
        server: ChatServerHandle,
    ) {
        let mut stream = msg_stream
            .max_frame_size(MAX_FRAME_SIZE)
            .aggregate_continuations()
            .max_continuation_size(MAX_CONTINUATION_SIZE);

        log::debug!(
            target: "Websocket",
            "Session started for {} with ID {}",
            self.name,
            self.id
        );
        log::debug!(target: "Websocket", "Auto-join is set to: {}", self.auto_join);

        self.last_heartbeat = Some(Instant::now());
        if self.auto_join {
            self.join_room(DEFAULT_ROOM, &server, &tx);
        }

        let mut heartbeat = tokio::time::interval_at(
            tokio::time::Instant::now() + HEARTBEAT_INTERVAL,
            HEARTBEAT_INTERVAL,
        );
        // Don't replay missed ticks back-to-back after a stall; keep the cadence.
        heartbeat.set_missed_tick_behavior(MissedTickBehavior::Delay);

        let close_reason = loop {
            tokio::select! {
                // Outbound: messages the server pushed for this client.
                outgoing = outbound.recv() => {
                    match outgoing {
                        Some(text) => {
                            if session.text(text).await.is_err() {
                                break None;
                            }
                        }
                        // All senders dropped; nothing more to deliver.
                        None => break None,
                    }
                }

                // Inbound: frames received from the client.
                incoming = stream.next() => {
                    match incoming {
                        Some(Ok(AggregatedMessage::Text(text))) => {
                            self.handle_text(&text, &server, &tx);
                        }
                        Some(Ok(AggregatedMessage::Ping(bytes))) => {
                            log::debug!(target: "Websocket", "Received ping message");
                            self.last_heartbeat = Some(Instant::now());
                            if session.pong(&bytes).await.is_err() {
                                break None;
                            }
                        }
                        Some(Ok(AggregatedMessage::Pong(_))) => {
                            log::debug!(target: "Websocket", "Received pong message");
                            self.last_heartbeat = Some(Instant::now());
                        }
                        Some(Ok(AggregatedMessage::Close(reason))) => {
                            log::debug!(target: "Websocket", "Closing connection: {reason:?}");
                            break reason;
                        }
                        // Binary frames are unused by the signaling protocol.
                        Some(Ok(_)) => {}
                        Some(Err(e)) => {
                            log::warn!(target: "Websocket", "WebSocket protocol error: {e}");
                            Self::deliver(&tx, format!(
                                "{} Invalid message format: {}",
                                WS_PREFIX_SYSTEM_ERROR,
                                ServerError::InternalServerError
                            ));
                            break None;
                        }
                        None => break None,
                    }
                }

                // Heartbeat: ping the client and enforce the timeout.
                _ = heartbeat.tick() => {
                    if let Some(last) = self.last_heartbeat
                        && Instant::now().duration_since(last) > HEARTBEAT_TIMEOUT
                    {
                        log::debug!(
                            target: "Websocket",
                            "Heartbeat failed for user {}, disconnecting!",
                            self.name
                        );
                        break None;
                    }
                    log::debug!(target: "Websocket", "Sending heartbeat to user {}", self.name);
                    if session.ping(b"").await.is_err() {
                        break None;
                    }
                }
            }
        };

        // Flush any frames still queued for this client before closing the connection.
        while let Ok(text) = outbound.try_recv() {
            if session.text(text).await.is_err() {
                break;
            }
        }

        self.on_stop(&server);
        let _ = session.close(close_reason).await;
    }

    fn join_room(&mut self, room_name: &str, server: &ChatServerHandle, tx: &Client) {
        if self.room == room_name {
            log::debug!(
                target: "Websocket",
                "User '{}' is already in room '{}'. Skipping join.",
                self.name,
                room_name
            );
            return;
        }

        let new_id = server.join_room(&self.session_id, room_name, &self.name, tx.clone());
        if new_id == 0 {
            log::warn!(
                target: "Websocket",
                "Join rejected for room '{}'; user '{}' stays in '{}'",
                room_name,
                self.name,
                self.room
            );
            return;
        }

        server.leave_room(&self.session_id, &self.room, self.id);
        self.id = new_id;
        self.room = room_name.to_owned();
        log::debug!(
            target: "Websocket",
            "{} successfully joined room '{}'",
            self.session_id,
            room_name
        );
    }

    fn list_rooms(&self, server: &ChatServerHandle, tx: &Client) {
        let rooms = server.list_rooms(&self.session_id);
        log::debug!(target: "Websocket", "{WS_PREFIX_SYSTEM_ROOMS} Rooms Available: {rooms:?}");
        let room_list = rooms.join(", ");
        Self::deliver(tx, format!("{WS_PREFIX_SYSTEM_ROOMS} {room_list}"));
    }

    fn user_command(&mut self, command_str: &str, server: &ChatServerHandle, tx: &Client) {
        log::debug!(target: "Websocket", "Processing command: '{}'", command_str.trim());

        match UserCommand::parse(command_str) {
            UserCommand::List => {
                log::debug!(target: "Websocket", "Received list command");
                self.list_rooms(server, tx);
            }
            UserCommand::Join(Some(room_name)) if WsChatServer::is_valid_room_name(room_name) => {
                log::debug!(target: "Websocket", "Received join command for room '{room_name}'");
                self.join_room(room_name, server, tx);
            }
            UserCommand::Join(Some(_)) => {
                Self::deliver(
                    tx,
                    format!(
                        "{WS_PREFIX_SYSTEM_ERROR} Invalid room name. Must be 1-64 letters, digits, hyphens, underscores, or spaces only."
                    ),
                );
            }
            UserCommand::Join(None) => {
                Self::deliver(
                    tx,
                    format!("{WS_PREFIX_SYSTEM_ERROR} Room name is required"),
                );
            }
            UserCommand::Name => {
                log::debug!(target: "Websocket", "Received name command");
                Self::deliver(tx, format!("{} {}", WS_PREFIX_SYSTEM_NAME, self.name));
            }
            UserCommand::Unknown => {
                log::debug!(target: "Websocket", "Unknown command: '{}'", command_str.trim());
                Self::deliver(
                    tx,
                    format!(
                        "{} Error Unknown command: {}",
                        WS_PREFIX_SYSTEM_ERROR,
                        ServerError::NotFound
                    ),
                );
            }
        }
    }

    fn handle_signal_message(&self, msg: &str, server: &ChatServerHandle, tx: &Client) {
        // 1. Size validation
        if msg.len() > MAX_SIGNAL_SIZE {
            log::warn!(
                target: "Websocket",
                "Oversize signaling message ({} bytes) from user {}",
                msg.len(),
                self.name
            );
            Self::deliver(
                tx,
                format!("{WS_PREFIX_SYSTEM_ERROR} Signal message too large"),
            );
            return;
        }

        // 2. Parse and validate the message
        let payload = msg.trim_start_matches(WS_PREFIX_SIGNAL_MESSAGE).trim();
        let value = match serde_json::from_str::<Value>(payload) {
            Ok(v) => v,
            Err(e) => {
                log::warn!(target: "Websocket", "Invalid signal JSON from {}: {}", self.name, e);
                Self::deliver(
                    tx,
                    format!("{WS_PREFIX_SYSTEM_ERROR} Invalid signaling message format"),
                );
                return;
            }
        };

        // 3. Validate target user
        let to_user = match value.get("to").and_then(|v| v.as_str()) {
            Some(user) => user,
            None => {
                log::warn!(target: "Websocket", "Signal missing 'to' field from {}", self.name);
                Self::deliver(
                    tx,
                    format!("{WS_PREFIX_SYSTEM_ERROR} Signaling message missing 'to' field"),
                );
                return;
            }
        };

        // 4. Validate room membership and relay through the shared server.
        server.validate_and_relay_signal(&self.session_id, &self.name, to_user, payload);
    }

    fn handle_user_disconnect(&self, server: &ChatServerHandle) {
        server.leave_room(&self.session_id, &self.room, self.id);
        log::debug!(target: "Websocket", "User {} disconnected", self.name);
    }

    fn handle_text(&mut self, text: &str, server: &ChatServerHandle, tx: &Client) {
        let now = Instant::now();
        if now > self.rate_limit_reset {
            self.message_count = 0;
            self.rate_limit_reset = now + Duration::from_secs(1);
        }
        self.message_count += 1;
        if self.message_count > MAX_WS_MESSAGES_PER_SEC {
            log::warn!(
                target: "Websocket",
                "Rate limit exceeded for user {}, dropping message",
                self.name
            );
            return;
        }

        let msg = text.trim();
        log::debug!(target: "Websocket", "Received message: '{msg}'");
        if msg.starts_with(WS_PREFIX_SIGNAL_MESSAGE) {
            self.handle_signal_message(msg, server, tx);
        } else if msg.starts_with(WS_PREFIX_USER_COMMAND) {
            let command_str = msg.trim_start_matches(WS_PREFIX_USER_COMMAND).trim();
            log::debug!(target: "Websocket", "Command string after trimming: '{command_str}'");
            self.user_command(command_str, server, tx);
        } else if msg.starts_with(WS_PREFIX_USER_DISCONNECTED) {
            log::debug!(target: "Websocket", "Received disconnect command");
            self.handle_user_disconnect(server);
        } else if msg.starts_with(WS_PREFIX_KEEP_ALIVE) {
            // Client-side keepalive ping
            log::debug!(target: "Websocket", "Keep-alive from {}", self.name);
        } else {
            log::debug!(target: "Websocket", "Unknown command: {msg}");
            Self::deliver(
                tx,
                format!(
                    "{} Error Unknown command: {}",
                    WS_PREFIX_SYSTEM_ERROR,
                    ServerError::NotFound
                ),
            );
        }
    }

    /// Connection teardown, formerly the actor's `stopped` hook.
    fn on_stop(&self, server: &ChatServerHandle) {
        log::debug!(
            target: "Websocket",
            "WsChatSession closed for {}({}) in room {}",
            self.name,
            self.id,
            self.room
        );

        if !self.room.is_empty() {
            self.handle_user_disconnect(server);
            log::debug!(
                target: "Websocket",
                "Sent LeaveRoom message for user {} leaving room {}",
                self.name,
                self.room
            );
        }

        if let Ok(uuid) = uuid::Uuid::parse_str(&self.session_id) {
            log::debug!(target: "Websocket", "Removing client {uuid} from session");
            self.session_store.remove_client(&uuid);
        } else {
            log::debug!(
                target: "Websocket",
                "Invalid UUID format for session_id: {}",
                self.session_id
            );
        }
    }

    fn deliver(tx: &Client, msg: String) {
        if tx.try_send(msg).is_err() {
            log::debug!(target: "Websocket", "Dropped outbound frame: client channel full or closed");
        }
    }
}
