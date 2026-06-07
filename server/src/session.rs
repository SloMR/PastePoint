use crate::{
    HEARTBEAT_INTERVAL, HEARTBEAT_TIMEOUT, SessionStore, WS_PREFIX_KEEP_ALIVE,
    WS_PREFIX_SIGNAL_MESSAGE, WS_PREFIX_SYSTEM_ERROR, WS_PREFIX_SYSTEM_NAME,
    WS_PREFIX_SYSTEM_ROOMS, WS_PREFIX_USER_COMMAND, WS_PREFIX_USER_DISCONNECTED,
    consts::{MAX_FRAME_SIZE, MAX_SIGNAL_SIZE, MAX_WS_MESSAGES_PER_SEC},
    error::ServerError,
    message::{
        Client, JoinRoom, LeaveRoom, ListRooms, ValidateAndRelaySignal, WsChatServer, WsChatSession,
    },
};
use actix::Addr;
use actix_ws::{AggregatedMessage, MessageStream, Session};
use fake::{
    Fake,
    faker::name::{en::FirstName, en::LastName},
};
use futures_util::StreamExt;
use rand::{RngExt, rng};
use serde_json::Value;
use std::time::{Duration, Instant};
use tokio::sync::mpsc::UnboundedReceiver;

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
    pub fn new(session_id: &str, auto_join: bool, session_store: SessionStore) -> Self {
        let id = rng().random_range(0..usize::MAX);
        let first_name = FirstName().fake::<String>();
        let last_name = LastName().fake::<String>();
        let name = format!("{first_name} {last_name}");

        WsChatSession {
            session_id: session_id.to_owned(),
            id,
            room: "".to_owned(),
            name,
            auto_join,
            session_store,
            last_heartbeat: None,
            message_count: 0,
            rate_limit_reset: Instant::now() + Duration::from_secs(1),
        }
    }

    pub async fn run(
        mut self,
        mut session: Session,
        msg_stream: MessageStream,
        mut outbound: UnboundedReceiver<String>,
        tx: Client,
        server: Addr<WsChatServer>,
    ) {
        let mut stream = msg_stream
            .max_frame_size(MAX_FRAME_SIZE)
            .aggregate_continuations()
            .max_continuation_size(MAX_SIGNAL_SIZE);

        log::debug!(
            target: "Websocket",
            "Session started for {} with ID {}",
            self.name,
            self.id
        );
        log::debug!(target: "Websocket", "Auto-join is set to: {}", self.auto_join);

        self.last_heartbeat = Some(Instant::now());
        if self.auto_join {
            self.join_room("main", &server, &tx).await;
        }

        let mut heartbeat = tokio::time::interval_at(
            tokio::time::Instant::now() + HEARTBEAT_INTERVAL,
            HEARTBEAT_INTERVAL,
        );

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
                            self.handle_text(&text, &server, &tx).await;
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

        self.on_stop(&server);
        let _ = session.close(close_reason).await;
    }

    async fn join_room(&mut self, room_name: &str, server: &Addr<WsChatServer>, tx: &Client) {
        if self.room == room_name {
            log::debug!(
                target: "Websocket",
                "User '{}' is already in room '{}'. Skipping join.",
                self.name,
                room_name
            );
            return;
        }

        let leave_msg = LeaveRoom(self.session_id.clone(), self.room.clone(), self.id);
        if let Err(e) = server.send(leave_msg).await {
            log::warn!(
                target: "Websocket",
                "Failed to deliver LeaveRoom to server for {}: {e}",
                self.name
            );
        }

        let join_msg = JoinRoom(
            self.session_id.clone(),
            room_name.to_owned(),
            self.name.clone(),
            tx.clone(),
        );

        match server.send(join_msg).await {
            Ok(id) => {
                log::debug!(
                    target: "Websocket",
                    "{} successfully joined room '{}'",
                    self.session_id,
                    room_name
                );
                self.id = id;
                self.room = room_name.to_owned();
            }
            Err(e) => {
                log::warn!(
                    target: "Websocket",
                    "Failed to join room '{room_name}' for {}: {e}",
                    self.name
                );
            }
        }
    }

    async fn list_rooms(&self, server: &Addr<WsChatServer>, tx: &Client) {
        match server.send(ListRooms(self.session_id.clone())).await {
            Ok(rooms) => {
                log::debug!(target: "Websocket", "{WS_PREFIX_SYSTEM_ROOMS} Rooms Available: {rooms:?}");
                let room_list = rooms.join(", ");
                Self::deliver(tx, format!("{WS_PREFIX_SYSTEM_ROOMS} {room_list}"));
            }
            Err(e) => {
                log::warn!(target: "Websocket", "Failed to retrieve room list: {e}");
                Self::deliver(
                    tx,
                    format!("{WS_PREFIX_SYSTEM_ERROR} Failed to retrieve room list."),
                );
            }
        }
    }

    async fn user_command(&mut self, command_str: &str, server: &Addr<WsChatServer>, tx: &Client) {
        log::debug!(target: "Websocket", "Processing command: '{}'", command_str.trim());

        match UserCommand::parse(command_str) {
            UserCommand::List => {
                log::debug!(target: "Websocket", "Received list command");
                self.list_rooms(server, tx).await;
            }
            UserCommand::Join(Some(room_name)) if WsChatServer::is_valid_room_name(room_name) => {
                log::debug!(target: "Websocket", "Received join command for room '{room_name}'");
                self.join_room(room_name, server, tx).await;
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

    fn handle_signal_message(&self, msg: &str, server: &Addr<WsChatServer>, tx: &Client) {
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

        // 4. Send validation and relay message to server instead of trying to check here
        server.do_send(ValidateAndRelaySignal {
            session_id: self.session_id.clone(),
            from_user: self.name.clone(),
            to_user: to_user.to_string(),
            payload: payload.to_string(),
        });
    }

    fn handle_user_disconnect(&self, server: &Addr<WsChatServer>) {
        let leave_msg = LeaveRoom(self.session_id.clone(), self.room.clone(), self.id);
        server.do_send(leave_msg);
        log::debug!(target: "Websocket", "User {} disconnected", self.name);
    }

    async fn handle_text(&mut self, text: &str, server: &Addr<WsChatServer>, tx: &Client) {
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
            self.user_command(command_str, server, tx).await;
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
    fn on_stop(&self, server: &Addr<WsChatServer>) {
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
        if tx.send(msg).is_err() {
            log::debug!(target: "Websocket", "Dropped outbound frame: client channel already closed");
        }
    }
}
