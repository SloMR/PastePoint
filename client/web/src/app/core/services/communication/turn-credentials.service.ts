import { HttpClient } from '@angular/common/http';
import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { NGXLogger } from 'ngx-logger';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../../environments/environment';
import { ICE_SERVERS } from '../../../utils/constants';

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
  private fetching = false;

  constructor() {
    // Warm the cache at construction
    void this.refresh();
  }

  get iceServers(): RTCIceServer[] {
    return this.servers;
  }

  async refresh(): Promise<void> {
    if (!isPlatformBrowser(this.platformId) || this.fetching) return;
    this.fetching = true;

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
        this.logger.info('TurnCredentialsService', 'No TURN relay configured on server — STUN-only');
      }
    } catch (error) {
      this.logger.debug('TurnCredentialsService', 'TURN fetch failed, STUN-only', error);
    } finally {
      this.fetching = false;
    }
  }
}
