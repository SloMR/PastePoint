// File transfer constants
export const KB = 1024;
export const MB = 1024 * KB;

// Note: WebRTC SCTP has a ~256KB message limit. Chunk data + protocol header
// (~64 bytes) must stay under it, so 192KB is the largest safe chunk.
export const CHUNK_SIZE = 192 * KB;
export const MAX_BUFFERED_AMOUNT = 16 * MB;
export const BUFFERED_AMOUNT_LOW_THRESHOLD = 8 * MB;

// Heartbeat constants
export const HEARTBEAT_INTERVAL_DESKTOP_SEC = 60;
export const HEARTBEAT_TIMEOUT_DESKTOP_SEC = 120;
export const HEARTBEAT_INTERVAL_MOBILE_SEC = 10;
export const HEARTBEAT_TIMEOUT_MOBILE_SEC = 30;

// WebSocket keepalive — sent every 25 seconds to prevent idle timeouts on the server and intermediate proxies
export const WS_PREFIX_KEEP_ALIVE = '[KeepAlive]';
export const WS_KEEP_ALIVE_INTERVAL_MS = 25_000;

// Local storage keys
export const SESSION_CODE_KEY = 'session_code';
export const LANGUAGE_PREFERENCE_KEY = 'language_preference';
export const APP_VERSION_KEY = 'app_version';

export const SUPPORT_EMAIL = 'support@pastepoint.com';
export const THEME_PREFERENCE_KEY = 'theme_preference';
export const UPDATE_LAST_PROMPT_KEY = 'update_last_prompt_at';
export const NAVIGATION_DELAY_MS = 100;

// Client update check
export const UPDATE_OPTIONAL_THROTTLE_MS = 12 * 60 * 60 * 1000; // 12h

// Inactivity timeout constants
export const IDLE_TIMEOUT = 12 * 60 * 60 * 1000; // 12 hours
export const BACKGROUND_EXPIRY_THRESHOLD = 5 * 60 * 1000; // 5 minutes
export const CONNECTION_WARNING_DELAY_MS = 25_000; // 25 seconds before showing connection warning

// WebRTC constants
export const MAX_RECONNECT_ATTEMPTS = 5;
export const RECONNECT_DELAY = 2000;
export const ICE_GATHERING_TIMEOUT = 30000;
export const CONNECTION_REQUEST_TIMEOUT = 15000;
export const CONNECTION_ESTABLISH_TIMEOUT = 8000;
export const MAX_PREVIEW_DATA_URL_SIZE = 150 * KB;
export const PREVIEW_MIME_TYPE = 'image/jpeg';
export const PREVIEW_QUALITY = 0.7;

export const OFFER_OPTIONS = {
  offerToReceiveAudio: false,
  offerToReceiveVideo: false,
};

export const RTC_SIGNALING_STATES = {
  CLOSED: 'closed',
  HAVE_LOCAL_OFFER: 'have-local-offer',
  HAVE_LOCAL_PRANSWER: 'have-local-pranswer',
  HAVE_REMOTE_OFFER: 'have-remote-offer',
  HAVE_REMOTE_PRANSWER: 'have-remote-pranswer',
  STABLE: 'stable',
} as const;

// Public STUN servers only.
export const ICE_SERVERS: RTCIceServer[] = [
  { urls: 'stun:stun.l.google.com:19302' },
  { urls: 'stun:stun.cloudflare.com:3478' },
  { urls: 'stun:global.stun.twilio.com:3478' },
];

export const RTC_CONFIGURATION = {
  iceServers: ICE_SERVERS,
  iceTransportPolicy: 'all' as RTCIceTransportPolicy,
  bundlePolicy: 'max-bundle' as RTCBundlePolicy,
  rtcpMuxPolicy: 'require' as RTCRtcpMuxPolicy,
  iceCandidatePoolSize: 10,
};

// WebRTC data channel constants
export const DATA_CHANNEL_OPTIONS = {
  ordered: true,
};

// WebRTC signaling message types
export const SIGNAL_MESSAGE_TYPES = {
  OFFER: 'offer',
  ANSWER: 'answer',
  CANDIDATE: 'candidate',
  FILE_OFFER: 'file-offer',
  FILE_RESPONSE: 'file-response',
};

export enum SignalMessageType {
  OFFER = 'offer',
  ANSWER = 'answer',
  CANDIDATE = 'candidate',
  CONNECTION_REQUEST = 'connection_request',
}

export interface SignalMessage {
  type: SignalMessageType;
  data: unknown;
  from: string;
  to: string;
  sequence?: number;
}

export interface DataChannelMessage {
  type: string;
  payload: unknown;
}

// WebRTC file transfer message types
export const FILE_TRANSFER_MESSAGE_TYPES = {
  FILE_CHUNK: 'file-chunk',
  FILE_ACCEPT: 'file-accept',
  FILE_DECLINE: 'file-decline',
  FILE_OFFER: 'file-offer',
  FILE_CANCEL_UPLOAD: 'file-cancel-upload',
  FILE_CANCEL_DOWNLOAD: 'file-cancel-download',
  FILE_RECEIVED: 'file-received',
};

// WebRTC data channel message types
export const DATA_CHANNEL_MESSAGE_TYPES = {
  CHAT: 'chat',
  FILE: 'file',
};

// Chat message interface
export enum ChatMessageType {
  TEXT = 'text',
  ATTACHMENT = 'attachment',
}

// Per-peer connection state for the member dot (green / yellow / red).
export type MemberConnectionState = 'connected' | 'connecting' | 'disconnected';

export interface FileTransferData {
  fileId: string;
  fileName: string;
  fileSize: number;
  fromUser: string;
  status: FileTransferStatus;
  groupId?: string;
  deliveredCount?: number;
  recipientCount?: number;
}

export interface ChatMessage {
  from: string;
  text: string;
  type: ChatMessageType;
  timestamp: Date;
  fileTransfer?: FileTransferData;
  previewUrl?: string;
  previewMime?: string;
  isMine?: boolean;
}

// File transfer interfaces
export enum FileTransferStatus {
  PENDING = 'pending',
  ACCEPTED = 'accepted',
  DECLINED = 'declined',
  COMPLETED = 'completed',
  CANCELLED = 'cancelled',
  FAILED = 'failed',
}

export interface FileUpload {
  fileId: string;
  file: File;
  currentOffset: number;
  isPaused: boolean;
  targetUser: string;
  progress: number;
  phase: 'sending' | 'finalizing';
  groupId: string;
}

export interface FileDownload {
  fileId: string;
  fileName: string;
  fileSize: number;
  fromUser: string;
  receivedSize: number;
  receivedChunks: Map<number, Blob>; // Using Blob for memory efficiency (can be disk-backed)
  totalChunks: number;
  progress: number;
  isAccepted: boolean;
  lastActivity: number;
  previewDataUrl?: string;
  previewMime?: string;
  expectedHash?: string;
}

// Metadata configuration interfaces
/**
 * Configuration interface for metadata settings
 */
export interface MetaConfig {
  title?: string;
  description?: string;
  keywords?: string;
  author?: string;
  canonical?: string;
  robots?: string;
  themeColor?: string;

  // Viewport configuration for responsive design
  viewport?: string;

  // Cache control headers
  cacheControl?: {
    pragma?: string;
    cacheControl?: string;
    expires?: string;
  };

  // Open Graph
  og?: {
    title?: string;
    description?: string;
    type?: string;
    url?: string;
    image?: string;
    siteName?: string;
  };

  // Twitter Cards
  twitter?: {
    card?: string;
    title?: string;
    description?: string;
    image?: string;
    site?: string;
    creator?: string;
  };
}

/**
 * Interface for structured data (JSON-LD)
 */
export interface StructuredData {
  [key: string]: unknown;
}
