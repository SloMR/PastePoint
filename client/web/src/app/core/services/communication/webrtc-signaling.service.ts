import { Injectable, inject } from '@angular/core';
import * as Sentry from '@sentry/angular';
import { startNewTrace } from '@sentry/core';
import { WebSocketConnectionService } from './websocket-connection.service';
import { UserService } from '../user-management/user.service';
import { BlockService } from './block.service';
import {
  MAX_RECONNECT_ATTEMPTS,
  RECONNECT_DELAY,
  OFFER_OPTIONS,
  DATA_CHANNEL_OPTIONS,
  RTC_SIGNALING_STATES,
  SignalMessageType,
  SignalMessage,
  RTC_CONFIGURATION,
  ICE_GATHERING_TIMEOUT,
  CONNECTION_REQUEST_TIMEOUT,
  CONNECTION_ESTABLISH_TIMEOUT,
} from '../../../utils/constants';
import { TranslateService } from '@ngx-translate/core';
import { NGXLogger } from 'ngx-logger';
import { WebRTCCommunicationService } from './webrtc-communication.service';
import { TurnCredentialsService } from './turn-credentials.service';
import { HotToastService } from '@ngxpert/hot-toast';
import { Subject } from 'rxjs';

@Injectable({
  providedIn: 'root',
})
export class WebRTCSignalingService {
  private wsService = inject(WebSocketConnectionService);
  private userService = inject(UserService);
  private blockService = inject(BlockService);
  private toaster = inject(HotToastService);
  private translate = inject<TranslateService>(TranslateService);
  private logger = inject(NGXLogger);
  private communicationService = inject(WebRTCCommunicationService);
  private turnCredentials = inject(TurnCredentialsService);

  // =============== Properties ===============
  public peerDisconnected$ = new Subject<string>();
  public peerConnected$ = new Subject<string>();

  private peerConnections = new Map<string, RTCPeerConnection>();
  private reconnectAttempts = new Map<string, number>();
  private connectionLocks = new Set<string>();
  private outboundSequences = new Map<string, number>();
  private inboundSequences = new Map<string, number>();
  private pendingSignals: SignalMessage[] = [];
  private candidateQueues = new Map<string, RTCIceCandidateInit[]>();
  private connectionRequests = new Map<string, ReturnType<typeof setTimeout>>();
  private connectionRequestDelays = new Map<string, ReturnType<typeof setTimeout>>();
  private reconnectionTimeouts = new Map<string, ReturnType<typeof setTimeout>>();
  private stateMismatchTimeouts = new Map<string, ReturnType<typeof setTimeout>>();
  private establishmentTimeouts = new Map<string, ReturnType<typeof setTimeout>>();
  private collectedCandidates = new Map<string, RTCIceCandidate[]>();

  private activeConnectSpans = new Map<string, Sentry.Span>();
  private connectAttemptCounts = new Map<string, number>();

  private unsupportedNotified = false;

  constructor() {
    this.initializeSignalMessageHandler();

    // Refresh TURN credentials on every connect so peers created afterwards
    this.wsService.connected$.subscribe(() => void this.turnCredentials.refresh());

    this.userService.user$.subscribe((user) => {
      if (user && this.pendingSignals.length > 0) {
        const drained = this.pendingSignals;
        this.pendingSignals = [];
        drained.forEach((m) => this.handleSignalMessage(m));
      }
    });

    this.communicationService.dataChannelClosed$.subscribe((targetUser) => {
      if (
        this.wsService.isConnected() &&
        this.peerConnections.has(targetUser) &&
        !this.connectionLocks.has(targetUser) &&
        !this.reconnectionTimeouts.has(targetUser)
      ) {
        this.logger.info(
          'handleDataChannelClose',
          `Data channel closed with ${targetUser}, attempting reconnection`
        );
        this.closePeerConnection(targetUser, true);
        this.handleDisconnection(targetUser);
      }
    });
  }

  // =============== Public Methods ===============

  /**
   * Initiates a new WebRTC connection with the target user
   * @param targetUser The user to connect with
   */
  public initiateConnection(targetUser: string): void {
    let span = this.activeConnectSpans.get(targetUser);
    if (!span) {
      startNewTrace(() => {
        span = Sentry.startInactiveSpan({ name: 'webrtc.connect', op: 'webrtc.connect' });
        this.activeConnectSpans.set(targetUser, span);
      });
      this.connectAttemptCounts.set(targetUser, 1);
    } else {
      const next = (this.connectAttemptCounts.get(targetUser) ?? 1) + 1;
      this.connectAttemptCounts.set(targetUser, next);
      span.setAttribute('attempts', next);
    }
    this.initiateConnectionInner(targetUser, span!);
  }

  /**
   * Marks the active webrtc.connect span as successful and ends it.
   * Called when the peer connection AND data channel are both open.
   */
  private finishConnectSpanAsSuccess(targetUser: string): void {
    const span = this.activeConnectSpans.get(targetUser);
    if (!span) return;
    span.setAttribute('outcome', 'connected');
    span.setStatus({ code: 1, message: 'ok' });
    span.end();
    this.activeConnectSpans.delete(targetUser);
    this.connectAttemptCounts.delete(targetUser);
  }

  /**
   * Marks the active webrtc.connect span as failed and attaches diagnostic
   * candidate counts so a single trace explains *why* the peer-to-peer
   * connection failed (e.g. no relay candidates → restrictive NAT).
   */
  private finishConnectSpanAsFailed(targetUser: string, reason: string): void {
    const span = this.activeConnectSpans.get(targetUser);
    if (!span) return;
    const peerConnection = this.peerConnections.get(targetUser);
    const candidates = this.collectedCandidates.get(targetUser) || [];
    const candidateTypeCounts = candidates.reduce<Record<string, number>>((acc, c) => {
      const t = c.type || 'unknown';
      acc[t] = (acc[t] || 0) + 1;
      return acc;
    }, {});

    span.setAttribute('outcome', 'failed');
    span.setAttribute('failure_reason', reason);
    span.setAttribute('webrtc.peer_state', peerConnection?.connectionState ?? 'unknown');
    span.setAttribute('webrtc.ice_state', peerConnection?.iceConnectionState ?? 'unknown');
    span.setAttribute(
      'webrtc.has_relay',
      candidates.some((c) => c.type === 'relay')
    );
    span.setAttribute(
      'webrtc.has_srflx',
      candidates.some((c) => c.type === 'srflx')
    );
    span.setAttribute('webrtc.candidate_total', candidates.length);
    for (const [type, count] of Object.entries(candidateTypeCounts)) {
      span.setAttribute(`webrtc.candidate.${type}`, count);
    }
    span.setStatus({ code: 2, message: reason });
    span.end();
    this.activeConnectSpans.delete(targetUser);
    this.connectAttemptCounts.delete(targetUser);
  }

  private initiateConnectionInner(targetUser: string, span: Sentry.Span): void {
    if (targetUser === this.userService.user) {
      this.logger.warn(
        'initiateConnection',
        `Preventing self-connection attempt to: "${targetUser}"`
      );
      span.setAttribute('outcome', 'self_connection_skipped');
      span.end();
      this.activeConnectSpans.delete(targetUser);
      this.connectAttemptCounts.delete(targetUser);
      return;
    }

    if (this.connectionLocks.has(targetUser)) {
      this.logger.debug('initiateConnection', `Connection already in progress for ${targetUser}`);
      if ((this.connectAttemptCounts.get(targetUser) ?? 0) === 1) {
        span.setAttribute('outcome', 'skipped_lock');
        span.setStatus({ code: 1, message: 'already_in_progress' });
        span.end();
        this.activeConnectSpans.delete(targetUser);
        this.connectAttemptCounts.delete(targetUser);
      }
      return;
    }

    const existingPeerConnection = this.peerConnections.get(targetUser);
    if (existingPeerConnection) {
      const connectionState = existingPeerConnection.connectionState;
      const iceState = existingPeerConnection.iceConnectionState;

      if (connectionState === 'connected' || connectionState === 'connecting') {
        this.logger.debug(
          'initiateConnection',
          `PeerConnection with ${targetUser} is ${connectionState}`
        );
        span.setAttribute('outcome', `skipped_${connectionState}`);
        span.setStatus({ code: 1, message: connectionState });
        span.end();
        this.activeConnectSpans.delete(targetUser);
        this.connectAttemptCounts.delete(targetUser);
        return;
      }

      if (
        connectionState === 'failed' ||
        connectionState === 'disconnected' ||
        iceState === 'failed' ||
        iceState === 'disconnected'
      ) {
        this.logger.debug('initiateConnection', `Cleaning up failed connection with ${targetUser}`);
        this.closePeerConnection(targetUser, true);
      } else {
        this.logger.warn(
          'initiateConnection',
          `PeerConnection with ${targetUser} exists in state ${connectionState}/${iceState}`
        );
        span.setAttribute('outcome', `skipped_${connectionState}_${iceState}`);
        span.setStatus({ code: 1, message: 'unexpected_state' });
        span.end();
        this.activeConnectSpans.delete(targetUser);
        this.connectAttemptCounts.delete(targetUser);
        return;
      }
    }

    if (!this.shouldInitiateConnection(targetUser)) {
      this.logger.debug(
        'initiateConnection',
        `Requesting ${targetUser} to initiate connection (role: callee)`
      );
      this.sendConnectionRequest(targetUser);
      return;
    }

    // Clear any existing connection request timeout since we're initiating
    const requestTimeout = this.connectionRequests.get(targetUser);
    if (requestTimeout) {
      clearTimeout(requestTimeout);
      this.connectionRequests.delete(targetUser);
      this.logger.debug(
        'initiateConnection',
        `Cleared connection request timeout for ${targetUser}`
      );
    }

    this.connectionLocks.add(targetUser);

    this.logger.info(
      'initiateConnection',
      `Initiating connection with ${targetUser} (role: caller)`
    );

    try {
      const peerConnection = this.createPeerConnection(targetUser);
      if (!peerConnection) {
        this.logger.error(
          'initiateConnection',
          `Failed to create peer connection for ${targetUser}`
        );
        throw new Error(`Failed to create peer connection for ${targetUser}`);
      }

      const dataChannel = peerConnection.createDataChannel('data', DATA_CHANNEL_OPTIONS);
      this.communicationService.setupDataChannel(dataChannel, targetUser);

      const handleDataChannelOpen = () => {
        this.clearEstablishmentWatchdog(targetUser);
        this.connectionLocks.delete(targetUser);
        this.communicationService.sendQueuedMessages(targetUser);
        if (peerConnection.connectionState === 'connected') {
          this.reconnectAttempts.delete(targetUser);
          this.finishConnectSpanAsSuccess(targetUser);
          this.peerConnected$.next(targetUser);
        }
      };

      if (dataChannel.readyState === 'open') {
        handleDataChannelOpen();
      } else {
        dataChannel.onopen = handleDataChannelOpen;
      }

      dataChannel.onerror = () => {
        this.connectionLocks.delete(targetUser);
        if (this.peerConnections.get(targetUser) === peerConnection) {
          this.closePeerConnection(targetUser, true);
          this.handleDisconnection(targetUser);
        }
      };
      dataChannel.onclose = () => {
        this.connectionLocks.delete(targetUser);
        if (
          this.wsService.isConnected() &&
          this.peerConnections.get(targetUser) === peerConnection
        ) {
          this.closePeerConnection(targetUser, true);
          this.handleDisconnection(targetUser);
        }
      };

      peerConnection
        .createOffer(OFFER_OPTIONS)
        .then((offer) => peerConnection.setLocalDescription(offer))
        .then(() => {
          this.sendSignalMessage({
            type: SignalMessageType.OFFER,
            data: peerConnection.localDescription,
            to: targetUser,
            sequence: this.getNextSequence(targetUser),
          });
        })
        .catch((error: unknown) => {
          this.logger.error('initiateConnection', `Offer creation failed: ${error}`);
          this.toaster.error(this.translate.instant('CONNECTION_LOST'));
          this.connectionLocks.delete(targetUser);
          this.reconnect(targetUser);
        });
    } catch (error: unknown) {
      this.logger.error('initiateConnection', `Connection initiation failed: ${error}`);
      this.toaster.error(this.translate.instant('CONNECTION_LOST'));
      this.connectionLocks.delete(targetUser);
      this.finishConnectSpanAsFailed(targetUser, 'initiation_failed');
    }
  }

  /**
   * Handles data channel close event
   * @param targetUser The user whose data channel was closed
   */
  public handleDataChannelClose(targetUser: string): void {
    this.closePeerConnection(targetUser, true);
  }

  /**
   * Handles data channel error event
   * @param targetUser The user whose data channel encountered an error
   */
  public handleDataChannelError(targetUser: string): void {
    this.closePeerConnection(targetUser, true);
  }

  /**
   * Handles data channel not open event
   * @param targetUser The user whose data channel is not open
   */
  public handleDataChannelNotOpen(targetUser: string): void {
    this.closePeerConnection(targetUser, true);
  }

  /**
   * Handles data channel reconnection event
   * @param targetUser The user to reconnect with
   */
  public handleDataChannelReconnect(targetUser: string): void {
    if (!this.peerConnections.has(targetUser)) {
      this.initiateConnection(targetUser);
    }
  }

  /**
   * Stronger than closePeerConnection — also cancels pending retries and
   * queued requests. Use when the peer is gone for good (left the room).
   */
  public closeConnection(targetUser: string): void {
    const span = this.activeConnectSpans.get(targetUser);
    if (span) {
      span.setAttribute('outcome', 'cancelled');
      span.setStatus({ code: 2, message: 'cancelled' });
      span.end();
      this.activeConnectSpans.delete(targetUser);
      this.connectAttemptCounts.delete(targetUser);
    }

    this.closePeerConnection(targetUser, true);

    this.connectionLocks.delete(targetUser);
    this.reconnectAttempts.delete(targetUser);
    this.inboundSequences.delete(targetUser);
    this.outboundSequences.delete(targetUser);

    const reconnectionTimeout = this.reconnectionTimeouts.get(targetUser);
    if (reconnectionTimeout) {
      clearTimeout(reconnectionTimeout);
      this.reconnectionTimeouts.delete(targetUser);
    }

    this.communicationService.deleteMessageQueue(targetUser);
  }

  /**
   * Closes a peer connection with the target user
   * @param targetUser The user to disconnect from
   * @param force Whether to force close the connection
   */
  public closePeerConnection(targetUser: string, force = false) {
    const peerConnection = this.peerConnections.get(targetUser);
    if (peerConnection) {
      this.peerConnections.delete(targetUser);
      peerConnection.close();
    }

    // Clear connection request timeout
    const requestTimeout = this.connectionRequests.get(targetUser);
    if (requestTimeout) {
      clearTimeout(requestTimeout);
      this.connectionRequests.delete(targetUser);
    }

    // Clear connection request delay timeout
    const requestDelayTimeout = this.connectionRequestDelays.get(targetUser);
    if (requestDelayTimeout) {
      clearTimeout(requestDelayTimeout);
      this.connectionRequestDelays.delete(targetUser);
    }

    // Clear state mismatch timeout
    const stateMismatchTimeout = this.stateMismatchTimeouts.get(targetUser);
    if (stateMismatchTimeout) {
      clearTimeout(stateMismatchTimeout);
      this.stateMismatchTimeouts.delete(targetUser);
    }

    this.clearEstablishmentWatchdog(targetUser);

    if (force) {
      this.candidateQueues.delete(targetUser);
      this.collectedCandidates.delete(targetUser);
      this.communicationService.deleteDataChannel(targetUser);
    }
  }

  /**
   * Closes all peer connections
   */
  public closeAllConnections(): void {
    this.activeConnectSpans.forEach((span) => {
      span.setAttribute('outcome', 'cancelled');
      span.setStatus({ code: 2, message: 'closeAll' });
      span.end();
    });
    this.activeConnectSpans.clear();
    this.connectAttemptCounts.clear();

    this.peerConnections.forEach((peerConnection) => {
      peerConnection.close();
    });
    this.peerConnections.clear();
    this.connectionLocks.clear();
    this.reconnectAttempts.clear();
    this.inboundSequences.clear();
    this.outboundSequences.clear();
    this.pendingSignals = [];
    this.candidateQueues.clear();
    this.collectedCandidates.clear();

    // Clear all connection request timeouts
    this.connectionRequests.forEach((timeout) => {
      clearTimeout(timeout);
    });
    this.connectionRequests.clear();

    // Clear all connection request delay timeouts
    this.connectionRequestDelays.forEach((timeout) => {
      clearTimeout(timeout);
    });
    this.connectionRequestDelays.clear();

    // Clear all reconnection timeouts
    this.reconnectionTimeouts.forEach((timeout) => {
      clearTimeout(timeout);
    });
    this.reconnectionTimeouts.clear();

    // Clear all state mismatch timeouts
    this.stateMismatchTimeouts.forEach((timeout) => {
      clearTimeout(timeout);
    });
    this.stateMismatchTimeouts.clear();

    // Clear all establishment watchdog timeouts
    this.establishmentTimeouts.forEach((timeout) => {
      clearTimeout(timeout);
    });
    this.establishmentTimeouts.clear();
  }

  /**
   * Gets the peer connection for a target user
   * @param targetUser The user to get the connection for
   */
  public getPeerConnection(targetUser: string): RTCPeerConnection | undefined {
    return this.peerConnections.get(targetUser);
  }

  /**
   * Deletes a peer connection for a target user
   * @param targetUser The user to delete the connection for
   */
  public deletePeerConnection(targetUser: string): void {
    this.peerConnections.delete(targetUser);
  }

  // =============== Private Methods ===============

  /**
   * Initializes the signal message handler
   */
  private initializeSignalMessageHandler(): void {
    this.wsService.signalMessages$.subscribe((message: unknown) => {
      if (message) {
        this.logger.debug(
          'WebRTCConnectionService',
          `Received signal message: ${JSON.stringify(message)}`
        );
        this.handleSignalMessage(message as SignalMessage);
      }
    });
  }

  /**
   * Creates a new peer connection for the target user
   * @param targetUser The user to create the connection for
   */
  private createPeerConnection(targetUser: string): RTCPeerConnection | undefined {
    if (this.userService.user === targetUser) {
      this.logger.warn('createPeerConnection', `Skipping connection creation with self`);
      return;
    }

    if (typeof RTCPeerConnection === 'undefined') {
      this.logger.error(
        'createPeerConnection',
        'RTCPeerConnection is unavailable in this environment'
      );
      if (!this.unsupportedNotified) {
        this.unsupportedNotified = true;
        this.toaster.error(this.translate.instant('WEBRTC_NOT_SUPPORTED'));
      }
      return;
    }

    // Check and close existing connection first to prevent memory leaks
    const existingConnection = this.peerConnections.get(targetUser);
    if (existingConnection) {
      this.logger.warn(
        'createPeerConnection',
        `Peer connection already exists for ${targetUser}, closing old one`
      );
      existingConnection.close();
      this.peerConnections.delete(targetUser);
    }

    const peerConnection = new RTCPeerConnection({
      ...RTC_CONFIGURATION,
      iceServers: this.turnCredentials.iceServers,
    });

    let iceGatheringTimeout: ReturnType<typeof setTimeout> | null = null;
    let iceGatheringComplete = false;

    peerConnection.onicecandidate = (event) => {
      if (event.candidate) {
        if (iceGatheringTimeout) {
          clearTimeout(iceGatheringTimeout);
          iceGatheringTimeout = null;
        }

        // Store candidate for diagnostics
        if (!this.collectedCandidates.has(targetUser)) {
          this.collectedCandidates.set(targetUser, []);
        }
        this.collectedCandidates.get(targetUser)!.push(event.candidate);

        const message: SignalMessage = {
          type: SignalMessageType.CANDIDATE,
          data: event.candidate,
          from: this.userService.user,
          to: targetUser,
        };
        this.wsService.sendSignalMessage(message);
      } else {
        iceGatheringComplete = true;
        if (iceGatheringTimeout) {
          clearTimeout(iceGatheringTimeout);
          iceGatheringTimeout = null;
        }

        const candidates = this.collectedCandidates.get(targetUser) || [];
        const candidateTypes = candidates.reduce(
          (acc, c) => {
            acc[c.type || 'unknown'] = (acc[c.type || 'unknown'] || 0) + 1;
            return acc;
          },
          {} as Record<string, number>
        );

        this.logger.info(
          'ICE',
          `Gathering complete for ${targetUser}. Collected ${candidates.length} candidates: ${JSON.stringify(candidateTypes)}`
        );

        const hasRelay = candidates.some((c) => c.type === 'relay');
        Sentry.addBreadcrumb({
          category: 'webrtc.ice',
          level: 'info',
          message: 'ice gathering complete',
          data: { types: candidateTypes },
        });
        if (!hasRelay && candidates.length > 0) {
          this.logger.warn(
            'ICE',
            `No TURN/relay candidates for ${targetUser} - connection may be unstable or fail behind restrictive NATs`
          );
        }
      }
    };

    iceGatheringTimeout = setTimeout(() => {
      if (!iceGatheringComplete) {
        this.logger.warn('createPeerConnection', `ICE gathering timeout for ${targetUser}`);
      }
    }, ICE_GATHERING_TIMEOUT);

    peerConnection.ondatachannel = (event) => {
      const dataChannel = event.channel;
      this.communicationService.setupDataChannel(dataChannel, targetUser);
    };

    peerConnection.onconnectionstatechange = () => {
      // Ignore events from stale connections that have been replaced
      if (this.peerConnections.get(targetUser) !== peerConnection) return;

      const state = peerConnection.connectionState;
      Sentry.addBreadcrumb({
        category: 'webrtc.peer',
        level: state === 'failed' ? 'error' : 'info',
        message: `peer connection state: ${state}`,
      });

      if (state === 'connected') {
        // Clear ICE gathering timeout when connection is established
        if (iceGatheringTimeout) {
          clearTimeout(iceGatheringTimeout);
          iceGatheringTimeout = null;
        }
        // Only clear retry counter and emit connected when data channel is also open
        if (this.communicationService.isConnected(targetUser)) {
          this.clearEstablishmentWatchdog(targetUser);
          this.reconnectAttempts.delete(targetUser);
          this.logger.info('createPeerConnection', `Successfully connected to ${targetUser}`);
          this.finishConnectSpanAsSuccess(targetUser);
          this.peerConnected$.next(targetUser);
        } else {
          this.logger.info(
            'createPeerConnection',
            `Peer connection connected to ${targetUser}, waiting for data channel`
          );
        }
      } else if (state === 'failed' || state === 'disconnected') {
        // Clear timeout on failure
        if (iceGatheringTimeout) {
          clearTimeout(iceGatheringTimeout);
          iceGatheringTimeout = null;
        }
        this.handleDisconnection(targetUser);
      }
    };

    peerConnection.oniceconnectionstatechange = () => {
      // Ignore events from stale connections that have been replaced
      if (this.peerConnections.get(targetUser) !== peerConnection) return;

      const iceState = peerConnection.iceConnectionState;
      Sentry.addBreadcrumb({
        category: 'webrtc.ice',
        level: iceState === 'failed' ? 'error' : 'info',
        message: `ice connection state: ${iceState}`,
      });

      if (iceState === 'connected' || iceState === 'completed') {
        // Clear ICE gathering timeout when ICE connection is established
        if (iceGatheringTimeout) {
          clearTimeout(iceGatheringTimeout);
          iceGatheringTimeout = null;
        }
      } else if (iceState === 'disconnected' || iceState === 'failed') {
        // Clear timeout on failure
        if (iceGatheringTimeout) {
          clearTimeout(iceGatheringTimeout);
          iceGatheringTimeout = null;
        }
        this.handleDisconnection(targetUser);
      }
    };

    this.peerConnections.set(targetUser, peerConnection);
    this.candidateQueues.set(targetUser, []);
    this.startEstablishmentWatchdog(targetUser);

    return peerConnection;
  }

  /**
   * Handles disconnection events and attempts reconnection
   * @param targetUser The user to handle disconnection for
   */
  private handleDisconnection(targetUser: string) {
    // Skip if a reconnection is already scheduled for this user
    if (this.reconnectionTimeouts.has(targetUser)) {
      return;
    }

    const attempts = this.reconnectAttempts.get(targetUser) ?? 0;

    // Log diagnostic info on first failure
    if (attempts === 0) {
      this.logConnectionDiagnostics(targetUser);
    }

    if (attempts < MAX_RECONNECT_ATTEMPTS) {
      this.reconnectAttempts.set(targetUser, attempts + 1);

      // Use exponential backoff (starts at 2s, max 10s)
      const baseDelay = RECONNECT_DELAY;
      const maxDelay = 10000;
      const delay = Math.min(baseDelay * Math.pow(1.5, attempts), maxDelay);

      this.logger.warn(
        'handleDisconnection',
        `Attempt ${attempts + 1}: Reconnecting to ${targetUser} in ${delay / 1000} seconds...`
      );

      if (attempts === 0) {
        this.logger.info('handleDisconnection', `Starting reconnection attempts to ${targetUser}`);
      }

      // Clear any existing reconnection timeout for this user
      const existingTimeout = this.reconnectionTimeouts.get(targetUser);
      if (existingTimeout) {
        clearTimeout(existingTimeout);
      }

      const timeoutId = setTimeout(() => {
        this.reconnectionTimeouts.delete(targetUser);
        if (!this.communicationService.isConnected(targetUser)) {
          this.logger.debug(
            'handleDisconnection',
            `Attempting reconnection ${attempts + 1} to ${targetUser}`
          );
          this.reconnect(targetUser);
        } else {
          this.logger.debug(
            'handleDisconnection',
            `Connection healthy for ${targetUser}, skipping reconnect`
          );
          this.reconnectAttempts.delete(targetUser);
        }
      }, delay);

      this.reconnectionTimeouts.set(targetUser, timeoutId);
    } else {
      this.logger.error(
        'handleDisconnection',
        `Max reconnection attempts reached for ${targetUser}. Could not reconnect.`
      );

      // Final diagnostic log
      this.logConnectionDiagnostics(targetUser);
      this.finishConnectSpanAsFailed(targetUser, 'max_reconnects_exceeded');

      if (this.wsService.isConnected()) {
        this.toaster.error(
          this.translate.instant('CANNOT_CONNECT_TO_USER', { userName: targetUser })
        );
      }
      this.closePeerConnection(targetUser, true);
      this.peerDisconnected$.next(targetUser);
    }
  }

  /**
   * Retries the connection if it doesn't fully establish (data channel open)
   * within CONNECTION_ESTABLISH_TIMEOUT, catching connections that hang without
   * ever emitting a `failed` event.
   * @param targetUser The user whose connection to watch
   */
  private startEstablishmentWatchdog(targetUser: string): void {
    this.clearEstablishmentWatchdog(targetUser);

    const timeoutId = setTimeout(() => {
      this.establishmentTimeouts.delete(targetUser);

      // The data channel opened in the meantime; nothing to do.
      if (this.communicationService.isConnected(targetUser)) {
        return;
      }

      this.logger.warn(
        'startEstablishmentWatchdog',
        `Connection with ${targetUser} did not establish in time; retrying`
      );
      this.handleDisconnection(targetUser);
    }, CONNECTION_ESTABLISH_TIMEOUT);

    this.establishmentTimeouts.set(targetUser, timeoutId);
  }

  /**
   * Clears the establishment watchdog for a target user, if any.
   * @param targetUser The user whose watchdog to clear
   */
  private clearEstablishmentWatchdog(targetUser: string): void {
    const timeoutId = this.establishmentTimeouts.get(targetUser);
    if (timeoutId) {
      clearTimeout(timeoutId);
      this.establishmentTimeouts.delete(targetUser);
    }
  }

  /**
   * Logs diagnostic info for failed connections (minimal)
   */
  private logConnectionDiagnostics(targetUser: string): void {
    const peerConnection = this.peerConnections.get(targetUser);
    const candidates = this.collectedCandidates.get(targetUser) || [];

    if (!peerConnection) return;

    const hasRelay = candidates.some((c) => c.type === 'relay');
    const hasSrflx = candidates.some((c) => c.type === 'srflx');

    this.logger.error(
      'DIAGNOSTIC',
      `Connection FAILED with ${targetUser}:\n` +
        `  State: ${peerConnection.connectionState} / ICE: ${peerConnection.iceConnectionState}\n` +
        `  Candidates: ${candidates.length} total (relay: ${hasRelay ? '✓' : '✗'}, srflx: ${hasSrflx ? '✓' : '✗'})\n` +
        `  ${!hasRelay ? 'ISSUE: No TURN relay candidates - connection will fail behind symmetric NAT' : ''}`
    );
  }

  /**
   * Handles incoming signal messages
   * @param message The signal message to handle
   */
  private handleSignalMessage(message: SignalMessage): void {
    if (this.blockService.isBlocked(message.from)) {
      this.logger.info(
        'handleSignalMessage',
        `Ignoring ${message.type} from blocked peer ${message.from}`
      );
      return;
    }

    if (message.from === message.to) {
      this.logger.warn(
        'handleSignalMessage',
        'Skipping self-loop signal: ' + JSON.stringify(message)
      );
      return;
    }

    const myUser = this.userService.user;
    if (!myUser) {
      this.pendingSignals.push(message);
      return;
    }

    if (message.to !== myUser) {
      this.logger.warn(
        'handleSignalMessage',
        `Skipping signal addressed to ${message.to}, not me (${myUser})`
      );
      return;
    }

    switch (message.type) {
      case SignalMessageType.OFFER:
        this.handleOffer(message);
        break;
      case SignalMessageType.ANSWER:
        this.handleAnswer(message);
        break;
      case SignalMessageType.CANDIDATE:
        this.handleCandidate(message);
        break;
      case SignalMessageType.CONNECTION_REQUEST:
        this.handleConnectionRequest(message);
        break;
      default:
        this.logger.error('handleSignalMessage', `Unknown signal message type: ${message.type}`);
    }
  }

  /**
   * Handles incoming connection request messages
   * @param message The connection request message to handle
   */
  private handleConnectionRequest(message: SignalMessage): void {
    const targetUser = message.from;
    this.logger.info('handleConnectionRequest', `Received connection request from ${targetUser}`);
    if (this.isDuplicateMessage(targetUser, message.sequence)) {
      this.logger.warn(
        'handleConnectionRequest',
        `Duplicate connection request from ${targetUser}`
      );
      return;
    }

    if (this.shouldInitiateConnection(targetUser)) {
      this.logger.debug(
        'handleConnectionRequest',
        `Initiating connection as requested by ${targetUser}`
      );
      this.initiateConnection(targetUser);
    } else {
      this.logger.debug(
        'handleConnectionRequest',
        `Not caller for ${targetUser}; ignoring request`
      );
    }
  }

  /**
   * Handles incoming offer messages with collision detection
   * @param message The offer message to handle
   */
  private handleOffer(message: SignalMessage): void {
    const targetUser = message.from;

    if (this.userService.user === targetUser) {
      this.logger.warn('handleOffer', `Skipping offer from self`);
      return;
    }

    const requestTimeout = this.connectionRequests.get(targetUser);
    if (requestTimeout) {
      clearTimeout(requestTimeout);
      this.connectionRequests.delete(targetUser);
      this.logger.debug('handleOffer', `Cleared connection request timeout for ${targetUser}`);
    }

    // Check if we're already trying to initiate a connection (collision detection)
    if (this.connectionLocks.has(targetUser)) {
      this.logger.warn('handleOffer', `Collision detected with ${targetUser}, resolving by role`);

      // If we should be the caller, ignore this offer and let our offer proceed
      if (this.shouldInitiateConnection(targetUser)) {
        this.logger.debug(
          'handleOffer',
          `Ignoring offer from ${targetUser} (we are the designated caller)`
        );
        return;
      } else {
        // If we should be the callee, cancel our initiation and handle this offer
        this.logger.debug(
          'handleOffer',
          `Canceling our initiation for ${targetUser} (we are the designated callee)`
        );
        this.closePeerConnection(targetUser, false);
        this.connectionLocks.delete(targetUser);
      }
    }

    // Set lock while processing offer to prevent concurrent connection attempts
    this.connectionLocks.add(targetUser);

    const peerConnection = this.createPeerConnection(targetUser);

    if (!peerConnection) {
      this.logger.error('handleOffer', `PeerConnection missing for ${targetUser}`);
      this.connectionLocks.delete(targetUser);
      return;
    }

    peerConnection
      .setRemoteDescription(new RTCSessionDescription(message.data as RTCSessionDescriptionInit))
      .then(() => {
        return peerConnection.createAnswer();
      })
      .then((answer) => {
        return peerConnection.setLocalDescription(answer);
      })
      .then(() => {
        // Release lock after answer is sent
        this.connectionLocks.delete(targetUser);
        const response: SignalMessage = {
          type: SignalMessageType.ANSWER,
          data: peerConnection.localDescription,
          from: this.userService.user,
          to: targetUser,
        };
        this.wsService.sendSignalMessage(response);
        this.processCandidateQueue(targetUser);
      })
      .catch((error) => {
        // Release lock on error
        this.connectionLocks.delete(targetUser);
        this.logger.error('handleOffer', `Error handling offer: ${error}`);
        if (this.wsService.isConnected()) {
          this.toaster.warning(
            this.translate.instant('CONNECTION_FAILED_WITH_USER', { userName: targetUser })
          );
        }
      });
  }

  /**
   * Handles incoming answer messages
   * @param message The answer message to handle
   */
  private handleAnswer(message: SignalMessage): void {
    const targetUser = message.from;
    const peerConnection = this.peerConnections.get(targetUser);

    if (!peerConnection) {
      this.logger.error('handleAnswer', `PeerConnection missing for ${targetUser}`);
      this.reconnect(targetUser);
      return;
    }

    if (peerConnection.signalingState !== RTC_SIGNALING_STATES.HAVE_LOCAL_OFFER) {
      this.logger.warn(
        'handleAnswer',
        `Invalid state for answer: ${peerConnection.signalingState}`
      );
      this.handleStateMismatch(targetUser);
      return;
    } else {
      this.logger.debug('handleAnswer', `Valid state for answer: ${peerConnection.signalingState}`);
    }

    if (this.isDuplicateMessage(targetUser, message.sequence)) {
      this.logger.warn('handleAnswer', `Duplicate answer from ${targetUser}`);
      return;
    }

    const newDescription = new RTCSessionDescription(message.data as RTCSessionDescriptionInit);
    peerConnection
      .setRemoteDescription(newDescription)
      .then(() => {
        this.logger.debug('handleAnswer', `Remote answer set for ${targetUser}`);
        this.processCandidateQueue(targetUser);

        if (peerConnection.signalingState !== RTC_SIGNALING_STATES.STABLE) {
          throw new Error(`Unexpected post-answer state: ${peerConnection.signalingState}`);
        } else {
          this.logger.debug('handleAnswer', `Connection established with ${targetUser}`);
        }
      })
      .catch((error) => {
        this.logger.error('handleAnswer', `Error handling answer: ${error}`);
        if (this.wsService.isConnected()) {
          this.toaster.warning(
            this.translate.instant('CONNECTION_FAILED_WITH_USER', { userName: targetUser })
          );
        }
        this.handleStateMismatch(targetUser);
      });
  }

  /**
   * Handles state mismatch events
   * @param targetUser The user to handle state mismatch for
   */
  private handleStateMismatch(targetUser: string): void {
    this.logger.warn(
      'handleStateMismatch',
      `Resetting connection due to state mismatch with ${targetUser}`
    );
    this.closePeerConnection(targetUser, true);

    // Clear any existing state mismatch timeout for this user
    const existingTimeout = this.stateMismatchTimeouts.get(targetUser);
    if (existingTimeout) {
      clearTimeout(existingTimeout);
    }

    // Clear reconnection timeout to prevent collision with state mismatch recovery
    const reconnectionTimeout = this.reconnectionTimeouts.get(targetUser);
    if (reconnectionTimeout) {
      clearTimeout(reconnectionTimeout);
      this.reconnectionTimeouts.delete(targetUser);
      this.logger.debug(
        'handleStateMismatch',
        `Cleared reconnection timeout for ${targetUser} to prevent collision`
      );
    }

    const timeoutId = setTimeout(() => {
      this.stateMismatchTimeouts.delete(targetUser);
      this.initiateConnection(targetUser);
    }, 500);

    this.stateMismatchTimeouts.set(targetUser, timeoutId);
  }

  /**
   * Handles incoming ICE candidate messages
   * @param message The candidate message to handle
   */
  private handleCandidate(message: SignalMessage): void {
    const targetUser = message.from;
    const peerConnection = this.peerConnections.get(targetUser);

    if (!peerConnection) {
      this.logger.warn(
        'handleCandidate',
        `No peer connection for ${targetUser}, ignoring candidate`
      );
      return;
    }

    const candidate = new RTCIceCandidate(message.data as RTCIceCandidateInit);

    if (peerConnection.remoteDescription) {
      peerConnection
        .addIceCandidate(candidate)
        .then(() => {
          this.logger.debug(
            'handleCandidate',
            `Successfully added ICE candidate from ${targetUser}`
          );
        })
        .catch((error) => {
          this.logger.error('handleCandidate', `Error adding ICE candidate: ${error}`);
          const attempts = this.reconnectAttempts.get(targetUser) ?? 0;
          if (attempts > 2) {
            this.logger.warn(
              'handleCandidate',
              `ICE candidate errors for ${targetUser}, attempts: ${attempts}`
            );
          }
        });
    } else {
      this.logger.debug(
        'handleCandidate',
        `Queueing ICE candidate from ${targetUser} (no remote description yet)`
      );
      let queue = this.candidateQueues.get(targetUser);
      if (queue) {
        queue.push(message.data as RTCIceCandidateInit);
      } else {
        this.candidateQueues.set(targetUser, [message.data as RTCIceCandidateInit]);
      }
    }
  }

  /**
   * Processes queued ICE candidates
   * @param targetUser The user whose candidate queue to process
   */
  private processCandidateQueue(targetUser: string): void {
    const queue = this.candidateQueues.get(targetUser);
    const peerConnection = this.peerConnections.get(targetUser);

    if (queue && peerConnection) {
      queue.forEach((candidateInit: RTCIceCandidateInit) => {
        const candidate = new RTCIceCandidate(candidateInit);
        peerConnection
          .addIceCandidate(candidate)
          .then(() => {
            this.logger.info(
              'processCandidateQueue',
              `Successfully added queued candidate from ${targetUser}`
            );
          })
          .catch((error) => {
            this.logger.error(
              'processCandidateQueue',
              `Error adding queued ICE candidate: ${error}`
            );
          });
      });
      queue.length = 0;
    } else {
      this.logger.debug(
        'processCandidateQueue',
        `No candidate queue or peer connection for ${targetUser}`
      );
    }
  }

  /**
   * Attempts to reconnect to a target user
   * @param targetUser The user to reconnect to
   */
  private reconnect(targetUser: string) {
    this.logger.info('reconnect', `Reconnecting WebRTC with ${targetUser}...`);

    this.closePeerConnection(targetUser, true);
    this.initiateConnection(targetUser);
  }

  /**
   * Sends a signal message to the target user
   * @param message The message to send
   */
  private sendSignalMessage(message: Omit<SignalMessage, 'from'>): void {
    this.wsService.sendSignalMessage({
      ...message,
      from: this.userService.user,
      sequence: this.getNextSequence(message.to),
    });
  }

  /**
   * Sends a connection request to the target user
   * @param targetUser The user to send the request to
   */
  private sendConnectionRequest(targetUser: string): void {
    const existingTimeout = this.connectionRequests.get(targetUser);
    if (existingTimeout) {
      this.logger.debug(
        'sendConnectionRequest',
        `Connection request already pending for ${targetUser}`
      );
      return;
    }

    // Clear any existing delay timeout for this user
    const existingDelayTimeout = this.connectionRequestDelays.get(targetUser);
    if (existingDelayTimeout) {
      clearTimeout(existingDelayTimeout);
      this.connectionRequestDelays.delete(targetUser);
    }

    // Add a small delay before sending the request to prevent race conditions
    // This gives the other peer time to send their offer if they're the designated caller
    const delayTimeout = setTimeout(() => {
      // Remove from tracking once executed
      this.connectionRequestDelays.delete(targetUser);

      // Check again if we already have a connection in progress
      if (this.peerConnections.has(targetUser) || this.connectionLocks.has(targetUser)) {
        this.logger.debug(
          'sendConnectionRequest',
          `Connection already in progress with ${targetUser}, skipping request`
        );
        return;
      }

      const message: SignalMessage = {
        type: SignalMessageType.CONNECTION_REQUEST,
        data: null,
        from: this.userService.user,
        to: targetUser,
        sequence: this.getNextSequence(targetUser),
      };
      this.wsService.sendSignalMessage(message);
      this.logger.info('sendConnectionRequest', `Sent connection request to ${targetUser}`);

      const timeout = setTimeout(() => {
        this.logger.warn('sendConnectionRequest', `Connection request timeout for ${targetUser}`);
        this.connectionRequests.delete(targetUser);

        // Fallback: try to initiate connection ourselves if no response
        if (!this.peerConnections.has(targetUser)) {
          this.logger.debug(
            'sendConnectionRequest',
            `Fallback: initiating connection with ${targetUser} after timeout`
          );
          this.forceInitiateConnection(targetUser);
        }
      }, CONNECTION_REQUEST_TIMEOUT);

      this.connectionRequests.set(targetUser, timeout);
    }, 500); // 500ms delay to prevent race conditions

    this.connectionRequestDelays.set(targetUser, delayTimeout);
  }

  /**
   * Forces connection initiation (bypasses role checking)
   * @param targetUser The user to connect with
   */
  private forceInitiateConnection(targetUser: string): void {
    this.logger.info('forceInitiateConnection', `Forcing connection initiation with ${targetUser}`);

    if (this.userService.user === targetUser) {
      this.logger.warn('forceInitiateConnection', `Skipping connection initiation with self`);
      return;
    }

    const existingTimeout = this.connectionRequests.get(targetUser);
    if (existingTimeout) {
      clearTimeout(existingTimeout);
      this.connectionRequests.delete(targetUser);
    }

    // Temporarily bypass role checking and initiate connection
    this.connectionLocks.add(targetUser);

    try {
      const peerConnection = this.createPeerConnection(targetUser);
      if (!peerConnection) {
        this.logger.error('forceInitiateConnection', `PeerConnection missing for ${targetUser}`);
        throw new Error(`Failed to create peer connection for ${targetUser}`);
      }

      const dataChannel = peerConnection.createDataChannel('data', DATA_CHANNEL_OPTIONS);
      this.communicationService.setupDataChannel(dataChannel, targetUser);

      const handleDataChannelOpen = () => {
        this.clearEstablishmentWatchdog(targetUser);
        this.connectionLocks.delete(targetUser);
        this.communicationService.sendQueuedMessages(targetUser);
        if (peerConnection.connectionState === 'connected') {
          this.reconnectAttempts.delete(targetUser);
          this.finishConnectSpanAsSuccess(targetUser);
          this.peerConnected$.next(targetUser);
        }
      };

      if (dataChannel.readyState === 'open') {
        handleDataChannelOpen();
      } else {
        dataChannel.onopen = handleDataChannelOpen;
      }

      dataChannel.onerror = () => {
        this.connectionLocks.delete(targetUser);
        if (this.peerConnections.get(targetUser) === peerConnection) {
          this.closePeerConnection(targetUser, true);
          this.handleDisconnection(targetUser);
        }
      };
      dataChannel.onclose = () => {
        this.connectionLocks.delete(targetUser);
        if (
          this.wsService.isConnected() &&
          this.peerConnections.get(targetUser) === peerConnection
        ) {
          this.closePeerConnection(targetUser, true);
          this.handleDisconnection(targetUser);
        }
      };

      peerConnection
        .createOffer(OFFER_OPTIONS)
        .then((offer) => peerConnection.setLocalDescription(offer))
        .then(() => {
          this.sendSignalMessage({
            type: SignalMessageType.OFFER,
            data: peerConnection.localDescription,
            to: targetUser,
            sequence: this.getNextSequence(targetUser),
          });
        })
        .catch((error: unknown) => {
          this.logger.error('forceInitiateConnection', `Offer creation failed: ${error}`);
          this.connectionLocks.delete(targetUser);
        });
    } catch (error: unknown) {
      this.logger.error('forceInitiateConnection', `Connection initiation failed: ${error}`);
      this.connectionLocks.delete(targetUser);
    }
  }

  // =============== Helper Methods ===============

  /**
   * Checks if a message is a duplicate
   * @param targetUser The user the message is from
   * @param sequence The message sequence number
   */
  private isDuplicateMessage(targetUser: string, sequence?: number): boolean {
    if (!sequence) return false;
    const lastSeq = this.inboundSequences.get(targetUser) ?? 0;
    if (sequence <= lastSeq) return true;
    this.inboundSequences.set(targetUser, sequence);
    return false;
  }

  /**
   * Gets the next sequence number for a target user
   * @param targetUser The user to get the sequence for
   */
  private getNextSequence(targetUser: string): number {
    const next = (this.outboundSequences.get(targetUser) ?? 0) + 1;
    this.outboundSequences.set(targetUser, next);
    return next;
  }

  /**
   * Determines if the current user should initiate the connection.
   * Glare resolution: the lexicographically smaller username is the caller.
   *
   * Plain `<` is UTF-16 code-unit comparison — locale-independent, so the web
   * and other clients agree on roles regardless of either device's system locale.
   * Do not switch to localeCompare here without coordinating the other client side.
   *
   * @param targetUser The user to compare with.
   * @returns true if the current user should initiate, false if the target user should.
   */
  private shouldInitiateConnection(targetUser: string): boolean {
    const currentUserId = this.userService.user;
    const targetUserId = targetUser;

    return currentUserId < targetUserId;
  }
}
