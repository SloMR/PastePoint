import { Injectable, effect, inject } from '@angular/core';
import { BehaviorSubject, Observable, Subject } from 'rxjs';
import { ChatMessage, DataChannelMessage } from '../../../utils/constants';
import { IWebRTCService } from '../../interfaces/webrtc.interface';
import { WebRTCSignalingService } from './webrtc-signaling.service';
import { WebRTCCommunicationService } from './webrtc-communication.service';
import { AppUpdateService } from '../update/app-update.service';
import { NGXLogger } from 'ngx-logger';

@Injectable({
  providedIn: 'root',
})
export class WebRTCService implements IWebRTCService {
  private signalingService = inject(WebRTCSignalingService);
  private communicationService = inject(WebRTCCommunicationService);
  private updateService = inject(AppUpdateService);
  private logger = inject(NGXLogger);

  constructor() {
    effect(() => {
      if (this.updateService.recommendation()?.kind === 'required') {
        this.logger.warn('updateGate', 'Update required, closing all peer connections');
        this.closeAllConnections();
      }
    });
  }

  // =============== Public Properties ===============
  public get peerDisconnected$(): Observable<string> {
    return this.signalingService.peerDisconnected$.asObservable();
  }

  public get peerConnected$(): Observable<string> {
    return this.signalingService.peerConnected$.asObservable();
  }

  /**
   * Gets the data channel open subject
   */
  public get dataChannelOpen$(): BehaviorSubject<boolean> {
    return this.communicationService.dataChannelOpen$;
  }

  /**
   * Gets the chat messages subject
   */
  public get chatMessages$(): Subject<ChatMessage> {
    return this.communicationService.chatMessages$;
  }

  /**
   * Gets the file offers subject
   */
  public get fileOffers$(): Subject<{
    fileName: string;
    fileSize: number;
    fromUser: string;
    fileId: string;
    fileHash?: string;
  }> {
    return this.communicationService.fileOffers$;
  }

  /**
   * Gets the file responses subject
   */
  public get fileResponses$(): Subject<{ accepted: boolean; fromUser: string; fileId: string }> {
    return this.communicationService.fileResponses$;
  }

  /**
   * Gets the file upload cancelled subject
   */
  public get fileUploadCancelled$(): Subject<{ fromUser: string; fileId: string }> {
    return this.communicationService.fileUploadCancelled$;
  }

  /**
   * Gets the file download cancelled subject
   */
  public get fileDownloadCancelled$(): Subject<{ fromUser: string; fileId: string }> {
    return this.communicationService.fileDownloadCancelled$;
  }

  /**
   * Gets the file received subject
   */
  public get fileReceived$(): Subject<{ fromUser: string; fileId: string }> {
    return this.communicationService.fileReceived$;
  }

  /**
   * Gets the buffered amount low subject
   */
  public get bufferedAmountLow$(): Subject<string> {
    return this.communicationService.bufferedAmountLow$;
  }

  /**
   * Gets the incoming file chunk subject
   */
  public get incomingFileChunk$(): Subject<{
    fromUser: string;
    fileId: string;
    chunkIndex: number;
    totalChunks: number;
    chunk: ArrayBuffer;
    isValid: boolean;
  }> {
    return this.communicationService.incomingFileChunk$;
  }

  // =============== Public Methods ===============
  /**
   * Initiates a new WebRTC connection with a target user
   * @param targetUser The user to connect with
   */
  public initiateConnection(targetUser: string): void {
    this.signalingService.initiateConnection(targetUser);
  }

  /**
   * Sends a message to a target user
   * @param message The message to send
   * @param targetUser The user to send the message to
   */
  public sendData(message: DataChannelMessage, targetUser: string): void {
    // When the other device started the connection we have no channel yet;
    // restarting here would throw away the setup this message is waiting for.
    if (!this.isReachable(targetUser)) {
      const dataChannel = this.communicationService.getDataChannel(targetUser);
      const peerConnection = this.signalingService.getPeerConnection(targetUser);

      if (peerConnection && !dataChannel) {
        this.logger.warn(
          'sendData',
          `State mismatch for ${targetUser}: peer connection exists but no data channel`
        );

        this.signalingService.closePeerConnection(targetUser, true);
      } else {
        this.logger.info('sendData', `Initiating connection to ${targetUser}`);
      }

      this.signalingService.initiateConnection(targetUser);
    }

    this.communicationService.sendData(message, targetUser);
  }

  /**
   * Sends raw data to a target user
   * @param data The raw data to send
   * @param targetUser The user to send the data to
   */
  public sendRawData(data: ArrayBuffer, targetUser: string): boolean {
    if (!this.isReachable(targetUser)) {
      this.signalingService.initiateConnection(targetUser);
    }
    return this.communicationService.sendRawData(data, targetUser);
  }

  /**
   * Gets the data channel for a target user
   * @param targetUser The user to get the channel for
   */
  public getDataChannel(targetUser: string): RTCDataChannel | null {
    return this.communicationService.getDataChannel(targetUser);
  }

  /**
   * Checks if there is an active connection with a target user
   * @param targetUser The user to check connection with
   */
  public isConnected(targetUser: string): boolean {
    return this.communicationService.isConnected(targetUser);
  }

  /**
   * Checks if an attempt with a target user is in flight. Needs no data channel,
   * so unlike the channel state it also holds while we are the callee.
   * @param targetUser The user to check
   */
  public isConnecting(targetUser: string): boolean {
    return this.signalingService.isConnecting(targetUser);
  }

  /**
   * Checks if a target user is connected or being connected to, i.e. whether a
   * new attempt would be redundant
   * @param targetUser The user to check
   */
  public isReachable(targetUser: string): boolean {
    return this.isConnected(targetUser) || this.isConnecting(targetUser);
  }

  /**
   * Checks if the connection is ready for file transfers
   * @param targetUser The user to check connection for
   */
  public isReadyForFileTransfer(targetUser: string): boolean {
    return this.communicationService.isConnected(targetUser);
  }

  public closeConnection(targetUser: string): void {
    this.signalingService.closeConnection(targetUser);
  }

  /**
   * Closes all connections
   */
  public closeAllConnections(): void {
    this.signalingService.closeAllConnections();
    this.communicationService.closeAllConnections();
  }
}
