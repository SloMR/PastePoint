import {
  ChangeDetectorRef,
  Component,
  ElementRef,
  EventEmitter,
  Input,
  NgZone,
  OnChanges,
  OnDestroy,
  Output,
  SimpleChanges,
  ViewChild,
  inject,
} from '@angular/core';
import { CommonModule } from '@angular/common';
import { TranslateModule } from '@ngx-translate/core';
import { NGXLogger } from 'ngx-logger';
import { extractSessionCodeFromUrl } from '../../../../../utils/session-link.util';
import { reloadOnceForChunkError } from '../../../../../utils/chunk-reload';

type JsQrFn = typeof import('jsqr').default;

@Component({
  selector: 'app-qr-scanner-popup',
  imports: [CommonModule, TranslateModule],
  templateUrl: './qr-scanner-popup.component.html',
  styleUrl: './qr-scanner-popup.component.css',
})
export class QrScannerPopupComponent implements OnChanges, OnDestroy {
  @Input() isOpen = false;

  @Output() closed = new EventEmitter<void>();
  @Output() scanned = new EventEmitter<string>();

  @ViewChild('videoEl') videoEl!: ElementRef<HTMLVideoElement>;
  @ViewChild('canvasEl') canvasEl!: ElementRef<HTMLCanvasElement>;

  private ngZone = inject(NgZone);
  private cdr = inject(ChangeDetectorRef);
  private logger = inject(NGXLogger);

  isScannerOpen = false;
  scannerError = '';

  private stream: MediaStream | null = null;
  private rafId: number | null = null;
  private startCameraTimeout: ReturnType<typeof setTimeout> | null = null;
  private scannerErrorTimeout: ReturnType<typeof setTimeout> | null = null;
  private jsQR: JsQrFn | null = null;

  ngOnChanges(changes: SimpleChanges): void {
    const open = changes['isOpen'];
    if (!open) return;

    if (open.currentValue) {
      void this.openScanner();
    } else if (this.isScannerOpen) {
      this.closeScanner();
    }
  }

  openScanner(): void {
    this.scannerError = '';
    this.isScannerOpen = true;

    if (!this.jsQR) {
      void import('jsqr')
        .then((m) => {
          this.jsQR = m.default;
        })
        .catch((err: unknown) => {
          if (reloadOnceForChunkError(err)) {
            return;
          }

          this.ngZone.run(() => {
            this.scannerError = 'CAMERA_NOT_AVAILABLE';
            this.closeScanner();
          });
        });
    }

    if (this.startCameraTimeout) clearTimeout(this.startCameraTimeout);
    this.startCameraTimeout = setTimeout(() => {
      this.startCameraTimeout = null;

      if (this.isScannerOpen) {
        void this.startCamera();
      }
    }, 50);
  }

  closeScanner(): void {
    this.isScannerOpen = false;

    if (this.startCameraTimeout) {
      clearTimeout(this.startCameraTimeout);
      this.startCameraTimeout = null;
    }

    if (this.scannerErrorTimeout) {
      clearTimeout(this.scannerErrorTimeout);
      this.scannerErrorTimeout = null;
    }

    this.scannerError = '';
    this.stopCamera();
  }

  private async startCamera(): Promise<void> {
    if (!navigator.mediaDevices?.getUserMedia) {
      this.logger.error('Camera unavailable: getUserMedia missing (insecure origin?)');
      this.failCamera();
      return;
    }

    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
      });

      if (!this.isScannerOpen) {
        this.stopCamera();
        return;
      }

      const video = this.videoEl.nativeElement;
      video.srcObject = this.stream;
      await video.play();

      this.ngZone.runOutsideAngular(() => this.scanFrame());
    } catch (err) {
      this.logger.error(
        `Camera unavailable: ${err instanceof Error ? err.name : 'UnknownError'}`,
        err
      );
      this.failCamera();
    }
  }

  private failCamera(): void {
    this.ngZone.run(() => {
      this.scannerError = 'CAMERA_NOT_AVAILABLE';
    });
  }

  private scanFrame(): void {
    if (!this.isScannerOpen) return;

    const video = this.videoEl?.nativeElement;
    const canvas = this.canvasEl?.nativeElement;

    if (!video || !canvas || video.readyState < 2) {
      this.rafId = requestAnimationFrame(() => this.scanFrame());
      return;
    }

    canvas.width = video.videoWidth;
    canvas.height = video.videoHeight;

    const ctx = canvas.getContext('2d');
    if (!ctx) {
      this.ngZone.run(() => this.closeScanner());
      return;
    }

    ctx.drawImage(video, 0, 0, canvas.width, canvas.height);
    const imageData = ctx.getImageData(0, 0, canvas.width, canvas.height);

    if (!this.jsQR) {
      // Library not loaded yet — keep polling on next frame.
      this.rafId = requestAnimationFrame(() => this.scanFrame());
      return;
    }

    const result = this.jsQR(imageData.data, imageData.width, imageData.height);
    if (result?.data && this.isScannerOpen) {
      const code = extractSessionCodeFromUrl(result.data);

      if (code === null) {
        this.ngZone.run(() => {
          this.scannerError = 'QR_CODE_INVALID_URL';
        });

        if (this.scannerErrorTimeout) clearTimeout(this.scannerErrorTimeout);
        this.scannerErrorTimeout = setTimeout(() => {
          this.scannerError = '';
          this.scannerErrorTimeout = null;
          this.cdr.detectChanges();

          this.rafId = requestAnimationFrame(() => this.scanFrame());
        }, 3000);
        return;
      }
      this.ngZone.run(() => {
        try {
          navigator.vibrate?.(50);
        } catch {
          /* ignore */
        }
        this.closeScanner();
        setTimeout(() => this.scanned.emit(code), 0);
      });
      return;
    }

    this.rafId = requestAnimationFrame(() => this.scanFrame());
  }

  private stopCamera(): void {
    if (this.rafId !== null) {
      cancelAnimationFrame(this.rafId);
      this.rafId = null;
    }

    if (this.stream) {
      this.stream.getTracks().forEach((t) => t.stop());
      this.stream = null;
    }
  }

  ngOnDestroy(): void {
    this.isScannerOpen = false;
    if (this.startCameraTimeout) {
      clearTimeout(this.startCameraTimeout);
      this.startCameraTimeout = null;
    }

    if (this.scannerErrorTimeout) {
      clearTimeout(this.scannerErrorTimeout);
      this.scannerErrorTimeout = null;
    }

    this.stopCamera();
  }
}
