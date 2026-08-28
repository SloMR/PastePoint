import { Injectable, NgZone, inject } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { TelemetryService } from '../monitoring/telemetry.service';
import { WebRTCService } from './webrtc.service';
import { UserService } from '../user-management/user.service';
import { ChatMessage, ChatMessageType, DATA_CHANNEL_MESSAGE_TYPES } from '../../../utils/constants';
import { IChatService } from '../../interfaces/chat.interface';
import { WebSocketConnectionService } from './websocket-connection.service';
import { NGXLogger } from 'ngx-logger';

@Injectable({
  providedIn: 'root',
})
export class ChatService implements IChatService {
  private wsService = inject(WebSocketConnectionService);
  private webrtcService = inject(WebRTCService);
  private userService = inject(UserService);
  private logger = inject(NGXLogger);
  private ngZone = inject(NgZone);
  private telemetry = inject(TelemetryService);

  /**
   * ==========================================================
   * PROPERTIES & OBSERVABLES
   * BehaviorSubject for message state and private message storage
   * ==========================================================
   */
  public messages$ = new BehaviorSubject<ChatMessage[]>([]);
  private messages: ChatMessage[] = [];

  /**
   * ==========================================================
   * CONSTRUCTOR
   * Dependency injection and subscription setup
   * ==========================================================
   */
  constructor() {
    this.webrtcService.chatMessages$.subscribe((message) => {
      this.handleUserMessage(message);
    });

    this.wsService.systemMessages$.subscribe((message) => {
      this.handleSystemMessage(message);
    });

    // The server assigns a new random name on every WebSocket connection.
    // After an automatic reconnect we must re-request the current name.
    this.wsService.reconnected$.subscribe(() => {
      this.getUsername();
    });
  }

  /**
   * ==========================================================
   * USER MANAGEMENT
   * Getter and setter for the current user
   * ==========================================================
   */
  public get user(): string {
    return this.userService.user;
  }

  public set user(value: string) {
    this.userService.user = value;
  }

  /**
   * ==========================================================
   * PUBLIC METHODS
   * Methods for sending messages and managing chat state
   * ==========================================================
   */

  /**
   * Sends message data only to target user without adding to local messages
   * @param content Message content
   * @param targetUser Target user to send to
   * @param messageType Type of message (default: TEXT)
   */
  public async sendMessage(
    content: string,
    targetUser: string,
    messageType: ChatMessageType = ChatMessageType.TEXT
  ): Promise<void> {
    if (content.trim()) {
      const chatMsg: ChatMessage = {
        from: this.user,
        text: content.trim(),
        type: messageType,
        timestamp: new Date(),
      };

      const dataChannelMsg = {
        type: DATA_CHANNEL_MESSAGE_TYPES.CHAT,
        payload: chatMsg,
      };
      this.webrtcService.sendData(dataChannelMsg, targetUser);
      this.logger.info('sendMessage', `Message sent to ${targetUser}: ${chatMsg.text}`);
    } else {
      this.logger.warn('sendMessage', 'Empty message content');
    }
  }

  /**
   * Adds a message to local chat only (UI display)
   * @param content Message content
   * @param messageType Type of message (default: TEXT)
   */
  public addMessageToLocal(
    content: string,
    messageType: ChatMessageType = ChatMessageType.TEXT,
    extras?: Partial<ChatMessage>
  ): void {
    if (content.trim()) {
      const chatMsg: ChatMessage = {
        from: this.user,
        text: content.trim(),
        type: messageType,
        timestamp: new Date(),
        isMine: true,
        ...(extras || {}),
      };

      this.ngZone.run(() => {
        this.messages.push(chatMsg);
        this.messages$.next(this.messages);
      });
      this.logger.info('addMessageToLocal', `Message added to local chat: ${chatMsg.text}`);
    }
  }

  public getUsername(): void {
    this.wsService.send('[UserCommand] /name');
  }

  public clearMessages(): void {
    this.ngZone.run(() => {
      this.messages = [];
      this.messages$.next(this.messages);
    });
  }

  /**
   * Replace all messages (keeps BehaviorSubject and internal array in sync)
   */
  public replaceMessages(messages: ChatMessage[]): void {
    this.ngZone.run(() => {
      this.messages = messages;
      this.messages$.next(this.messages);
    });
  }

  /**
   * Removes every message from a peer, keeping your own.
   * App Review requires a block to clear their content from the feed instantly.
   */
  public removeMessagesFrom(peer: string): void {
    this.ngZone.run(() => {
      this.messages = this.messages.filter((message) => message.isMine || message.from !== peer);
      this.messages$.next(this.messages);
    });
  }

  /**
   * ==========================================================
   * PRIVATE METHODS
   * Handlers for incoming messages
   * ==========================================================
   */
  private handleUserMessage(incoming: ChatMessage): void {
    this.telemetry.event('chat.message_received');
    this.ngZone.run(() => {
      this.messages.push(incoming);
      this.messages$.next(this.messages);
    });
  }

  private handleSystemMessage(message: string): void {
    if (message.includes('[SystemName]')) {
      const matchName = message.match(/\[SystemName]\s*(.*?)$/);
      if (matchName?.[1]) {
        const userName = matchName[1].trim();
        this.logger.info(
          'handleSystemMessage',
          `Username updated from: ${this.user}, to: ${userName}`
        );
        this.user = userName;
      } else {
        this.logger.warn('handleSystemMessage', `No username found in message: ${message}`);
      }
    }
  }
}
