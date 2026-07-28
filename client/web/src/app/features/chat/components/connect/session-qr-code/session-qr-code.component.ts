import {
  AfterViewInit,
  ChangeDetectionStrategy,
  ChangeDetectorRef,
  Component,
  ElementRef,
  Input,
  OnChanges,
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

/** Renders an invite URL as a QR canvas. Refuses any URL outside our own host. */
@Component({
  selector: 'app-session-qr-code',
  imports: [CommonModule, TranslateModule],
  templateUrl: './session-qr-code.component.html',
  styleUrl: './session-qr-code.component.css',
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class SessionQrCodeComponent implements AfterViewInit, OnChanges {
  @Input() sessionUrl = '';
  @Input() size = 180;

  @ViewChild('qrContainer') qrContainer?: ElementRef<HTMLDivElement>;

  private platformId = inject(PLATFORM_ID);
  private toaster = inject(HotToastService);
  private translate = inject(TranslateService);
  private logger = inject(NGXLogger);
  private cdr = inject(ChangeDetectorRef);

  ngAfterViewInit(): void {
    this.scheduleRender();
  }

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['sessionUrl'] && !changes['sessionUrl'].firstChange) this.scheduleRender();
  }

  private scheduleRender(): void {
    if (!isPlatformBrowser(this.platformId)) return;
    requestAnimationFrame(() => void this.render());
  }

  private async render(): Promise<void> {
    if (!this.sessionUrl || !this.qrContainer) return;

    try {
      if (new URL(this.sessionUrl).host !== environment.webUrl) {
        this.logger.warn('SessionQrCode', 'Rejected QR code for external URL');
        return;
      }

      const host = this.qrContainer.nativeElement;
      while (host.firstChild) host.removeChild(host.firstChild);

      const canvas = document.createElement('canvas');
      await QRCode.toCanvas(canvas, this.sessionUrl, {
        width: this.size,
        margin: 2,
        errorCorrectionLevel: 'L',
        color: { dark: '#000000', light: '#FFFFFF' },
      });
      host.appendChild(canvas);
      this.cdr.markForCheck();
    } catch (error) {
      this.logger.error('SessionQrCode', 'Failed to generate QR code:', error);
      this.toaster.error(this.translate.instant('QR_CODE_GENERATION_FAILED'));
    }
  }
}
