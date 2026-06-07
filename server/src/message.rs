use crate::SessionStore;
use actix::prelude::*;
use std::{collections::HashMap, time::Instant};
use tokio::sync::mpsc::UnboundedSender;

pub type Client = UnboundedSender<String>;
pub type Room = HashMap<usize, ClientMetadata>;

#[derive(Default)]
pub struct WsChatServer {
    pub rooms: HashMap<String, HashMap<String, Room>>, // session_id -> room_name -> clients
}

pub struct WsChatSession {
    pub session_id: String,              // session id
    pub id: usize,                       // client id
    pub room: String,                    // room name
    pub name: String,                    // client name
    pub auto_join: bool,                 // flag to control auto-join
    pub session_store: SessionStore,     // reference to SessionStore
    pub last_heartbeat: Option<Instant>, // last heartbeat time
    pub message_count: usize,            // rate limiting: messages in current window
    pub rate_limit_reset: Instant,       // rate limiting: when to reset counter
}

pub struct ClientMetadata {
    pub tx: Client,   // outbound channel to the client
    pub name: String, // client name
}

#[derive(Clone, Message)]
#[rtype(result = "usize")]
pub struct JoinRoom(
    pub String, // session_id
    pub String, // room_name
    pub String, // client_name
    pub Client, // outbound channel to the client
);

#[derive(Clone, Message)]
#[rtype(result = "()")]
pub struct LeaveRoom(
    pub String, // session_id
    pub String, // room_name
    pub usize,  // id
);

#[derive(Clone, Message)]
#[rtype(result = "Vec<String>")]
pub struct ListRooms(pub String /* session_id */);

#[derive(Message)]
#[rtype(result = "()")]
pub struct RelaySignalMessage {
    pub(crate) session_id: String, // session_id
    pub(crate) from: String,       // from user
    pub(crate) to: String,         // to user
    pub(crate) message: String,    // signal message
}

#[derive(Message)]
#[rtype(result = "()")]
pub struct CleanupSession(pub String /* session_id */);

#[derive(Message)]
#[rtype(result = "()")]
pub struct ValidateAndRelaySignal {
    pub session_id: String,
    pub from_user: String,
    pub to_user: String,
    pub payload: String,
}
