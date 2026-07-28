import {
  ChangeDetectionStrategy,
  Component,
  EventEmitter,
  Input,
  Output,
  PLATFORM_ID,
  inject,
} from '@angular/core';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';

import { WelcomeCardComponent } from './welcome-card/welcome-card.component';
import { JoinCodeFormComponent } from '../join-code-form/join-code-form.component';
import { SessionQrCodeComponent } from '../session-qr-code/session-qr-code.component';

@Component({
  selector: 'app-welcome',
  imports: [
    CommonModule,
    TranslateModule,
    WelcomeCardComponent,
    JoinCodeFormComponent,
    SessionQrCodeComponent,
  ],
  templateUrl: './welcome.component.html',
  styleUrl: './welcome.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class WelcomeComponent {
  @Input() sessionCode = '';
  @Input() sessionUrl = '';
  @Input() memberCount = 0;
  @Input() isRTL = false;
  @Input() isDarkMode = false;

  @Output() connectDeviceRequested = new EventEmitter<void>();
  @Output() copyRequested = new EventEmitter<void>();
  @Output() joinRequested = new EventEmitter<string>();
  @Output() scanRequested = new EventEmitter<void>();

  private platformId = inject(PLATFORM_ID);

  protected get canShare(): boolean {
    return isPlatformBrowser(this.platformId) && typeof navigator.share === 'function';
  }

  protected async shareInvite(): Promise<void> {
    if (!this.canShare || !this.sessionUrl) return;
    try {
      await navigator.share({ url: this.sessionUrl });
    } catch {
      // dismissed
    }
  }
}
