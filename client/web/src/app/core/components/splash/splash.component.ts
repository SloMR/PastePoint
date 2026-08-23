import {
  ChangeDetectionStrategy,
  ChangeDetectorRef,
  Component,
  EventEmitter,
  OnDestroy,
  OnInit,
  Output,
  PLATFORM_ID,
  effect,
  inject,
} from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { Subscription } from 'rxjs';
import { WebSocketConnectionService } from '../../services/communication/websocket-connection.service';
import { AppUpdateService } from '../../services/update/app-update.service';

@Component({
  selector: 'app-splash',
  standalone: true,
  imports: [],
  templateUrl: './splash.component.html',
  styleUrl: './splash.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class SplashComponent implements OnInit, OnDestroy {
  @Output() finished = new EventEmitter<void>();

  private platformId = inject(PLATFORM_ID);
  private cdr = inject(ChangeDetectorRef);
  private ws = inject(WebSocketConnectionService);
  private updateService = inject(AppUpdateService);

  // A required update blocks connecting, so connected$ never fires.
  private readonly updateGateEffect = effect(() => {
    if (this.updateService.recommendation()?.kind === 'required') {
      this.dismiss();
    }
  });

  private timers: ReturnType<typeof setTimeout>[] = [];
  private sub?: Subscription;
  private startedAt = 0;
  private dismissing = false;

  private readonly floorMs = 1400;
  private readonly ceilingMs = 5000;

  protected leaving = false;

  ngOnInit(): void {
    if (!isPlatformBrowser(this.platformId)) {
      return;
    }

    this.startedAt = Date.now();

    if (this.ws.isConnected()) {
      this.dismiss();
    } else {
      this.sub = this.ws.connected$.subscribe(() => this.dismiss());
    }

    this.timers.push(setTimeout(() => this.dismiss(), this.ceilingMs));
  }

  ngOnDestroy(): void {
    this.timers.forEach((t) => clearTimeout(t));
    this.sub?.unsubscribe();
  }

  private dismiss(): void {
    if (this.dismissing) {
      return;
    }
    this.dismissing = true;

    const run = (): void => {
      this.leaving = true;
      this.cdr.markForCheck();
      this.timers.push(setTimeout(() => this.finished.emit(), 400));
    };

    const remaining = this.floorMs - (Date.now() - this.startedAt);
    if (remaining <= 0) {
      run();
    } else {
      this.timers.push(setTimeout(run, remaining));
    }
  }
}
