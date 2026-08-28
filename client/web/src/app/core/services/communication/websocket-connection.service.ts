import { Injectable, PLATFORM_ID, OnDestroy, effect, inject } from '@angular/core';
import { BehaviorSubject, Subject } from 'rxjs';
import { TelemetryService, TelemetrySpan } from '../monitoring/telemetry.service';
import { environment } from '../../../../environments/environment';
import { NGXLogger } from 'ngx-logger';
import { isPlatformBrowser } from '@angular/common';
import { TranslateService } from '@ngx-translate/core';
import {
  SESSION_CODE_KEY,
  WS_PREFIX_KEEP_ALIVE,
  WS_KEEP_ALIVE_INTERVAL_MS,
} from '../../../utils/constants';
import { HotToastService } from '@ngxpert/hot-toast';
import { AppUpdateService } from '../update/app-update.service';
@Injectable({
  providedIn: 'root',
})
export class WebSocketConnectionService implements OnDestroy {
  private logger = inject(NGXLogger);
  private toaster = inject(HotToastService);
  private translate = inject<TranslateService>(TranslateService);
  private platformId = inject(PLATFORM_ID);
  private updateService = inject(AppUpdateService);
  private telemetry = inject(TelemetryService);

  /**
   * ==========================================================
   * PRIVATE PROPERTIES
   * Core WebSocket connection and configuration
   * ==========================================================
   */
  private socket: WebSocket | undefined;
  private webSocketProto = 'wss';
  private host = environment.apiUrl;
  private sessionCode: string | undefined;
  private reconnectAttempts = 0;
  private maxReconnectAttempts = 5;
  private reconnectDelay = 1000;
  private maxReconnectDelay = 30000;
  private reconnectTimer: ReturnType<typeof setTimeout> | null = null;
  private keepAliveTimer: ReturnType<typeof setInterval> | null = null;
  private manualDisconnect = false;
  private isConnecting = false;
  private isDisconnectedForUpdate = false;

  // For bfcache support
  private pageHideListener: (() => void) | undefined;
  private pageShowListener: (() => void) | undefined;

  /**
   * ==========================================================
   * PUBLIC OBSERVABLES
   * BehaviorSubjects for communication with other services
   * ==========================================================
   */
  public messages$ = new BehaviorSubject<string>('');
  public systemMessages$ = new BehaviorSubject<string>('');
  public signalMessages$ = new BehaviorSubject<unknown>(null);

  /** Fires once after a successful automatic reconnect. Services subscribe
   *  to this to refresh stale state (e.g. username) without polling. */
  public reconnected$ = new Subject<void>();

  /** Fires on every successful socket open (initial connect and reconnects).
   *  The launch splash waits on this to dismiss once we're online. */
  public connected$ = new Subject<void>();

  /** Live reconnect status (attempt # and when the next try fires), or `null`
   *  when connected / not retrying. Drives the server-reconnect banner. */
  public reconnectState$ = new BehaviorSubject<{ attempt: number; nextAttemptAt: number } | null>(
    null
  );

  /** Fires when a private session code is dropped after repeated failed
   *  reconnects so the UI can leave the /private/:code route. */
  public sessionFallback$ = new Subject<void>();

  /**
   * ==========================================================
   * CONSTRUCTOR
   * Dependency injection
   * ==========================================================
   */
  constructor() {
    if (isPlatformBrowser(this.platformId)) {
      this.setupBFCacheHandlers();
      this.setupUpdateGate();
    }
  }

  /** Tears down the connection while a required update is pending; resumes when it clears. */
  private setupUpdateGate(): void {
    effect(() => {
      const required = this.updateRequired();
      if (required && (this.isConnected() || this.isConnecting || this.reconnectTimer !== null)) {
        this.logger.warn('updateGate', 'Update required, disconnecting until the app is updated');
        this.telemetry.warnEvent('update.gate_blocked');
        this.isDisconnectedForUpdate = true;
        this.disconnect(false);
      } else if (!required && this.isDisconnectedForUpdate) {
        this.isDisconnectedForUpdate = false;
        this.connect(this.sessionCode).catch((err: unknown) => {
          this.logger.error('updateGate', `Reconnect after update gate cleared failed: ${err}`);
        });
      }
    });
  }

  private updateRequired(): boolean {
    return this.updateService.recommendation()?.kind === 'required';
  }

  /**
   * ==========================================================
   * BFCACHE SUPPORT
   * Setup handlers for page hide/show events to support bfcache
   * ==========================================================
   */
  private setupBFCacheHandlers(): void {
    // Handle page hide event (browser might store page in bfcache)
    this.pageHideListener = () => {
      this.logger.info('pageHide', 'Page entering bfcache, closing WebSocket temporarily');
      if (this.isConnected()) {
        // Store the session code for later reconnection
        this.sessionCode = this.sessionCode ?? this.getSessionCodeFromUrl();
        // Temporary disconnect without clearing session code
        this.temporaryDisconnect();
      }
    };

    // Handle page show event (page restored from bfcache)
    this.pageShowListener = () => {
      // Check if page was restored from bfcache
      if (this.sessionCode && !this.isConnected() && !this.isConnecting) {
        this.logger.info('pageShow', 'Page restored from bfcache, reconnecting WebSocket');
        this.connect(this.sessionCode).catch((err: unknown) => {
          this.logger.error('pageShow', `Failed to reconnect after bfcache: ${err}`);
          this.toaster.error(this.translate.instant('SESSION_RECONNECT_FAILED'));
        });
      }
    };

    // Add event listeners
    window.addEventListener('pagehide', this.pageHideListener);
    window.addEventListener('pageshow', this.pageShowListener);
  }

  /**
   * Get session code from URL if available
   */
  private getSessionCodeFromUrl(): string | undefined {
    const urlSegments = window.location.pathname.split('/');
    return urlSegments.length > 2 ? urlSegments[2] : undefined;
  }

  /**
   * Temporarily disconnect WebSocket without clearing session
   * Used for bfcache support
   */
  private temporaryDisconnect(): void {
    this.stopKeepAlive();
    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }

    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.logger.info('temporaryDisconnect', 'Closing WebSocket connection for bfcache.');
      this.socket.close();
      this.socket = undefined;
    }
  }

  /**
   * ==========================================================
   * CONNECTION MANAGEMENT
   * Methods for establishing and managing WebSocket connection
   * ==========================================================
   */
  public connect(code?: string): Promise<void> {
    if (this.updateRequired()) {
      this.logger.warn('connect', 'Update required, refusing to connect');
      return Promise.resolve();
    }

    if (this.isConnecting) {
      this.logger.warn('connect', 'Connection already in progress, ignoring duplicate request');
      return Promise.resolve();
    }

    if (this.isConnected() && this.sessionCode === code) {
      this.logger.info('connect', 'Already connected to this session, skipping connection');
      return Promise.resolve();
    }

    if (this.socket) {
      this.logger.info('connect', 'Disconnecting existing connection before creating a new one');
      this.disconnect(true);
      return new Promise((resolve) => {
        setTimeout(() => {
          void this.establishConnection(code).then(resolve);
        }, 100);
      });
    }

    return this.establishConnection(code);
  }

  private establishConnection(code?: string): Promise<void> {
    this.isConnecting = true;
    this.manualDisconnect = false;

    if (!code) {
      const urlSegments = window.location.pathname.split('/');
      code = urlSegments.length > 2 ? urlSegments[2] : undefined;
    }

    this.sessionCode = code;

    const wsUri = `${this.webSocketProto}://${this.host}/ws${code ? `/${code}` : ''}`;

    const connectSpan: TelemetrySpan = this.telemetry.startSpan('ws.connect', {
      'ws.has_session_code': code != null,
      attempt: this.reconnectAttempts,
    });

    return new Promise<void>((resolve, reject) => {
      this.logger.info('connect', `Connecting to WebSocket (private: ${code != null})`);
      const socket = new WebSocket(wsUri);
      this.socket = socket;

      // Settle once — onclose may fire without onopen/onerror, e.g. when a
      // concurrent disconnect replaces this.socket and the stale-event guards
      // below skip the natural reject path.
      let settled = false;
      const settleResolve = () => {
        if (settled) return;
        settled = true;
        this.telemetry.endSpan(connectSpan, { ok: true });
        resolve();
      };
      const settleReject = (err: unknown) => {
        if (settled) return;
        settled = true;
        const msg = err instanceof Error ? err.message : String(err);
        this.telemetry.endSpan(connectSpan, { ok: false, message: msg });
        reject(err);
      };

      socket.onopen = () => {
        if (socket !== this.socket) return;
        this.logger.info('connect', 'WebSocket connected');
        this.connected$.next();
        if (this.reconnectAttempts > 0) {
          this.telemetry.event('ws.reconnected', { attempts: this.reconnectAttempts });
          this.reconnected$.next();
        }
        this.reconnectAttempts = 0;
        this.reconnectDelay = 1000;
        this.reconnectState$.next(null);
        this.isConnecting = false;
        this.startKeepAlive();
        settleResolve();
      };

      socket.onmessage = (ev) => {
        if (socket !== this.socket) return;
        if (typeof ev.data === 'string') {
          const message = ev.data.trim();

          if (message.startsWith('[SignalMessage]')) {
            try {
              const signalMessage = JSON.parse(message.replace('[SignalMessage]', '').trim());
              this.signalMessages$.next(signalMessage);
            } catch (e) {
              this.logger.error(
                'connect',
                `Failed to parse signal message: ${e instanceof Error ? e.message : String(e)}`,
                e
              );
              return;
            }
          } else if (this.isSystemMessage(message)) {
            this.systemMessages$.next(message);
          } else {
            this.messages$.next(message);
          }
        } else {
          this.logger.warn('connect', 'Received non-string message from WebSocket');
        }
      };

      socket.onclose = (event) => {
        // Must run before the stale-event guard — the promise belongs to
        // this socket, even if it's already been replaced.
        settleReject(new Error(`WebSocket closed before opening (code ${event.code})`));

        // Ignore stale close events from a socket that has already been replaced.
        // Without this guard, a late-firing onclose from a previous socket would
        // null-out the current `this.socket` and trigger a phantom reconnect,
        // causing the server to register the client as multiple distinct users.
        if (socket !== this.socket) {
          this.logger.debug('onclose', `Ignoring stale close event (code ${event.code})`);
          return;
        }

        this.isConnecting = false;
        this.stopKeepAlive();
        this.socket = undefined;

        // Keep retrying any non-manual close (server down / network blip) so we
        // recover whenever the server comes back. No dead-end to
        // /404: the reconnect banner conveys status while we retry.
        this.logger.warn('connect', `WebSocket closed with code ${event.code}`);
        if (!this.manualDisconnect) {
          this.scheduleReconnect();
        }
      };

      socket.onerror = () => {
        if (socket !== this.socket) return;
        this.logger.warn('connect', 'WebSocket connection error (will attempt reconnect)');
        this.isConnecting = false;
        this.stopKeepAlive();
        this.socket = undefined;
        settleReject(new Error('WebSocket connection error'));
        // onerror fires before onclose on a failed connect and nulls the socket,
        // so the onclose stale-guard skips its reconnect — schedule it here.
        if (!this.manualDisconnect) {
          this.scheduleReconnect();
        }
      };
    });
  }

  private scheduleReconnect(): void {
    if (this.updateRequired()) {
      this.reconnectState$.next(null);
      return;
    }

    this.stopKeepAlive();

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
    }

    this.reconnectAttempts++;

    if (
      this.reconnectAttempts > this.maxReconnectAttempts &&
      this.sessionCode &&
      navigator.onLine
    ) {
      this.logger.warn(
        'scheduleReconnect',
        'Private session unreachable after max attempts, falling back to the public session'
      );
      this.telemetry.warnEvent('session.fallback_public', { attempts: this.reconnectAttempts });
      this.clearSessionCode();
      this.sessionFallback$.next();
    }

    const currentDelay =
      this.reconnectAttempts <= this.maxReconnectAttempts
        ? Math.min(
            this.reconnectDelay * Math.pow(2, this.reconnectAttempts - 1),
            this.maxReconnectDelay
          )
        : this.maxReconnectDelay;

    this.logger.info(
      'scheduleReconnect',
      `Scheduling reconnect attempt ${this.reconnectAttempts} in ${currentDelay}ms`
    );

    // Don't flag the server as troubled on the first retry — a suspended tab
    // resuming (e.g. after picking a file) reconnects on attempt 1 without ever
    // showing the banner. Only a persistent failure surfaces it.
    if (this.reconnectAttempts > 1) {
      this.reconnectState$.next({
        attempt: this.reconnectAttempts,
        nextAttemptAt: Date.now() + currentDelay,
      });
    }

    this.reconnectTimer = setTimeout(() => {
      if (this.isConnected()) {
        this.logger.info('scheduleReconnect', 'Already connected, skipping reconnect');
        return;
      }
      this.connect(this.sessionCode).catch((error: unknown) => {
        this.logger.error('scheduleReconnect', `Reconnect failed: ${error}`);
      });
    }, currentDelay);
  }

  private clearSessionCode(): void {
    if (isPlatformBrowser(this.platformId)) {
      localStorage.removeItem(SESSION_CODE_KEY);
    }
    this.sessionCode = undefined;
  }

  public disconnect(isManual = true): void {
    this.stopKeepAlive();
    if (isManual) {
      this.manualDisconnect = true;
      this.clearSessionCode();

      this.reconnectAttempts = 0;
      this.reconnectDelay = 1000;
    }

    if (this.reconnectTimer) {
      clearTimeout(this.reconnectTimer);
      this.reconnectTimer = null;
    }
    this.reconnectState$.next(null);

    const socket = this.socket;
    this.socket = undefined;
    this.isConnecting = false;

    if (
      socket &&
      (socket.readyState === WebSocket.OPEN || socket.readyState === WebSocket.CONNECTING)
    ) {
      this.logger.info('disconnect', 'Closing WebSocket connection.');
      socket.close();
    } else {
      this.logger.warn('disconnect', 'WebSocket is already closed or not initialized.');
    }
  }

  /**
   * ==========================================================
   * MESSAGE SENDING
   * Methods for sending different types of messages
   * ==========================================================
   */
  public send(message: string): void {
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      this.socket.send(message);
    } else {
      this.logger.error('send', 'WebSocket is not open. Message not sent.');
    }
  }

  public sendSignalMessage(message: unknown): void {
    if (this.socket && this.socket.readyState === WebSocket.OPEN) {
      const signalMessage = `[SignalMessage] ${JSON.stringify(message)}`;
      this.socket.send(signalMessage);
    } else {
      this.logger.error('sendSignalMessage', 'WebSocket is not open. Message not sent.');
    }
  }

  /**
   * ==========================================================
   * UTILITY METHODS
   * Helper methods for WebSocket operations
   * ==========================================================
   */
  private isSystemMessage(message: string): boolean {
    return (
      message.includes('[SystemMessage]') ||
      message.includes('[SystemJoin]') ||
      message.includes('[SystemRooms]') ||
      message.includes('[SystemMembers]') ||
      message.includes('[SystemName]')
    );
  }

  /**
   * Check if the WebSocket connection is currently active
   */
  public isConnected(): boolean {
    return this.socket !== undefined && this.socket.readyState === WebSocket.OPEN;
  }

  private startKeepAlive(): void {
    this.stopKeepAlive();
    this.keepAliveTimer = setInterval(() => {
      if (this.socket?.readyState === WebSocket.OPEN) {
        this.socket.send(WS_PREFIX_KEEP_ALIVE);
      }
    }, WS_KEEP_ALIVE_INTERVAL_MS);
  }

  private stopKeepAlive(): void {
    if (this.keepAliveTimer !== null) {
      clearInterval(this.keepAliveTimer);
      this.keepAliveTimer = null;
    }
  }

  /**
   * Clean up resources when service is destroyed
   */
  ngOnDestroy(): void {
    if (isPlatformBrowser(this.platformId)) {
      this.stopKeepAlive();

      // Remove event listeners
      window.removeEventListener('pagehide', this.pageHideListener ?? (() => {}));
      window.removeEventListener('pageshow', this.pageShowListener ?? (() => {}));

      // Close WebSocket connection
      if (this.isConnected()) {
        this.disconnect(true);
      }
    }
  }
}
