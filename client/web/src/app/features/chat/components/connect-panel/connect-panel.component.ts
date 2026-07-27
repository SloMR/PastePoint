import {
  ChangeDetectionStrategy,
  ChangeDetectorRef,
  Component,
  ElementRef,
  EventEmitter,
  Input,
  OnChanges,
  Output,
  PLATFORM_ID,
  SimpleChanges,
  ViewChild,
  inject,
} from '@angular/core';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { TranslateModule, TranslateService } from '@ngx-translate/core';
import { HotToastService } from '@ngxpert/hot-toast';
import { NGXLogger } from 'ngx-logger';
import * as QRCode from 'qrcode';

import { environment } from '../../../../../environments/environment';
import { JoinCodeFormComponent } from '../join-code-form/join-code-form.component';

@Component({
  selector: 'app-connect-panel',
  imports: [CommonModule, TranslateModule, JoinCodeFormComponent],
  templateUrl: './connect-panel.component.html',
  styleUrl: './connect-panel.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ConnectPanelComponent implements OnChanges {
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

  @ViewChild('qrContainer') qrContainer?: ElementRef<HTMLDivElement>;

  private platformId = inject(PLATFORM_ID);
  private toaster = inject(HotToastService);
  private translate = inject(TranslateService);
  private logger = inject(NGXLogger);
  private cdr = inject(ChangeDetectorRef);

  protected get canShare(): boolean {
    return isPlatformBrowser(this.platformId) && typeof navigator.share === 'function';
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['isOpen']?.currentValue === true || (this.isOpen && changes['sessionUrl'])) {
      requestAnimationFrame(() => void this.renderQRCode());
    }
  }

  protected async shareInvite(): Promise<void> {
    if (!this.canShare || !this.sessionUrl) return;
    try {
      await navigator.share({ url: this.sessionUrl });
    } catch {
      // dismissed
    }
  }

  private async renderQRCode(): Promise<void> {
    if (!isPlatformBrowser(this.platformId)) return;
    if (!this.sessionUrl || !this.qrContainer) return;

    try {
      if (new URL(this.sessionUrl).host !== environment.webUrl) {
        this.logger.warn('renderQRCode', 'Rejected QR code for external URL');
        return;
      }

      const host = this.qrContainer.nativeElement;
      while (host.firstChild) host.removeChild(host.firstChild);

      const canvas = document.createElement('canvas');
      await QRCode.toCanvas(canvas, this.sessionUrl, {
        width: 180,
        margin: 2,
        errorCorrectionLevel: 'L',
        color: { dark: '#000000', light: '#FFFFFF' },
      });
      host.appendChild(canvas);
      this.cdr.markForCheck();
    } catch (error) {
      this.logger.error('renderQRCode', 'Failed to generate QR code:', error);
      this.toaster.error(this.translate.instant('QR_CODE_GENERATION_FAILED'));
    }
  }
}
