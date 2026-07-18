import {
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
import { environment } from '../../../../../../environments/environment';

@Component({
  selector: 'app-qr-code-popup',
  imports: [CommonModule, TranslateModule],
  templateUrl: './qr-code-popup.component.html',
  styleUrl: './qr-code-popup.component.css',
})
export class QrCodePopupComponent implements OnChanges {
  @Input() isOpen = false;
  @Input() isRTL = false;
  @Input() sessionUrl = '';

  @Output() closed = new EventEmitter<void>();

  @ViewChild('qrCodeContainer', { static: false }) qrCodeContainer?: ElementRef;

  protected isGenerating = false;

  private platformId = inject(PLATFORM_ID);
  private toaster = inject(HotToastService);
  private translate = inject(TranslateService);
  private logger = inject(NGXLogger);

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['isOpen']?.currentValue === true) {
      requestAnimationFrame(() => this.generateQRCode());
    }
  }

  private async generateQRCode(): Promise<void> {
    if (!isPlatformBrowser(this.platformId)) return;
    if (!this.sessionUrl || !this.qrCodeContainer) return;

    try {
      const parsedUrl = new URL(this.sessionUrl);
      if (parsedUrl.host !== environment.webUrl) {
        this.logger.warn('generateQRCode', 'Rejected QR code for external URL');
        this.toaster.error(this.translate.instant('QR_CODE_INVALID_URL'));
        return;
      }

      this.isGenerating = true;

      const qrCodeElement = this.qrCodeContainer.nativeElement;
      const isMobile = window.innerWidth < 640;
      while (qrCodeElement.firstChild) {
        qrCodeElement.removeChild(qrCodeElement.firstChild);
      }

      const canvas = document.createElement('canvas');
      await QRCode.toCanvas(canvas, this.sessionUrl, {
        width: isMobile ? 250 : 300,
        margin: 2,
        errorCorrectionLevel: 'L',
        color: {
          dark: '#000000',
          light: '#FFFFFF',
        },
      });

      qrCodeElement.appendChild(canvas);
      this.logger.info('generateQRCode', 'QR code generated successfully');
    } catch (error) {
      this.logger.error('generateQRCode', 'Failed to generate QR code:', error);
      this.toaster.error(this.translate.instant('QR_CODE_GENERATION_FAILED'));
    } finally {
      this.isGenerating = false;
    }
  }
}
