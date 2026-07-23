#![warn(unreachable_pub)]

mod chat_server;
mod config;
mod consts;
mod error;
mod routes;
mod session;
mod session_store;

pub use chat_server::{ChatServerHandle, WsChatServer};
pub use config::{ClientVersionConfig, SentryConfig, ServerConfig, TurnConfig};
pub use consts::{
    CLEANUP_INTERVAL, CONTENT_TYPE_TEXT_PLAIN, CORS_MAX_AGE, HEARTBEAT_INTERVAL, HEARTBEAT_TIMEOUT,
    KEEP_ALIVE_INTERVAL, MAX_FRAME_SIZE, MAX_SIGNAL_SIZE, MIN_USER_AGENT_LENGTH, SAFE_CHARSET,
    SESSION_CODE_LENGTH, SESSION_EXPIRATION_TIME, WS_PREFIX_KEEP_ALIVE, WS_PREFIX_SIGNAL_MESSAGE,
    WS_PREFIX_SYSTEM_ERROR, WS_PREFIX_SYSTEM_JOIN, WS_PREFIX_SYSTEM_MEMBERS, WS_PREFIX_SYSTEM_NAME,
    WS_PREFIX_SYSTEM_ROOMS, WS_PREFIX_USER_COMMAND, WS_PREFIX_USER_DISCONNECTED,
};
pub use error::ServerError;
pub use routes::{
    chat_ws, create_session, health, index, private_chat_ws, turn_credentials, version,
};
pub use session_store::SessionStore;
