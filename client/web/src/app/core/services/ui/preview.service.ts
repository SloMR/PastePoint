import { Injectable, PLATFORM_ID, inject } from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import {
  MAX_PREVIEW_DATA_URL_SIZE,
  PREVIEW_MIME_TYPE,
  PREVIEW_QUALITY,
} from '../../../utils/constants';

@Injectable({
  providedIn: 'root',
})
export class PreviewService {
  private platformId = inject(PLATFORM_ID);

  private pdfJsLoaded = false;
  private pdfjsLib: any | null = null;

  private static readonly PDFJS_CDN_BASE = 'https://cdnjs.cloudflare.com/ajax/libs/pdf.js/5.4.149';
  private static readonly PDFJS_LIB_URL = `${PreviewService.PDFJS_CDN_BASE}/pdf.min.mjs`;
  private static readonly PDFJS_WORKER_URL = `${PreviewService.PDFJS_CDN_BASE}/pdf.worker.min.mjs`;

  private async ensurePdfJsLoaded(): Promise<void> {
    if (this.pdfJsLoaded) return;
    if (!isPlatformBrowser(this.platformId)) {
      return;
    }

    try {
      const pdfjsLib = await import(
        /* @vite-ignore */ /* webpackIgnore: true */
        PreviewService.PDFJS_LIB_URL
      );

      if (pdfjsLib?.GlobalWorkerOptions) {
        pdfjsLib.GlobalWorkerOptions.workerSrc = PreviewService.PDFJS_WORKER_URL;
      }

      this.pdfjsLib = pdfjsLib;
      this.pdfJsLoaded = true;
    } catch (e) {
      throw new Error(`Failed to load pdf.js from CDN: ${(e as Error)?.message || e}`, {
        cause: e,
      });
    }
  }

  /**
   * Creates a thumbnail from an image file.
   * Uses createObjectURL instead of readAsDataURL to avoid loading entire file into memory.
   */
  public async createImageThumbnail(
    file: File,
    maxWidth: number = 320,
    maxHeight: number = 192
  ): Promise<{ dataUrl: string; mime: string }> {
    return new Promise<{ dataUrl: string; mime: string }>((resolve, reject) => {
      // Use createObjectURL - more memory efficient than readAsDataURL
      // It creates a reference to the file, not a copy
      const objectUrl = URL.createObjectURL(file);

      const img = new Image();
      img.onload = () => {
        // Revoke the object URL immediately after loading - free memory
        URL.revokeObjectURL(objectUrl);

        let { width, height } = img;
        const ratio = Math.min(maxWidth / width, maxHeight / height, 1);
        width = Math.floor(width * ratio);
        height = Math.floor(height * ratio);

        const canvas = document.createElement('canvas');
        canvas.width = width;
        canvas.height = height;

        const ctx = canvas.getContext('2d');
        if (!ctx) {
          reject(new Error('Canvas context not available'));
          return;
        }

        ctx.drawImage(img, 0, 0, width, height);

        const png = canvas.toDataURL('image/png');
        const result =
          png.length > MAX_PREVIEW_DATA_URL_SIZE
            ? {
                dataUrl: canvas.toDataURL(PREVIEW_MIME_TYPE, PREVIEW_QUALITY),
                mime: PREVIEW_MIME_TYPE,
              }
            : { dataUrl: png, mime: 'image/png' };

        // Clear canvas to help garbage collection
        canvas.width = 0;
        canvas.height = 0;

        resolve(result);
      };
      img.onerror = () => {
        URL.revokeObjectURL(objectUrl);
        reject(new Error('Image load failed'));
      };
      img.src = objectUrl;
    });
  }

  // Skip PDF preview for files larger than this (too memory intensive)
  private static readonly MAX_PDF_SIZE_FOR_PREVIEW = 100 * 1024 * 1024; // 100MB

  /**
   * Creates a thumbnail from a PDF file.
   * Skips large PDFs to avoid memory spikes.
   */
  public async createPdfThumbnailFromFile(
    file: File,
    maxWidth: number = 320
  ): Promise<string | undefined> {
    // Skip large PDFs to avoid memory spikes
    if (file.size > PreviewService.MAX_PDF_SIZE_FOR_PREVIEW) {
      return undefined;
    }

    try {
      await this.ensurePdfJsLoaded();
      const buffer = await file.arrayBuffer();
      const result = await this.createPdfThumbnailFromBytes(new Uint8Array(buffer), maxWidth);
      // buffer will be garbage collected
      return result;
    } catch {
      return undefined;
    }
  }

  /**
   * Creates a thumbnail from PDF bytes.
   * Properly cleans up PDF.js resources after rendering.
   * Uses JPEG format with quality setting to keep file size small for WebRTC transfer.
   */
  public async createPdfThumbnailFromBytes(
    data: Uint8Array,
    maxWidth: number = 320
  ): Promise<string | undefined> {
    let pdf: any = null;
    let page: any = null;

    try {
      await this.ensurePdfJsLoaded();
      if (!this.pdfjsLib) return undefined;

      const loadingTask = this.pdfjsLib.getDocument({ data });
      pdf = await loadingTask.promise;
      page = await pdf.getPage(1);

      const viewport = page.getViewport({ scale: 1 });
      const ratio = Math.min(maxWidth / viewport.width, 1);
      const scaled = page.getViewport({ scale: ratio });

      const canvas = document.createElement('canvas');
      canvas.width = Math.ceil(scaled.width);
      canvas.height = Math.ceil(scaled.height);

      const ctx = canvas.getContext('2d');
      if (!ctx) return undefined;

      ctx.fillStyle = '#FFFFFF';
      ctx.fillRect(0, 0, canvas.width, canvas.height);

      await page.render({ canvasContext: ctx, viewport: scaled }).promise;

      // Use JPEG with 0.7 quality for much smaller file sizes
      const dataUrl = canvas.toDataURL(PREVIEW_MIME_TYPE, PREVIEW_QUALITY);

      // Clear canvas to help garbage collection
      canvas.width = 0;
      canvas.height = 0;

      return dataUrl;
    } catch {
      return undefined;
    } finally {
      // Clean up PDF.js resources to free memory
      if (page) {
        page.cleanup();
      }
      if (pdf) {
        await pdf.destroy();
      }
    }
  }
}
