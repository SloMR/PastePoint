import { Injectable, NgZone, PLATFORM_ID, inject } from '@angular/core';
import * as Sentry from '@sentry/angular';
import { BehaviorSubject, Subject } from 'rxjs';
import {
  BUFFERED_AMOUNT_LOW_THRESHOLD,
  DATA_CHANNEL_MESSAGE_TYPES,
  FILE_TRANSFER_MESSAGE_TYPES,
  MAX_BUFFERED_AMOUNT,
  ChatMessage,
  DataChannelMessage,
} from '../../../utils/constants';
import { NGXLogger } from 'ngx-logger';
import { HotToastService } from '@ngxpert/hot-toast';
import { decodeChunk } from '../../../utils/chunk-protocol';

@Injectable({
  providedIn: 'root',
})
export class WebRTCCommunicationService {
  private zone = inject(NgZone);
  private logger = inject(NGXLogger);
  private toaster = inject(HotToastService);
  private platformId = inject(PLATFORM_ID);

  // =============== Properties ===============

  // Public Subjects
  public dataChannelOpen$ = new BehaviorSubject<boolean>(false);
  public dataChannelClosed$ = new Subject<string>();
  public chatMessages$ = new Subject<ChatMessage>();
  public fileOffers$ = new Subject<{
    fileName: string;
    fileSize: number;
    fromUser: string;
    fileId: string;
    fileHash?: string;
    previewDataUrl?: string;
    previewMime?: string;
  }>();
  public fileResponses$ = new Subject<{ accepted: boolean; fromUser: string; fileId: string }>();
  public fileUploadCancelled$ = new Subject<{ fromUser: string; fileId: string }>();
  public fileDownloadCancelled$ = new Subject<{ fromUser: string; fileId: string }>();
  public fileReceived$ = new Subject<{ fromUser: string; fileId: string }>();
  public bufferedAmountLow$ = new Subject<string>();
  public incomingFileChunk$ = new Subject<{
    fromUser: string;
    fileId: string;
    chunkIndex: number;
    totalChunks: number;
    chunk: ArrayBuffer;
    isValid: boolean;
  }>();

  // Private Collections
  private dataChannels = new Map<string, RTCDataChannel>();
  private messageQueues = new Map<string, (DataChannelMessage | ArrayBuffer)[]>();
  private connectionTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

  // =============== Public Methods ===============

  /**
   * Sets up a new data channel for communication with a target user
   * @param channel The RTCDataChannel to set up
   * @param targetUser The user to communicate with
   */
  public setupDataChannel(channel: RTCDataChannel, targetUser: string): void {
    channel.binaryType = 'arraybuffer';
    this.dataChannels.set(targetUser, channel);

    this.logger.info(
      'setupDataChannel',
      `Setting up data channel with ${targetUser}, initial state: ${channel.readyState}`
    );

    // Clear any existing timeout
    const existingTimeout = this.connectionTimeouts.get(targetUser);
    if (existingTimeout) {
      clearTimeout(existingTimeout);
    }

    const timeout = setTimeout(() => {
      if (channel.readyState === 'connecting') {
        this.logger.warn(
          'setupDataChannel',
          `Connection timeout for ${targetUser}, closing channel`
        );
        channel.close();
        this.dataChannels.delete(targetUser);
        this.connectionTimeouts.delete(targetUser);
        this.messageQueues.delete(targetUser);
        this.zone.run(() => {
          this.logger.warn(
            'setupDataChannel',
            `Connection timeout for ${targetUser}, closing channel`
          );
        });
      }
    }, 30000);
    this.connectionTimeouts.set(targetUser, timeout);

    const handleOpen = () => {
      this.logger.info('setupDataChannel', `Data channel with ${targetUser} is open`);
      this.dataChannelOpen$.next(true);

      // Clear the timeout since connection is established
      const connectionTimeout = this.connectionTimeouts.get(targetUser);
      if (connectionTimeout) {
        clearTimeout(connectionTimeout);
        this.connectionTimeouts.delete(targetUser);
      }

      const queuedMessages = this.messageQueues.get(targetUser);
      if (queuedMessages && queuedMessages.length > 0) {
        this.logger.info(
          'setupDataChannel',
          `Sending ${queuedMessages.length} queued messages to ${targetUser}`
        );
        queuedMessages.forEach((msg) => {
          if (typeof msg === 'object' && !(msg instanceof ArrayBuffer)) {
            channel.send(JSON.stringify(msg));
          } else {
            channel.send(msg);
          }
        });
        this.messageQueues.set(targetUser, []);
      } else {
        this.logger.info('setupDataChannel', `No queued messages for ${targetUser}`);
      }
    };

    if (channel.readyState === 'open') {
      handleOpen();
    } else {
      channel.onopen = handleOpen;
    }

    channel.onmessage = (event) => {
      this.handleDataChannelMessage(event.data, targetUser);
    };

    channel.onerror = (ev: Event) => {
      // Ignore events from stale data channels that have been replaced
      if (this.dataChannels.get(targetUser) !== channel) return;

      let errorDetail = 'unknown';
      if ('error' in ev) {
        const rtcErrorEvent = ev as RTCErrorEvent;
        const error = rtcErrorEvent.error;
        const errorMsg =
          (error && typeof error.message === 'string' && error.message) ||
          (typeof error === 'object' ? JSON.stringify(error) : String(error)) ||
          'Unknown RTCErrorEvent';
        errorDetail = errorMsg;
        this.logger.error('setupDataChannel', `Data Channel Error with ${targetUser}: ${errorMsg}`);
      } else {
        this.logger.error(
          'setupDataChannel',
          `Data Channel Error with ${targetUser}: ${JSON.stringify(ev)}`
        );
      }
      Sentry.addBreadcrumb({
        category: 'webrtc.datachannel',
        level: 'error',
        message: 'data channel error',
        data: { ready_state: channel.readyState, error: errorDetail },
      });
      this.dataChannelClosed$.next(targetUser);
    };

    channel.onclose = () => {
      // Ignore events from stale data channels that have been replaced
      if (this.dataChannels.get(targetUser) !== channel) return;

      this.logger.info('setupDataChannel', `Data channel with ${targetUser} is closed`);
      this.dataChannelOpen$.next(false);
      this.dataChannels.delete(targetUser);

      // Clear any connection timeout
      const connectionTimeout = this.connectionTimeouts.get(targetUser);
      if (connectionTimeout) {
        clearTimeout(connectionTimeout);
        this.connectionTimeouts.delete(targetUser);
      }

      this.dataChannelClosed$.next(targetUser);
    };

    channel.bufferedAmountLowThreshold = BUFFERED_AMOUNT_LOW_THRESHOLD;
    channel.onbufferedamountlow = () => {
      this.bufferedAmountLow$.next(targetUser);
    };
  }

  /**
   * Sends a message through the data channel to a target user
   * @param message The message to send
   * @param targetUser The user to send the message to
   */
  public sendData(message: DataChannelMessage, targetUser: string): void {
    const channel = this.dataChannels.get(targetUser);

    if (channel && channel.readyState === 'open') {
      channel.send(JSON.stringify(message));
    } else if (channel && channel.readyState === 'connecting') {
      this.logger.warn(
        'sendData',
        `Data channel with ${targetUser} is connecting. Message will be queued.`
      );

      this.ensureMessageQueue(targetUser);
      this.messageQueues.get(targetUser)?.push(message);
    } else {
      this.logger.error('sendData', `Data channel with ${targetUser} is not open`);

      if (channel) {
        this.dataChannels.delete(targetUser);
      }

      this.ensureMessageQueue(targetUser);
      this.messageQueues.get(targetUser)?.push(message);
    }
  }

  /**
   * Sends raw data through the data channel to a target user
   * @param data The raw data to send
   * @param targetUser The user to send the data to
   */
  public sendRawData(data: ArrayBuffer, targetUser: string): boolean {
    if (!this.isDataChannelReadyToSend(targetUser)) {
      this.ensureMessageQueue(targetUser);
      this.messageQueues.get(targetUser)?.push(data);
      return false;
    }

    try {
      const channel = this.dataChannels.get(targetUser)!;
      channel.send(data);
      return true;
    } catch (error) {
      this.logger.error('sendRawData', `Error sending raw data: ${error}`);

      this.ensureMessageQueue(targetUser);
      this.messageQueues.get(targetUser)?.push(data);

      return false;
    }
  }

  /**
   * Gets the data channel for a target user
   * @param targetUser The user to get the channel for
   */
  public getDataChannel(targetUser: string): RTCDataChannel | null {
    return this.dataChannels.get(targetUser) ?? null;
  }

  /**
   * Checks if there is an active connection with a target user
   * @param targetUser The user to check connection with
   */
  public isConnected(targetUser: string): boolean {
    const channel = this.dataChannels.get(targetUser);
    return channel?.readyState === 'open';
  }

  /**
   * Checks if a data channel is connecting or connected
   * @param targetUser The user to check connection for
   */
  public isConnectedOrConnecting(targetUser: string): boolean {
    const channel = this.dataChannels.get(targetUser);
    return channel?.readyState === 'open' || channel?.readyState === 'connecting';
  }

  /**
   * Closes all data channel connections
   */
  public closeAllConnections(): void {
    this.dataChannels.forEach((channel) => {
      channel.close();
    });
    this.dataChannels.clear();
    this.messageQueues.clear();

    // Clear all connection timeouts
    this.connectionTimeouts.forEach((timeout) => {
      clearTimeout(timeout);
    });
    this.connectionTimeouts.clear();
  }

  /**
   * Deletes a data channel for a target user
   * @param targetUser The user to delete the channel for
   */
  public deleteDataChannel(targetUser: string): void {
    this.dataChannels.delete(targetUser);

    // Clear any connection timeout
    const connectionTimeout = this.connectionTimeouts.get(targetUser);
    if (connectionTimeout) {
      clearTimeout(connectionTimeout);
      this.connectionTimeouts.delete(targetUser);
    }
  }

  /**
   * Deletes the message queue for a target user
   * @param targetUser The user to delete the queue for
   */
  public deleteMessageQueue(targetUser: string): void {
    this.messageQueues.delete(targetUser);
  }

  /**
   * Sends any queued messages to the target user
   * @param targetUser The user to send queued messages to
   */
  public sendQueuedMessages(targetUser: string): void {
    const channel = this.dataChannels.get(targetUser);
    if (!channel || channel.readyState !== 'open') {
      return;
    }

    const queuedMessages = this.messageQueues.get(targetUser);
    if (queuedMessages && queuedMessages.length > 0) {
      this.logger.info(
        'sendQueuedMessages',
        `Sending ${queuedMessages.length} queued messages to ${targetUser}`
      );
      queuedMessages.forEach((msg) => {
        if (typeof msg === 'object' && !(msg instanceof ArrayBuffer)) {
          channel.send(JSON.stringify(msg));
        } else {
          channel.send(msg);
        }
      });
      this.messageQueues.set(targetUser, []);
    }
  }

  // =============== Private Methods ===============

  /**
   * Handles incoming data channel messages
   * @param data The received data
   * @param targetUser The user who sent the data
   */
  private handleDataChannelMessage(data: unknown, targetUser: string): void {
    this.zone.run(() => {
      if (typeof data === 'string') {
        let message: DataChannelMessage;
        try {
          message = JSON.parse(data);
        } catch (e) {
          this.logger.error(
            'handleDataChannelMessage',
            `Failed to parse data channel message from ${targetUser}: ${e instanceof Error ? e.message : String(e)}`,
            e
          );
          return;
        }
        switch (message.type) {
          case DATA_CHANNEL_MESSAGE_TYPES.CHAT: {
            let chatMsg = message.payload as ChatMessage;
            chatMsg.timestamp = new Date(chatMsg.timestamp);
            this.chatMessages$.next(chatMsg);
            break;
          }
          case FILE_TRANSFER_MESSAGE_TYPES.FILE_OFFER: {
            this.logger.info('handleDataChannelMessage', `Received file offer from ${targetUser}`);
            const fileOfferPayload = message.payload as {
              fileId: string;
              fileName: string;
              fileSize: number;
              fileHash?: string;
              previewDataUrl?: string;
              previewMime?: string;
            };
            this.fileOffers$.next({
              fileId: fileOfferPayload.fileId,
              fileName: fileOfferPayload.fileName,
              fileSize: fileOfferPayload.fileSize,
              fileHash: fileOfferPayload.fileHash,
              fromUser: targetUser,
              previewDataUrl: fileOfferPayload.previewDataUrl,
              previewMime: fileOfferPayload.previewMime,
            });
            break;
          }
          case FILE_TRANSFER_MESSAGE_TYPES.FILE_ACCEPT: {
            this.logger.info(
              'handleDataChannelMessage',
              `Received file acceptance from ${targetUser}`
            );
            const fileAcceptPayload = message.payload as { fileId: string };
            this.fileResponses$.next({
              accepted: true,
              fromUser: targetUser,
              fileId: fileAcceptPayload.fileId,
            });
            break;
          }
          case FILE_TRANSFER_MESSAGE_TYPES.FILE_DECLINE: {
            this.logger.info(
              'handleDataChannelMessage',
              `Received file decline from ${targetUser}`
            );
            const fileDeclinePayload = message.payload as { fileId: string };
            this.fileResponses$.next({
              accepted: false,
              fromUser: targetUser,
              fileId: fileDeclinePayload.fileId,
            });
            break;
          }
          case FILE_TRANSFER_MESSAGE_TYPES.FILE_CANCEL_UPLOAD: {
            this.logger.info(
              'handleDataChannelMessage',
              `Received uploading file cancellation from ${targetUser}`
            );
            const fileCancelUploadPayload = message.payload as { fileId: string };
            this.fileUploadCancelled$.next({
              fromUser: targetUser,
              fileId: fileCancelUploadPayload.fileId,
            });
            break;
          }
          case FILE_TRANSFER_MESSAGE_TYPES.FILE_CANCEL_DOWNLOAD: {
            this.logger.info(
              'handleDataChannelMessage',
              `Received downloading file cancellation from ${targetUser}`
            );
            const fileCancelDownloadPayload = message.payload as { fileId: string };
            this.fileDownloadCancelled$.next({
              fromUser: targetUser,
              fileId: fileCancelDownloadPayload.fileId,
            });
            break;
          }
          case FILE_TRANSFER_MESSAGE_TYPES.FILE_RECEIVED: {
            this.logger.info(
              'handleDataChannelMessage',
              `Received file assembly confirmation from ${targetUser}`
            );
            const fileReceivedPayload = message.payload as { fileId: string };
            this.fileReceived$.next({
              fromUser: targetUser,
              fileId: fileReceivedPayload.fileId,
            });
            break;
          }
          default:
            this.logger.warn('handleDataChannelMessage', `Unknown message type: ${message.type}`);
        }
      } else if (data instanceof ArrayBuffer) {
        const parsed = decodeChunk(data);

        if (parsed) {
          const { metadata, data: chunkData, isValid } = parsed;

          // Log first chunk for each file
          if (metadata.chunkIndex === 0) {
            this.logger.info(
              'handleDataChannelMessage',
              `First chunk received for ${metadata.fileId.substring(0, 8)}... (${chunkData.byteLength} bytes, CRC: ${isValid ? 'OK' : 'FAIL'})`
            );
          }

          this.incomingFileChunk$.next({
            fromUser: targetUser,
            fileId: metadata.fileId,
            chunkIndex: metadata.chunkIndex,
            totalChunks: metadata.totalChunks,
            chunk: chunkData,
            isValid,
          });
        } else {
          this.logger.error(
            'handleDataChannelMessage',
            `Failed to decode chunk from ${targetUser}, size: ${data.byteLength}`
          );
          Sentry.addBreadcrumb({
            category: 'webrtc.datachannel',
            level: 'error',
            message: 'chunk decode failed',
          });
        }
      } else {
        this.logger.warn(
          'handleDataChannelMessage',
          `Unknown data type from ${targetUser}: ${typeof data}`
        );
      }
    });
  }

  // =============== Helper Methods ===============

  /**
   * Ensures a message queue exists for the target user
   * @param targetUser The user to ensure the queue for
   */
  private ensureMessageQueue(targetUser: string): void {
    if (!this.messageQueues.has(targetUser)) {
      this.messageQueues.set(targetUser, []);
    }
  }

  /**
   * Checks if a data channel is ready to send data
   * @param targetUser The user to check the channel for
   */
  private isDataChannelReadyToSend(targetUser: string): boolean {
    const channel = this.dataChannels.get(targetUser);

    if (!channel) {
      this.logger.warn('isDataChannelReadyToSend', `No data channel exists for ${targetUser}`);
      return false;
    }

    if (channel.readyState !== 'open') {
      this.logger.warn(
        'isDataChannelReadyToSend',
        `Data channel with ${targetUser} is in state: ${channel.readyState}`
      );
      return false;
    }

    if (channel.bufferedAmount > MAX_BUFFERED_AMOUNT) {
      this.logger.warn(
        'isDataChannelReadyToSend',
        `Data channel buffer for ${targetUser} is full: ${channel.bufferedAmount} bytes`
      );
      return false;
    }

    return true;
  }
}
