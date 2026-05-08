import { Injectable, inject } from '@angular/core';
import * as Sentry from '@sentry/angular';
import {
  FILE_TRANSFER_MESSAGE_TYPES,
  FileDownload,
  PREVIEW_MIME_TYPE,
} from '../../../utils/constants';
import { FileTransferBaseService } from './file-transfer-base.service';
import { PreviewService } from '../../services/ui/preview.service';
import {
  createStreamingHash,
  updateStreamingHash,
  finalizeStreamingHash,
  IHasher,
} from '../../../utils/chunk-protocol';

@Injectable({
  providedIn: 'root',
})
export class FileDownloadService extends FileTransferBaseService {
  private previewService = inject(PreviewService);

  private activeReceiveSpans = new Map<string, Sentry.Span>();

  // =============== Constructor ===============
  constructor() {
    super();
  }

  private receiveSpanKey(fromUser: string, fileId: string): string {
    return `${fromUser}:${fileId}`;
  }

  private startReceiveSpan(fromUser: string, fileId: string, fileSize: number): void {
    const key = this.receiveSpanKey(fromUser, fileId);
    if (this.activeReceiveSpans.has(key)) return;
    const span = Sentry.startInactiveSpan({
      name: 'file.transfer.receive',
      op: 'file.transfer.receive',
    });
    span.setAttribute('file_size_bytes', fileSize);
    this.activeReceiveSpans.set(key, span);
  }

  private finishReceiveSpan(
    fromUser: string,
    fileId: string,
    outcome: 'completed' | 'crc_failed' | 'missing_chunks' | 'hash_mismatch' | 'cancelled',
    extra?: Record<string, number | string | boolean>
  ): void {
    const key = this.receiveSpanKey(fromUser, fileId);
    const span = this.activeReceiveSpans.get(key);
    if (!span) return;
    span.setAttribute('outcome', outcome);
    if (extra) {
      for (const [k, v] of Object.entries(extra)) {
        span.setAttribute(k, v);
      }
    }
    span.setStatus(
      outcome === 'completed' ? { code: 1, message: 'ok' } : { code: 2, message: outcome }
    );
    span.end();
    this.activeReceiveSpans.delete(key);
  }

  // =============== Data Handling Methods ===============
  /**
   * Handles incoming file data chunks and assembles the file.
   * Uses chunk index for ordered assembly, preventing corruption from out-of-order delivery.
   * Validates chunk integrity via CRC32 checksum.
   */
  public async handleDataChunk(
    fileId: string,
    chunk: ArrayBuffer,
    fromUser: string,
    chunkIndex: number,
    totalChunks: number,
    isValid: boolean = true
  ): Promise<void> {
    const userMap = await this.getIncomingFileTransfers(fromUser);
    if (!userMap) {
      this.logger.warn(
        'handleDataChunk',
        `Discarding chunk - no incomingFileTransfers map for ${fromUser}`
      );
      return;
    }

    const fileDownload = userMap.get(fileId);
    if (!fileDownload) {
      this.logger.error(
        'handleDataChunk',
        `Chunk ${chunkIndex}/${totalChunks} - fileId ${fileId.substring(0, 8)}... NOT FOUND in map`
      );
      return;
    }

    if (!fileDownload.isAccepted) {
      this.logger.error(
        'handleDataChunk',
        `Chunk ${chunkIndex}/${totalChunks} - fileId ${fileId.substring(0, 8)}... NOT YET ACCEPTED`
      );
      return;
    }

    // Verify chunk integrity (CRC32 checksum)
    if (!isValid) {
      this.logger.error(
        'handleDataChunk',
        `Chunk ${chunkIndex} for ${fileId} failed CRC32 validation - data corrupted!`
      );
      this.toaster.error(
        this.translate.instant('CHUNK_INTEGRITY_ERROR', {
          chunkIndex: chunkIndex + 1,
          totalChunks,
        })
      );
      this.finishReceiveSpan(fromUser, fileId, 'crc_failed', {
        chunk_index: chunkIndex,
        total_chunks: totalChunks,
        bytes_received: fileDownload.receivedSize,
      });
      return;
    }

    // Initialize totalChunks
    if (fileDownload.totalChunks === 0) {
      fileDownload.totalChunks = totalChunks;
      this.startReceiveSpan(fromUser, fileId, fileDownload.fileSize);
    }

    // Check for duplicate chunk
    if (fileDownload.receivedChunks.has(chunkIndex)) {
      this.logger.warn('handleDataChunk', `Duplicate chunk ${chunkIndex} for ${fileId}, ignoring`);
      return;
    }

    // Store chunk as Blob
    fileDownload.receivedChunks.set(chunkIndex, new Blob([chunk]));
    fileDownload.receivedSize += chunk.byteLength;

    const progress = (fileDownload.receivedChunks.size / totalChunks) * 100;
    fileDownload.progress = parseFloat(progress.toFixed(2));

    // Log first chunk processed
    if (chunkIndex === 0) {
      this.logger.info(
        'handleDataChunk',
        `First chunk processed for ${fileId.substring(0, 8)}... (${chunk.byteLength} bytes)`
      );
    }

    await this.updateActiveDownloads();

    // Check if all chunks received
    if (fileDownload.receivedChunks.size >= totalChunks) {
      this.logger.info('handleDataChunk', `All chunks received for fileId=${fileId}`);
      await this.assembleAndDownloadFile(fileDownload, userMap, fromUser);
    } else {
      this.logger.error(
        'handleDataChunk',
        `File ${fileId.substring(0, 8)}... not fully received: ${fileDownload.receivedChunks.size}/${totalChunks} chunks`
      );
    }
  }

  /**
   * Assembles chunks in order, verifies file integrity, and triggers download.
   * Uses Blob-based assembly and streaming hash to minimize memory usage.
   */
  private async assembleAndDownloadFile(
    fileDownload: FileDownload,
    userMap: Map<string, FileDownload>,
    fromUser: string
  ): Promise<void> {
    // Collect chunks in order as Blobs
    const orderedChunks: Blob[] = [];
    let missingChunks = 0;

    for (let i = 0; i < fileDownload.totalChunks; i++) {
      const chunk = fileDownload.receivedChunks.get(i);
      if (chunk) {
        orderedChunks.push(chunk as Blob);
      } else {
        this.logger.error(
          'assembleAndDownloadFile',
          `Missing chunk ${i} for ${fileDownload.fileId}`
        );
        missingChunks++;
      }
    }

    // Clear the map immediately to free memory
    fileDownload.receivedChunks.clear();

    if (missingChunks > 0) {
      this.logger.error(
        'assembleAndDownloadFile',
        `${missingChunks} chunks missing, aborting download`
      );
      this.toaster.error(this.translate.instant('FILE_INCOMPLETE_ERROR', { count: missingChunks }));
      orderedChunks.length = 0; // Clear to free memory
      this.finishReceiveSpan(fromUser, fileDownload.fileId, 'missing_chunks', {
        missing_chunks: missingChunks,
        total_chunks: fileDownload.totalChunks,
      });
      await this.cleanupAfterDownload(fileDownload.fromUser, fileDownload.fileId);
      return;
    }

    const lowerName = (fileDownload.fileName || '').toLowerCase();
    const ext = lowerName.split('.').pop() || '';
    let blobType = '';
    if (ext === 'pdf') {
      blobType = 'application/pdf';
    } else if (['png', 'jpg', 'jpeg', 'gif', 'webp', 'bmp', 'svg'].includes(ext)) {
      blobType = ext === 'svg' ? 'image/svg+xml' : `image/${ext === 'jpg' ? 'jpeg' : ext}`;
    }

    // Verify file integrity via streaming SHA-256 hash (memory efficient!)
    // Hashes chunk-by-chunk without loading entire file into memory
    if (fileDownload.expectedHash) {
      try {
        const hasher = await createStreamingHash();
        for (const chunkBlob of orderedChunks) {
          const chunkBuffer = await chunkBlob.arrayBuffer();
          updateStreamingHash(hasher as IHasher, new Uint8Array(chunkBuffer));
        }
        const actualHash = finalizeStreamingHash(hasher as IHasher);

        if (actualHash !== fileDownload.expectedHash) {
          this.logger.error('assembleAndDownloadFile', `Hash mismatch for ${fileDownload.fileId}!`);
          this.toaster.error(this.translate.instant('CHUNK_INTEGRITY_ERROR'));
          orderedChunks.length = 0; // Clear to free memory
          this.finishReceiveSpan(fromUser, fileDownload.fileId, 'hash_mismatch');
          await this.cleanupAfterDownload(fileDownload.fromUser, fileDownload.fileId);
          return; // Abort - don't download corrupted file
        }
        this.logger.info(
          'assembleAndDownloadFile',
          `File integrity verified for ${fileDownload.fileId} ✓`
        );
      } catch (e) {
        this.logger.warn(
          'assembleAndDownloadFile',
          `Failed to verify file hash: ${e instanceof Error ? e.message : String(e)}`,
          e
        );
      }
    }

    // Create final Blob directly from chunk Blobs
    const receivedBlob = new Blob(orderedChunks, { type: blobType || undefined });
    const downloadUrl = URL.createObjectURL(receivedBlob);
    const timestamp = new Date().toISOString().split('T')[0];
    const fileName = this.sanitizeFileName(fileDownload.fileName) || `downloaded_file_${timestamp}`;

    // Clear the orderedChunks array to help GC
    orderedChunks.length = 0;

    this.logger.info(
      'assembleAndDownloadFile',
      `File assembled: ${fileName} (${(receivedBlob.size / 1024 / 1024).toFixed(2)}MB)`
    );

    // Update preview after completion (only for small files to avoid memory issues)
    try {
      if (blobType === 'application/pdf') {
        if (!fileDownload.previewDataUrl) {
          const buffer = await receivedBlob.arrayBuffer();
          const thumb = await this.previewService.createPdfThumbnailFromBytes(
            new Uint8Array(buffer)
          );
          if (thumb) {
            fileDownload.previewDataUrl = thumb;
            fileDownload.previewMime = PREVIEW_MIME_TYPE;
          }
        } else {
          fileDownload.previewMime = PREVIEW_MIME_TYPE;
        }
      } else if (blobType.startsWith('image/')) {
        fileDownload.previewMime = blobType;
        fileDownload.previewDataUrl = downloadUrl;
      }
      await this.updateActiveDownloads();
      await this.updateIncomingFileOffers();
    } catch {
      this.logger.warn(
        'assembleAndDownloadFile',
        `Failed to generate preview for ${fileDownload.fileId}`
      );
    }

    // Trigger download
    const anchor = document.createElement('a');
    anchor.href = downloadUrl;
    anchor.download = fileName;
    document.body.appendChild(anchor);
    anchor.click();
    document.body.removeChild(anchor);

    // Revoke the object URL after a short delay to allow download to start
    setTimeout(() => URL.revokeObjectURL(downloadUrl), 1000);

    this.toaster.success(this.translate.instant('FILE_DOWNLOAD_COMPLETED', { fileName }));

    this.finishReceiveSpan(fromUser, fileDownload.fileId, 'completed');

    // Cleanup
    userMap.delete(fileDownload.fileId);
    if (userMap.size === 0) {
      await this.deleteIncomingFileTransfers(fromUser);
    }

    await this.updateActiveDownloads();
  }

  // =============== Helper Methods ===============
  /**
   * Cleans up after a failed download (missing chunks or integrity error)
   */
  private async cleanupAfterDownload(fromUser: string, fileId: string): Promise<void> {
    const userMap = await this.getIncomingFileTransfers(fromUser);
    if (userMap) {
      userMap.delete(fileId);
      if (userMap.size === 0) {
        await this.deleteIncomingFileTransfers(fromUser);
      }
    }
    await this.updateActiveDownloads();
    await this.updateIncomingFileOffers();
  }

  // =============== Cancellation Methods ===============
  /**
   * Cancels an active file download and notifies the sender
   */
  public async cancelFileDownload(fromUser: string, fileId: string): Promise<void> {
    const userMap = await this.getIncomingFileTransfers(fromUser);
    if (userMap?.has(fileId)) {
      this.finishReceiveSpan(fromUser, fileId, 'cancelled', { cancelled_by: 'receiver' });
      userMap.delete(fileId);
      const key = this.getOrCreateStatusKey(fromUser, fileId);
      await this.deleteFileTransferStatus(key);
      await this.updateActiveDownloads();

      const message = {
        type: FILE_TRANSFER_MESSAGE_TYPES.FILE_CANCEL_DOWNLOAD,
        payload: {
          fileId: fileId,
        },
      };
      this.sendData(message, fromUser);
      this.logger.info('cancelDownload', `Cancel download fromUser=${fromUser}, fileId=${fileId}`);
    }
  }

  /**
   * Handles file upload cancellation from the sender
   */
  public async handleFileUploadCancellation(fromUser: string, fileId: string): Promise<void> {
    this.logger.debug(
      'handleFileUploadCancellation',
      `File upload from ${fromUser} (fileId=${fileId}) was cancelled`
    );

    this.finishReceiveSpan(fromUser, fileId, 'cancelled', { cancelled_by: 'sender' });

    const userMap = await this.getIncomingFileTransfers(fromUser);
    if (userMap) {
      userMap.delete(fileId);
      if (userMap.size === 0) {
        await this.deleteIncomingFileTransfers(fromUser);
      }
    }

    await this.updateIncomingFileOffers();
    await this.updateActiveDownloads();

    this.toaster.info(this.translate.instant('FILE_UPLOAD_CANCELLED'));
  }
}
