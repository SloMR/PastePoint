import {
  ChangeDetectionStrategy,
  Component,
  EventEmitter,
  Input,
  Output,
  PLATFORM_ID,
  inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';

import { canWebShare, shareUrl } from '../../../../utils/web-share.util';

import { WelcomeCardComponent } from './welcome-card/welcome-card.component';
import { JoinCodeFormComponent } from '../connect/join-code-form/join-code-form.component';
import { SessionQrCodeComponent } from '../connect/session-qr-code/session-qr-code.component';

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
    return canWebShare(this.platformId);
  }

  protected async shareInvite(): Promise<void> {
    if (!this.canShare || !this.sessionUrl) return;
    await shareUrl(this.sessionUrl);
  }
}
