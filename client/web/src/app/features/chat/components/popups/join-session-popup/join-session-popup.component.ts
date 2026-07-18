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
import { FormsModule } from '@angular/forms';
import { TranslateModule } from '@ngx-translate/core';
import { DeviceDetectorService } from 'ngx-device-detector';
import { environment } from '../../../../../../environments/environment';

type JsQrFn = typeof import('jsqr').default;

@Component({
  selector: 'app-join-session-popup',
  imports: [CommonModule, FormsModule, TranslateModule],
  templateUrl: './join-session-popup.component.html',
  styleUrl: './join-session-popup.component.css',
})
export class JoinSessionPopupComponent implements OnChanges, OnDestroy {
  @Input() isOpen = false;
  @Input() sessionCode = '';

  @Output() sessionCodeChange = new EventEmitter<string>();
  @Output() closed = new EventEmitter<void>();
  @Output() submitted = new EventEmitter<void>();

  @ViewChild('videoEl') videoEl!: ElementRef<HTMLVideoElement>;
  @ViewChild('canvasEl') canvasEl!: ElementRef<HTMLCanvasElement>;

  private deviceDetector = inject(DeviceDetectorService);
  private ngZone = inject(NgZone);
  private cdr = inject(ChangeDetectorRef);

  isScannerOpen = false;
  scannerError = '';

  private stream: MediaStream | null = null;
  private rafId: number | null = null;
  private startCameraTimeout: ReturnType<typeof setTimeout> | null = null;
  private scannerErrorTimeout: ReturnType<typeof setTimeout> | null = null;
  private jsQR: JsQrFn | null = null;

  ngOnChanges(changes: SimpleChanges): void {
    if (changes['isOpen']?.currentValue === false && this.isScannerOpen) {
      this.closeScanner();
    }
  }

  get isMobile(): boolean {
    return !this.deviceDetector.isDesktop();
  }

  openScanner(): void {
    this.scannerError = '';
    this.isScannerOpen = true;

    // Pre-load jsQR once so the per-frame scan loop doesn't pay
    // dynamic-import overhead on every requestAnimationFrame tick.
    if (!this.jsQR) {
      void import('jsqr')
        .then((m) => {
          this.jsQR = m.default;
        })
        .catch(() => {
          this.ngZone.run(() => {
            this.scannerError = 'CAMERA_NOT_AVAILABLE';
            this.closeScanner();
          });
        });
    }

    // Give the DOM a tick to render the <video> element before binding the stream.
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
    try {
      this.stream = await navigator.mediaDevices.getUserMedia({
        video: { facingMode: 'environment' },
      });
      if (!this.isScannerOpen) {
        // User closed the scanner while permission prompt was up.
        this.stopCamera();
        return;
      }
      const video = this.videoEl.nativeElement;
      video.srcObject = this.stream;
      await video.play();
      this.ngZone.runOutsideAngular(() => this.scanFrame());
    } catch {
      this.ngZone.run(() => {
        this.scannerError = 'CAMERA_NOT_AVAILABLE';
      });
    }
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
      const code = this.extractSessionCode(result.data);
      if (code === null) {
        this.ngZone.run(() => {
          this.scannerError = 'QR_CODE_INVALID_URL';
        });
        if (this.scannerErrorTimeout) clearTimeout(this.scannerErrorTimeout);
        this.scannerErrorTimeout = setTimeout(() => {
          this.scannerError = '';
          this.scannerErrorTimeout = null;
          this.cdr.detectChanges();
          // Resume scanning only after the error clears.
          this.rafId = requestAnimationFrame(() => this.scanFrame());
        }, 3000);
        return;
      }
      this.ngZone.run(() => {
        // Best-effort haptic feedback (Android Chrome supports it; iOS Safari ignores).
        try {
          navigator.vibrate?.(50);
        } catch {
          /* ignore */
        }
        this.sessionCodeChange.emit(code);
        this.closeScanner();
        setTimeout(() => this.submitted.emit(), 0);
      });
      return;
    }

    this.rafId = requestAnimationFrame(() => this.scanFrame());
  }

  private extractSessionCode(payload: string): string | null {
    try {
      const url = new URL(payload);
      if (url.host !== environment.webUrl) {
        return null;
      }
      const parts = url.pathname.split('/').filter(Boolean);
      if (parts.length === 2 && parts[0] === 'private' && parts[1]) {
        return parts[1];
      }
    } catch {
      // not a URL — cannot be a valid PastePoint QR code
    }
    return null;
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
