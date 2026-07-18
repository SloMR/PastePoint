use std::time::Duration;

// WebSocket frame and message size limits
pub const MAX_FRAME_SIZE: usize = 64 * 1024;
pub const MAX_SIGNAL_SIZE: usize = 128 * 1024;

// Continuation frames can be used for messages larger than MAX_SIGNAL_SIZE, but we set a reasonable upper limit
pub(crate) const MAX_CONTINUATION_SIZE: usize = MAX_SIGNAL_SIZE * 2;

// Channel capacities
pub(crate) const OUTBOUND_CHANNEL_CAPACITY: usize = 256;

// Default room name
pub(crate) const DEFAULT_ROOM: &str = "main";

// Security limits
pub(crate) const MAX_ROOMS_PER_SESSION: usize = 50;
pub(crate) const MAX_SESSIONS: usize = 100_000;
pub(crate) const MAX_WS_MESSAGES_PER_SEC: usize = 30;

// Timing intervals
pub const KEEP_ALIVE_INTERVAL: Duration = Duration::from_secs(3600);
pub const HEARTBEAT_INTERVAL: Duration = Duration::from_secs(5);
pub const HEARTBEAT_TIMEOUT: Duration = Duration::from_secs(15);
pub const SESSION_EXPIRATION_TIME: Duration = Duration::from_secs(60);
pub const CLEANUP_INTERVAL: Duration = Duration::from_secs(3600);

// Session configuration
pub const SESSION_CODE_LENGTH: usize = 10;
pub const SAFE_CHARSET: &[u8] = b"ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz23456789";

// HTTP configuration
pub const CORS_MAX_AGE: usize = 3600;
pub const CONTENT_TYPE_TEXT_PLAIN: &str = "text/plain; charset=utf-8";
pub const MIN_USER_AGENT_LENGTH: usize = 5;

// WebSocket message prefixes
pub const WS_PREFIX_KEEP_ALIVE: &str = "[KeepAlive]";
pub const WS_PREFIX_SYSTEM_ERROR: &str = "[SystemError]";
pub const WS_PREFIX_SYSTEM_ROOMS: &str = "[SystemRooms]";
pub const WS_PREFIX_SYSTEM_NAME: &str = "[SystemName]";
pub const WS_PREFIX_SYSTEM_JOIN: &str = "[SystemJoin]";
pub const WS_PREFIX_SYSTEM_MEMBERS: &str = "[SystemMembers]";
pub const WS_PREFIX_SIGNAL_MESSAGE: &str = "[SignalMessage]";
pub const WS_PREFIX_USER_COMMAND: &str = "[UserCommand]";
pub const WS_PREFIX_USER_DISCONNECTED: &str = "[UserDisconnected]";
