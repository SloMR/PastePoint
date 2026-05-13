import { Injectable, NgZone, inject } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import * as Sentry from '@sentry/angular';
import { startNewTrace } from '@sentry/core';
import { WebSocketConnectionService } from '../communication/websocket-connection.service';
import { NGXLogger } from 'ngx-logger';
import { IRoomService } from '../../interfaces/room.interface';

@Injectable({
  providedIn: 'root',
})
export class RoomService implements IRoomService {
  private wsService = inject(WebSocketConnectionService);
  private logger = inject(NGXLogger);
  private ngZone = inject(NgZone);

  /**
   * ==========================================================
   * PROPERTIES & OBSERVABLES
   * BehaviorSubjects for room and member state
   * ==========================================================
   */
  public rooms$ = new BehaviorSubject<string[]>([]);
  public members$ = new BehaviorSubject<string[]>([]);
  public currentRoom = 'main';

  private pendingJoinSpan: Sentry.Span | null = null;
  private pendingJoinTimeout: ReturnType<typeof setTimeout> | null = null;
  private static readonly JOIN_SPAN_TIMEOUT_MS = 10_000;

  private clearPendingJoinSpan(
    outcome: 'cancelled' | 'superseded' | 'timeout' | 'joined',
    statusCode: 1 | 2
  ): void {
    if (this.pendingJoinTimeout) {
      clearTimeout(this.pendingJoinTimeout);
      this.pendingJoinTimeout = null;
    }
    if (this.pendingJoinSpan) {
      this.pendingJoinSpan.setAttribute('outcome', outcome);
      this.pendingJoinSpan.setStatus({ code: statusCode, message: outcome });
      this.pendingJoinSpan.end();
      this.pendingJoinSpan = null;
    }
  }

  /**
   * ==========================================================
   * CONSTRUCTOR
   * Dependency injection and subscription setup
   * ==========================================================
   */
  constructor() {
    this.wsService.systemMessages$.subscribe((message) => {
      this.handleSystemMessage(message);
    });
  }

  /**
   * ==========================================================
   * PUBLIC METHODS
   * Methods for room management operations
   * ==========================================================
   */
  public listRooms(): void {
    this.logger.info('listRooms', 'Listing rooms');
    this.wsService.send('[UserCommand] /list');
  }

  /**
   * Resets singleton state on session transition so BehaviorSubjects don't
   * replay the previous session's members/rooms into the new view.
   */
  public reset(): void {
    this.clearPendingJoinSpan('cancelled', 2);
    this.ngZone.run(() => {
      this.rooms$.next([]);
      this.members$.next([]);
      this.currentRoom = 'main';
    });
  }

  public joinRoom(room: string): void {
    const sanitizedRoom = room
      .replace(/[^a-zA-Z0-9\-_ ]/g, '')
      .trim()
      .substring(0, 64);

    if (!sanitizedRoom) {
      this.logger.warn('joinRoom', `Room name is empty after sanitization: ${room}`);
      return;
    }

    if (sanitizedRoom === this.currentRoom) {
      this.logger.warn('joinRoom', `Already in room: ${room}`);
      return;
    }

    this.clearPendingJoinSpan('superseded', 2);

    startNewTrace(() => {
      this.pendingJoinSpan = Sentry.startInactiveSpan({
        name: 'room.join',
        op: 'session.join',
      });
    });
    this.pendingJoinTimeout = setTimeout(() => {
      this.logger.warn('joinRoom', `Join timed out for room: ${sanitizedRoom}`);
      this.clearPendingJoinSpan('timeout', 2);
    }, RoomService.JOIN_SPAN_TIMEOUT_MS);
    this.wsService.send(`[UserCommand] /join ${sanitizedRoom}`);
  }

  /**
   * ==========================================================
   * PRIVATE METHODS
   * Handlers for system messages
   * ==========================================================
   */
  private handleSystemMessage(message: string): void {
    if (message.includes('[SystemRooms]')) {
      const matchRooms = message.match(/\[SystemRooms]\s*(.*?)$/);
      if (matchRooms) {
        const rooms = matchRooms[1].split(',').map((room: string) => room.trim());
        this.ngZone.run(() => {
          this.rooms$.next(rooms);
        });
      } else {
        this.logger.warn('handleSystemMessage', `No rooms found in message: ${message}`);
      }
    } else if (message.includes('[SystemMembers]')) {
      const matchMembers = message.match(/\[SystemMembers]\s*(.*?)$/);
      if (matchMembers) {
        const members = matchMembers[1].split(',').map((member: string) => member.trim());
        this.ngZone.run(() => {
          this.members$.next(members);
        });
      } else {
        this.logger.warn('handleSystemMessage', `No members found in message: ${message}`);
      }
    } else if (message.includes('[SystemJoin]')) {
      const matchJoin = message.match(/^(.*?)\s*\[SystemJoin]\s*(.*?)$/);
      if (matchJoin) {
        this.logger.info('handleSystemMessage', `User joined room ${matchJoin[2]}`);
        this.ngZone.run(() => {
          this.currentRoom = matchJoin[2];
        });

        this.clearPendingJoinSpan('joined', 1);
      } else {
        this.logger.warn('handleSystemMessage', `No room to join found in message: ${message}`);
      }
    }
  }
}
