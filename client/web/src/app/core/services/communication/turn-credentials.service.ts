import { HttpClient } from '@angular/common/http';
import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { NGXLogger } from 'ngx-logger';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../../environments/environment';
import { ICE_SERVERS, TURN_READY_TIMEOUT, TURN_RETRY_COOLDOWN } from '../../../utils/constants';

// Server response; do not rename fields.
interface TurnCredentialsResponse {
  username: string;
  credential: string;
  ttl: number;
  urls: string[];
}

/**
 * Fetches short-lived TURN credentials from `GET /turn-credentials` and exposes
 * the ICE server list (STUN + relay). Refreshed on each WebSocket connect so a
 * long-idle tab never relays with an expired credential; failures fall back to
 * STUN-only (direct/STUN connections still work).
 */
@Injectable({ providedIn: 'root' })
export class TurnCredentialsService {
  private http = inject(HttpClient);
  private logger = inject(NGXLogger);
  private platformId = inject(PLATFORM_ID);

  private servers: RTCIceServer[] = [...ICE_SERVERS];
  private inflight: Promise<void> | null = null;
  private hasServerAnswered = false;
  private nextRetryAt = 0;

  constructor() {
    // Warm the cache at construction
    void this.refresh();
  }

  get iceServers(): RTCIceServer[] {
    return this.servers;
  }

  /**
   * Resolves once the server has answered, so a peer connection is never built
   * STUN-only while the first fetch is in flight. A failure is retried, but only
   * after `TURN_RETRY_COOLDOWN` — an unreachable endpoint would otherwise be hit
   * again on every peer. `TURN_READY_TIMEOUT` caps how long a peer waits.
   */
  async ready(): Promise<void> {
    if (!isPlatformBrowser(this.platformId) || this.hasServerAnswered) return;
    if (Date.now() < this.nextRetryAt) return;

    await Promise.race([
      this.refresh(),
      new Promise<void>((resolve) => setTimeout(resolve, TURN_READY_TIMEOUT)),
    ]);
  }

  /** Fetches credentials, sharing a single in-flight request between callers. */
  refresh(): Promise<void> {
    if (!isPlatformBrowser(this.platformId)) return Promise.resolve();

    this.inflight ??= this.load().finally(() => (this.inflight = null));
    return this.inflight;
  }

  private async load(): Promise<void> {
    try {
      const url = `https://${environment.apiUrl}/turn-credentials`;
      const res = await firstValueFrom(this.http.get<TurnCredentialsResponse>(url));
      if (res?.urls?.length && res.username && res.credential) {
        this.servers = [
          ...ICE_SERVERS,
          { urls: res.urls, username: res.username, credential: res.credential },
        ];
        this.logger.info(
          'TurnCredentialsService',
          `TURN credentials fetched — relay available (ttl ${res.ttl}s, urls: ${res.urls.join(', ')})`
        );
      } else {
        // 204 / disabled — stay STUN-only.
        this.servers = [...ICE_SERVERS];
        this.logger.info(
          'TurnCredentialsService',
          'No TURN relay configured on server — STUN-only'
        );
      }
      this.hasServerAnswered = true;
    } catch (error) {
      this.nextRetryAt = Date.now() + TURN_RETRY_COOLDOWN;
      this.logger.debug('TurnCredentialsService', 'TURN fetch failed, STUN-only', error);
    }
  }
}
