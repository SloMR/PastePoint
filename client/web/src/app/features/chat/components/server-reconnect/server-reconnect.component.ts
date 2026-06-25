import { Component, OnDestroy, OnInit, inject, signal } from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';
import { Subscription } from 'rxjs';
import { WebSocketConnectionService } from '../../../../core/services/communication/websocket-connection.service';

@Component({
  selector: 'app-server-reconnect',
  imports: [CommonModule, TranslateModule],
  templateUrl: './server-reconnect.component.html',
  styleUrl: './server-reconnect.component.css',
})
export class ServerReconnectComponent implements OnInit, OnDestroy {
  private wsConnection = inject(WebSocketConnectionService);

  protected readonly show = signal(false);
  protected readonly attempt = signal(0);
  protected readonly secondsRemaining = signal(0);

  private subscription?: Subscription;
  private ticker?: ReturnType<typeof setInterval>;
  private nextAttemptAt = 0;

  ngOnInit(): void {
    this.subscription = this.wsConnection.reconnectState$.subscribe((state) => {
      if (state) {
        this.attempt.set(state.attempt);
        this.nextAttemptAt = state.nextAttemptAt;
        this.show.set(true);
        this.updateRemaining();
        this.startTicker();
      } else {
        this.show.set(false);
        this.stopTicker();
      }
    });
  }

  ngOnDestroy(): void {
    this.subscription?.unsubscribe();
    this.stopTicker();
  }

  private startTicker(): void {
    this.stopTicker();
    this.ticker = setInterval(() => this.updateRemaining(), 1000);
  }

  private stopTicker(): void {
    if (this.ticker) {
      clearInterval(this.ticker);
      this.ticker = undefined;
    }
  }

  private updateRemaining(): void {
    this.secondsRemaining.set(Math.max(0, Math.ceil((this.nextAttemptAt - Date.now()) / 1000)));
  }
}
