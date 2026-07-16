import { Injectable, inject } from '@angular/core';
import { BehaviorSubject } from 'rxjs';
import { NGXLogger } from 'ngx-logger';
import { WebSocketConnectionService } from './websocket-connection.service';

@Injectable({
  providedIn: 'root',
})
export class BlockService {
  private wsService = inject(WebSocketConnectionService);
  private logger = inject(NGXLogger);

  public blockedPeers$ = new BehaviorSubject<Set<string>>(new Set());
  private blockedPeers = new Set<string>();

  constructor() {
    this.wsService.connected$.subscribe(() => this.clear());
  }

  public block(peer: string): void {
    if (!peer) {
      return;
    }

    this.logger.info('block', `Blocking peer ${peer}`);
    this.blockedPeers.add(peer);
    this.blockedPeers$.next(new Set(this.blockedPeers));
  }

  public unblock(peer: string): void {
    this.logger.info('unblock', `Unblocking peer ${peer}`);

    this.blockedPeers.delete(peer);
    this.blockedPeers$.next(new Set(this.blockedPeers));
  }

  public isBlocked(peer: string): boolean {
    return this.blockedPeers.has(peer);
  }

  private clear(): void {
    if (this.blockedPeers.size === 0) {
      return;
    }

    this.logger.debug('clear', 'Clearing blocks — identities are reassigned on reconnect');
    this.blockedPeers.clear();
    this.blockedPeers$.next(new Set());
  }
}
