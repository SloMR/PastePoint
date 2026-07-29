import { Injectable, OnDestroy, inject } from '@angular/core';
import { DeviceDetectorService } from 'ngx-device-detector';
import { NGXLogger } from 'ngx-logger';
import { Subject } from 'rxjs';

import {
  HEARTBEAT_INTERVAL_DESKTOP_SEC,
  HEARTBEAT_INTERVAL_MOBILE_SEC,
  HEARTBEAT_TIMEOUT_DESKTOP_SEC,
  HEARTBEAT_TIMEOUT_MOBILE_SEC,
} from '../../../utils/constants';

@Injectable({ providedIn: 'root' })
export class HeartbeatService implements OnDestroy {
  private deviceDetector = inject(DeviceDetectorService);
  private logger = inject(NGXLogger);

  private intervalId: ReturnType<typeof setInterval> | null = null;
  private lastHeartbeat: number = Date.now();
  private hiddenAt: number | null = null;
  private heartbeatTimeout = 0;
  private visibilityChangeListener: (() => void) | null = null;

  /** Emits when a suspension is detected (interval missed by more than the timeout) */
  readonly suspended$ = new Subject<{ secondsSinceLastBeat: number }>();

  start(): void {
    this.stop();

    const isDesktop = this.deviceDetector.isDesktop();
    const heartbeatInterval = isDesktop
      ? HEARTBEAT_INTERVAL_DESKTOP_SEC
      : HEARTBEAT_INTERVAL_MOBILE_SEC;
    const heartbeatTimeout = isDesktop
      ? HEARTBEAT_TIMEOUT_DESKTOP_SEC
      : HEARTBEAT_TIMEOUT_MOBILE_SEC;
    this.heartbeatTimeout = heartbeatTimeout;

    this.logger.debug(
      'HeartbeatService.start',
      `Starting heartbeat for ${isDesktop ? 'desktop' : 'mobile'} with ${heartbeatInterval}s interval`
    );

    this.lastHeartbeat = Date.now();
    this.setupVisibilityMonitor();

    this.intervalId = setInterval(() => {
      const now = Date.now();
      const diff = (now - this.lastHeartbeat) / 1000;
      this.lastHeartbeat = now;

      if (diff > heartbeatTimeout) {
        this.logger.warn('HeartbeatService', `Suspension detected: last beat ${diff}s ago`);
        this.suspended$.next({ secondsSinceLastBeat: diff });
      }
    }, heartbeatInterval * 1000);
  }

  private setupVisibilityMonitor(): void {
    if (typeof document === 'undefined') return;

    this.visibilityChangeListener = () => {
      if (document.visibilityState === 'hidden') {
        this.hiddenAt = Date.now();
        return;
      }

      if (document.visibilityState !== 'visible' || this.hiddenAt === null) return;

      const now = Date.now();
      const secondsInBackground = (now - this.hiddenAt) / 1000;
      this.hiddenAt = null;
      this.lastHeartbeat = now;

      if (secondsInBackground > this.heartbeatTimeout) {
        this.logger.warn(
          'HeartbeatService',
          `Suspension detected on resume: backgrounded for ${secondsInBackground}s`
        );
        this.suspended$.next({ secondsSinceLastBeat: secondsInBackground });
      }
    };

    document.addEventListener('visibilitychange', this.visibilityChangeListener);
  }

  stop(): void {
    if (this.intervalId) {
      clearInterval(this.intervalId);
      this.intervalId = null;
      this.logger.debug('HeartbeatService.stop', 'Heartbeat stopped');
    }

    if (this.visibilityChangeListener && typeof document !== 'undefined') {
      document.removeEventListener('visibilitychange', this.visibilityChangeListener);
      this.visibilityChangeListener = null;
    }
    this.hiddenAt = null;
  }

  ngOnDestroy(): void {
    this.stop();
    this.suspended$.complete();
  }
}
