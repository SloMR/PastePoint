import { HttpClient } from '@angular/common/http';
import { Injectable, PLATFORM_ID, inject, signal } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { NGXLogger } from 'ngx-logger';
import { firstValueFrom } from 'rxjs';
import { environment } from '../../../../environments/environment';
import packageJson from '../../../../../package.json';
import { UPDATE_LAST_PROMPT_KEY, UPDATE_OPTIONAL_THROTTLE_MS } from '../../../utils/constants';

// Server response; do not rename fields.
interface PlatformVersion {
  minimum: string;
  latest: string;
  url: string;
}

interface VersionResponse {
  web: PlatformVersion;
}

export type UpdateRecommendation =
  | { kind: 'required'; url: string }
  | { kind: 'optional'; url: string; latest: string };

@Injectable({ providedIn: 'root' })
export class AppUpdateService {
  private http = inject(HttpClient);
  private logger = inject(NGXLogger);
  private platformId = inject(PLATFORM_ID);

  readonly recommendation = signal<UpdateRecommendation | null>(null);

  private readonly installed = packageJson.version;
  private checking = false;

  startMonitoring(): void {
    if (!isPlatformBrowser(this.platformId)) return;

    void this.check();
    document.addEventListener('visibilitychange', () => {
      if (document.visibilityState === 'visible') void this.check();
    });
  }

  async check(): Promise<void> {
    if (!isPlatformBrowser(this.platformId)) return;
    if (this.checking) return;
    this.checking = true;

    try {
      const url = `https://${environment.apiUrl}/version`;
      const res = await firstValueFrom(this.http.get<VersionResponse>(url));
      const next = this.evaluate(res?.web);
      // undefined = leave as-is; a value or null is authoritative (null clears the gate).
      if (next !== undefined) this.recommendation.set(next);
    } catch (error) {
      this.logger.debug('AppUpdateService', 'Version check failed, ignoring', error);
    } finally {
      this.checking = false;
    }
  }

  /** Clears an active optional nudge; a no-op for a required gate. */
  dismissOptional(): void {
    if (this.recommendation()?.kind === 'optional') this.recommendation.set(null);
  }

  private evaluate(policy?: PlatformVersion): UpdateRecommendation | null | undefined {
    if (!policy) return undefined;
    const { minimum, latest, url } = policy;

    // Defensive: floor above latest is a config typo — treat as no-policy.
    if (minimum && latest && this.compare(minimum, latest) > 0) {
      this.logger.warn(
        'AppUpdateService',
        'Version policy misconfigured (minimum > latest); ignoring'
      );
      return undefined;
    }

    if (!url) {
      if (minimum || latest)
        this.logger.warn('AppUpdateService', 'Version policy has no url; ignoring');
      return undefined;
    }

    if (this.isLower(this.installed, minimum)) {
      return { kind: 'required', url }; // force — never throttled
    }
    if (this.isLower(this.installed, latest)) {
      if (!this.shouldShowOptional()) return null;
      this.markOptionalShown();
      return { kind: 'optional', url, latest };
    }
    return null; // up to date — clears the gate
  }

  private isLower(a: string, b: string): boolean {
    if (!b) return false; // empty target = no policy
    return this.compare(a, b) < 0;
  }

  /** Numeric segment-wise compare (-1/0/1); avoids the "0.8.10" < "0.8.2" string bug. */
  private compare(a: string, b: string): number {
    const pa = a.split('.').map((n) => parseInt(n, 10) || 0);
    const pb = b.split('.').map((n) => parseInt(n, 10) || 0);
    const len = Math.max(pa.length, pb.length);
    for (let i = 0; i < len; i++) {
      const diff = (pa[i] ?? 0) - (pb[i] ?? 0);
      if (diff !== 0) return diff < 0 ? -1 : 1;
    }
    return 0;
  }

  private shouldShowOptional(): boolean {
    const raw = localStorage.getItem(UPDATE_LAST_PROMPT_KEY);
    if (!raw) return true;
    const last = parseInt(raw, 10);
    return isNaN(last) || Date.now() - last >= UPDATE_OPTIONAL_THROTTLE_MS;
  }

  private markOptionalShown(): void {
    localStorage.setItem(UPDATE_LAST_PROMPT_KEY, String(Date.now()));
  }
}
