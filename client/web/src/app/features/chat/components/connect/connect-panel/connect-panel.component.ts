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

import { canWebShare, shareUrl } from '../../../../../utils/web-share.util';
import { JoinCodeFormComponent } from '../join-code-form/join-code-form.component';
import { SessionQrCodeComponent } from '../session-qr-code/session-qr-code.component';

@Component({
  selector: 'app-connect-panel',
  imports: [CommonModule, TranslateModule, JoinCodeFormComponent, SessionQrCodeComponent],
  templateUrl: './connect-panel.component.html',
  styleUrl: './connect-panel.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ConnectPanelComponent {
  @Input() isOpen = false;
  @Input() sessionCode = '';
  @Input() sessionUrl = '';
  @Input() memberCount = 0;
  @Input() isRTL = false;

  @Output() closed = new EventEmitter<void>();
  @Output() createRequested = new EventEmitter<void>();
  @Output() copyRequested = new EventEmitter<void>();
  @Output() scanRequested = new EventEmitter<void>();
  @Output() joinRequested = new EventEmitter<string>();

  private platformId = inject(PLATFORM_ID);

  protected get canShare(): boolean {
    return canWebShare(this.platformId);
  }

  protected async shareInvite(): Promise<void> {
    if (!this.canShare || !this.sessionUrl) return;
    await shareUrl(this.sessionUrl);
  }
}
