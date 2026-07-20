import { Injectable, inject } from '@angular/core';
import { Subject } from 'rxjs';
import * as Sentry from '@sentry/angular';
import { startNewTrace } from '@sentry/core';
import {
  FileUpload,
  CHUNK_SIZE,
  MAX_BUFFERED_AMOUNT,
  MB,
  FILE_TRANSFER_MESSAGE_TYPES,
  FileTransferStatus,
  MAX_PREVIEW_DATA_URL_SIZE,
  PREVIEW_MIME_TYPE,
} from '../../../utils/constants';
import { FileTransferBaseService } from './file-transfer-base.service';
import { PreviewService } from '../../services/ui/preview.service';
import {
  encodeChunk,
  calculateTotalChunks,
  calculateFileHashStreaming,
} from '../../../utils/chunk-protocol';
import { UserService } from '../user-management/user.service';

@Injectable({
  providedIn: 'root',
})
export class FileUploadService extends FileTransferBaseService {
  private previewService = inject(PreviewService);
  private userService = inject(UserService);

  // =============== Private Properties ===============
  private processingQueues = new Map<string, boolean>();
  private userFileQueues = new Map<string, string[]>(); // Queue of fileIds per user for sequential transfer
  private activeFilePerUser = new Map<string, string | null>(); // Currently transferring file per user
  private consecutiveErrorCounts = new Map<string, number>();
  private maxConsecutiveErrors = 5;
  private offerReady = new Map<string, Promise<void>>();
  private fileHashCache = new WeakMap<File, Promise<string>>();

  // Outgoing group aggregation: one logical send (a file fanned out to N peers)
  // so the sender's echo bubble can show "Sent / Sent to X of N / Not delivered".
  private outgoingGroups = new Map<string, { total: number; completed: number; failed: number }>();
  public outgoingGroupStatus$ = new Subject<{
    groupId: string;
    delivered: number;
    total: number;
    resolved: boolean;
  }>();

  // =============== Constructor ===============
  constructor() {
    super();
  }

  // =============== Public File Management Methods ===============
  /**
   * Pre-computes a file's hash so it's ready by the time the user hits send.
   * Call when a file is staged; the result is memoized per File.
   */
  public prewarmFileHash(file: File): Promise<string> {
    let hashPromise = this.fileHashCache.get(file);
    if (!hashPromise) {
      hashPromise = calculateFileHashStreaming(file);
      this.fileHashCache.set(file, hashPromise);
    }
    return hashPromise;
  }

  /**
   * Prepares a file for sending by creating necessary transfer metadata
   */
  public async prepareFileForSending(
    file: File,
    targetUser: string,
    groupId: string
  ): Promise<void> {
    if (file.size === 0) {
      this.logger.warn('prepareFileForSending', `Skipping empty file ${file.name}`);
      this.toaster.error(this.translate.instant('FILE_EMPTY_ERROR', { fileName: file.name }));
      return;
    }

    let userMap = await this.getFileTransfers(targetUser);
    if (!userMap) {
      userMap = new Map<string, FileUpload>();
      await this.setFileTransfers(targetUser, userMap);
    }

    const fileId = this.generateFileId();
    const fileTransfer: FileUpload = {
      fileId,
      file,
      currentOffset: 0,
      isPaused: false,
      targetUser,
      progress: 0,
      phase: 'sending',
      groupId,
    };

    userMap.set(fileId, fileTransfer);
    await this.setFileTransfers(targetUser, userMap);
    await this.updateActiveUploads();
  }

  /**
   * Sends all file offers to a target user
   */
  public async sendAllFileOffers(targetUser: string): Promise<void> {
    const userMap = await this.getFileTransfers(targetUser);
    if (!userMap) {
      this.logger.error('sendAllFileOffers', `No file transfers found for user: ${targetUser}`);
      return;
    }

    this.logger.debug('sendAllFileOffers', `Found ${userMap.size} files to send to ${targetUser}`);
    for (const fileTransfer of userMap.values()) {
      const key = this.getOrCreateStatusKey(targetUser, fileTransfer.fileId);
      const status = await this.getFileTransferStatus(key);
      if (!status || status === FileTransferStatus.PENDING) {
        await this.sendFileOffer(fileTransfer.fileId, targetUser);
      } else {
        this.logger.info(
          'sendAllFileOffers',
          `FileId=${fileTransfer.fileId} already sent or completed. Skipping.`
        );
      }
    }
  }

  /**
   * Starts sending a file after an offer has been accepted.
   * Files are queued and sent sequentially to prevent chunk interleaving.
   */
  public async startSendingFile(targetUser: string, fileId: string): Promise<void> {
    this.logger.info(
      'startSendingFile',
      `File send started: ${fileId.substring(0, 8)}... to ${targetUser}`
    );

    const transferId = this.getOrCreateStatusKey(targetUser, fileId);
    await this.setFileTransferStatus(transferId, FileTransferStatus.ACCEPTED);

    const userMap = await this.getFileTransfers(targetUser);
    if (!userMap) {
      this.logger.error('startSendingFile', `No fileTransfers map for user: ${targetUser}`);
      return;
    }

    const fileTransfer = userMap.get(fileId);
    if (!fileTransfer) {
      this.logger.error('startSendingFile', `No fileId=${fileId} for ${targetUser}`);
      this.toaster.error(this.translate.instant('NO_FILE_TO_SEND'));
      return;
    }

    const offerKey = this.getOrCreateStatusKey(targetUser, fileId);
    await this.offerReady.get(offerKey);
    this.offerReady.delete(offerKey);

    fileTransfer.phase = 'sending';
    await this.setFileTransfers(targetUser, userMap);

    // Add to queue for sequential processing
    this.enqueueFileForUser(targetUser, fileId);
    const queueLength = this.userFileQueues.get(targetUser)?.length ?? 0;
    this.logger.info(
      'startSendingFile',
      `Queued ${fileId.substring(0, 8)}... for ${targetUser} (queue size: ${queueLength})`
    );

    // Try to start processing if no file is currently being sent
    await this.processNextFileInQueue(targetUser);
  }

  /**
   * Adds a file to the user's transfer queue
   */
  private enqueueFileForUser(targetUser: string, fileId: string): void {
    if (!this.userFileQueues.has(targetUser)) {
      this.userFileQueues.set(targetUser, []);
    }
    const queue = this.userFileQueues.get(targetUser)!;
    if (!queue.includes(fileId)) {
      queue.push(fileId);
    }
  }

  /**
   * Processes the next file in the user's queue if no transfer is active
   */
  private async processNextFileInQueue(targetUser: string): Promise<void> {
    // Check if already processing a file for this user
    const activeFile = this.activeFilePerUser.get(targetUser);
    if (activeFile) {
      this.logger.info(
        'processNextFileInQueue',
        `Already sending ${activeFile.substring(0, 8)}... to ${targetUser}, waiting`
      );
      return;
    }

    const queue = this.userFileQueues.get(targetUser);
    if (!queue || queue.length === 0) {
      this.logger.debug('processNextFileInQueue', `No files in queue for ${targetUser}`);
      return;
    }

    this.logger.info(
      'processNextFileInQueue',
      `Processing queue for ${targetUser}: ${queue.length} files waiting`
    );

    const nextFileId = queue.shift();
    if (!nextFileId) {
      return;
    }

    const userMap = await this.getFileTransfers(targetUser);
    if (!userMap) {
      this.logger.error('processNextFileInQueue', `No userMap for ${targetUser}`);
      await this.processNextFileInQueue(targetUser);
      return;
    }

    const fileTransfer = userMap.get(nextFileId);
    if (!fileTransfer) {
      this.logger.warn('processNextFileInQueue', `File ${nextFileId.substring(0, 8)}... cancelled`);
      await this.processNextFileInQueue(targetUser);
      return;
    }

    const dataChannel = this.getDataChannel(targetUser);
    const channelState = dataChannel?.readyState ?? 'no-channel';
    if (!dataChannel || dataChannel.readyState !== 'open') {
      this.logger.error(
        'processNextFileInQueue',
        `Channel not open for ${targetUser} (state: ${channelState}), initiating connection and retrying`
      );
      queue.unshift(nextFileId);
      // Initiate connection and retry after delay
      this.initiateConnection(targetUser);
      setTimeout(() => this.processNextFileInQueue(targetUser), 2000);
      return;
    }

    // Mark as active and start transfer
    this.activeFilePerUser.set(targetUser, nextFileId);
    this.logger.info(
      'processNextFileInQueue',
      `Starting file transfer: ${fileTransfer.file.name} (${nextFileId.substring(0, 8)}...) to ${targetUser}`
    );

    try {
      await this.sendFileChunks(fileTransfer);
    } catch (error) {
      this.logger.error('processNextFileInQueue', `File transfer failed: ${error}`);
    }
  }

  /**
   * Declines a file offer request
   */
  public async declineFileOffer(targetUser: string, fileId: string): Promise<void> {
    const transferId = this.getOrCreateStatusKey(targetUser, fileId);
    await this.setFileTransferStatus(transferId, FileTransferStatus.DECLINED);

    const userMap = await this.getFileTransfers(targetUser);
    if (userMap) {
      this.markGroupOutcome(userMap.get(fileId)?.groupId, false);
      userMap.delete(fileId);
      await this.setFileTransfers(targetUser, userMap);
    }
    await this.updateActiveUploads();
    await this.checkAllUsersResponded();
  }

  /**
   * Stops an active file upload
   * @param targetUser The user the file was being sent to
   * @param fileId The file ID to stop
   * @param notifyRecipient Whether to send cancellation message to recipient (default: true)
   *                        Set to false when receiver already cancelled (to avoid redundant message)
   */
  public async stopFileUpload(
    targetUser: string,
    fileId: string,
    notifyRecipient: boolean = true
  ): Promise<void> {
    const userMap = await this.getFileTransfers(targetUser);
    if (userMap?.has(fileId)) {
      const fileTransfer = userMap.get(fileId);
      if (fileTransfer) {
        fileTransfer.isPaused = true;
        await this.setFileTransfers(targetUser, userMap);
      }

      this.markGroupOutcome(fileTransfer?.groupId, false);
      userMap.delete(fileId);
      const key = this.getOrCreateStatusKey(targetUser, fileId);
      await this.deleteFileTransferStatus(key);
      await this.setFileTransfers(targetUser, userMap);
      await this.updateActiveUploads();

      // Remove from queue if present
      const queue = this.userFileQueues.get(targetUser);
      if (queue) {
        const idx = queue.indexOf(fileId);
        if (idx !== -1) {
          queue.splice(idx, 1);
        }
      }

      // Clear active file if this was the one being transferred
      if (this.activeFilePerUser.get(targetUser) === fileId) {
        this.activeFilePerUser.set(targetUser, null);
        // Process next file in queue
        await this.processNextFileInQueue(targetUser);
      }

      // Only send notification if recipient doesn't already know
      if (notifyRecipient) {
        const message = {
          type: FILE_TRANSFER_MESSAGE_TYPES.FILE_CANCEL_UPLOAD,
          payload: {
            fileId: fileId,
          },
        };
        this.sendData(message, targetUser);
      }
    } else {
      this.logger.error(
        'stopFileUpload',
        `No file transfer found for ${targetUser} and fileId=${fileId}`
      );
    }
  }

  /**
   * Stops every in-flight upload to a peer that left the room and clears its
   * per-user queue state. No notification — the peer is already gone.
   */
  public async stopUploadsToPeer(user: string): Promise<void> {
    const userMap = await this.getFileTransfers(user);
    if (userMap) {
      for (const fileId of Array.from(userMap.keys())) {
        await this.stopFileUpload(user, fileId, false);
      }
    }
    this.userFileQueues.delete(user);
    this.activeFilePerUser.delete(user);
    this.processingQueues.delete(user);
    this.consecutiveErrorCounts.delete(user);
    this.offerReady.delete(user);
  }

  /**
   * Completes an upload once the receiver confirms the file was assembled.
   */
  public async completeFileUpload(targetUser: string, fileId: string): Promise<void> {
    const userMap = await this.getFileTransfers(targetUser);
    const fileTransfer = userMap?.get(fileId);

    if (!userMap || !fileTransfer) {
      this.logger.debug(
        'completeFileUpload',
        `No pending upload found for ${targetUser} and fileId=${fileId}`
      );
      return;
    }

    const key = this.getOrCreateStatusKey(targetUser, fileId);
    await this.setFileTransferStatus(key, FileTransferStatus.COMPLETED);
    this.markGroupOutcome(fileTransfer.groupId, true);

    this.toaster.success(
      this.translate.instant('FILE_UPLOAD_COMPLETED', { fileName: fileTransfer.file.name })
    );

    userMap.delete(fileId);
    await this.setFileTransfers(targetUser, userMap);
    await this.updateActiveUploads();
    await this.checkAllUsersResponded();
  }

  /**
   * Resumes a paused file transfer when buffer is available
   */
  public async resumePausedTransfer(targetUser: string): Promise<void> {
    const userMap = await this.getFileTransfers(targetUser);
    if (!userMap) return;

    const activeFileId = this.activeFilePerUser.get(targetUser);
    if (!activeFileId) {
      // No active file, try to process queue
      await this.processNextFileInQueue(targetUser);
      return;
    }

    const fileTransfer = userMap.get(activeFileId);
    if (fileTransfer?.isPaused && fileTransfer.currentOffset < fileTransfer.file.size) {
      const dataChannel = this.getDataChannel(targetUser);
      if (dataChannel && dataChannel.bufferedAmount <= MAX_BUFFERED_AMOUNT) {
        this.logger.info('resumePausedTransfer', `Resuming ${activeFileId} for ${targetUser}`);
        fileTransfer.isPaused = false;
        await this.setFileTransfers(targetUser, userMap);

        // Continue sending chunks
        this.sendFileChunks(fileTransfer).catch((error: unknown) => {
          this.logger.error('resumePausedTransfer', `Error resuming: ${error}`);
        });
      }
    }
  }

  // =============== Private Helper Methods ===============
  /**
   * Sends a file offer to a target user
   */
  private async sendFileOffer(fileId: string, targetUser: string): Promise<void> {
    if (!this.userService.user) {
      this.logger.error('sendFileOffer', 'No current user set in UserService');
      return;
    }

    const userMap = await this.getFileTransfers(targetUser);
    if (!userMap) {
      this.logger.error('sendFileOffer', 'No Map of files for ' + targetUser);
      return;
    }

    const fileTransfer = userMap.get(fileId);
    if (!fileTransfer) {
      this.logger.error('sendFileOffer', `No file with id=${fileId} to send to ${targetUser}`);
      this.toaster.error(this.translate.instant('NO_FILE_TO_SEND'));
      return;
    }

    this.logger.info('sendFileOffer', `Sending file offer to ${targetUser} (id=${fileId})`);

    const key = this.getOrCreateStatusKey(targetUser, fileId);
    await this.setFileTransferStatus(key, FileTransferStatus.PENDING);

    let markOfferReady!: () => void;
    this.offerReady.set(key, new Promise<void>((resolve) => (markOfferReady = resolve)));

    try {
      // Phase 1: Send basic offer IMMEDIATELY so receiver sees it right away
      const basicMessage = {
        type: FILE_TRANSFER_MESSAGE_TYPES.FILE_OFFER,
        payload: {
          fileId: fileId,
          fileName: fileTransfer.file.name,
          fileSize: fileTransfer.file.size,
          fromUser: this.userService.user,
        },
      };
      this.sendData(basicMessage, targetUser);
      this.logger.debug('sendFileOffer', `Sent basic offer for ${fileId} to ${targetUser}`);

      // Phase 2: Calculate hash and generate preview, then send complete offer
      let previewDataUrl: string | undefined;
      let previewMime: string | undefined;
      let fileHash: string | undefined;

      // Calculate file hash for integrity verification. Integrity is MANDATORY:
      // if we can't hash the file, we must not send it (the receiver rejects any
      // file without a verified hash). Abort and tell the receiver to drop the
      // phase-1 offer they already saw.
      try {
        fileHash = await this.prewarmFileHash(fileTransfer.file);
        this.logger.debug(
          'sendFileOffer',
          `File hash for ${fileId}: ${fileHash.substring(0, 16)}...`
        );
      } catch (e) {
        this.logger.error(
          'sendFileOffer',
          `Hash failed for ${fileId}, aborting send: ${String(e)}`
        );
        this.toaster.error(
          this.translate.instant('FILE_SEND_HASH_FAILED', { fileName: fileTransfer.file.name })
        );
        await this.stopFileUpload(targetUser, fileId);
        return;
      }

      try {
        const mime = fileTransfer.file.type || '';
        if (mime.startsWith('image/')) {
          const thumb = await this.previewService.createImageThumbnail(fileTransfer.file);
          previewDataUrl = thumb.dataUrl;
          previewMime = thumb.mime;
        } else if (mime === 'application/pdf') {
          previewDataUrl = await this.previewService.createPdfThumbnailFromFile(fileTransfer.file);
          if (previewDataUrl) {
            previewMime = PREVIEW_MIME_TYPE;
          }
        }

        // Check if preview is too large for WebRTC message limit
        if (previewDataUrl && previewDataUrl.length > MAX_PREVIEW_DATA_URL_SIZE) {
          this.logger.warn(
            'sendFileOffer',
            `Preview too large (${(previewDataUrl.length / 1024).toFixed(1)}KB), skipping to avoid WebRTC message limit`
          );
          previewDataUrl = undefined;
          previewMime = undefined;
        }
      } catch (e) {
        this.logger.warn('sendFileOffer', `Failed generating preview: ${String(e)}`);
      }

      // Only send update if we have hash or preview to add
      if (fileHash || previewDataUrl) {
        const completeMessage = {
          type: FILE_TRANSFER_MESSAGE_TYPES.FILE_OFFER,
          payload: {
            fileId: fileId,
            fileName: fileTransfer.file.name,
            fileSize: fileTransfer.file.size,
            fileHash,
            previewDataUrl,
            previewMime,
            fromUser: this.userService.user,
          },
        };
        this.sendData(completeMessage, targetUser);
        this.logger.debug('sendFileOffer', `Sent complete offer with preview for ${fileId}`);
      }
    } finally {
      markOfferReady();
    }
  }

  /**
   * Checks if all users have responded to file offers
   */
  private async checkAllUsersResponded(): Promise<void> {
    const allStatuses = Array.from(await this.getFileTransferStatuses());
    this.logger.debug('checkAllUsersResponded', 'All statuses:', allStatuses);

    const allResponded = allStatuses.every(
      (status) => status === FileTransferStatus.DECLINED || status === FileTransferStatus.COMPLETED
    );

    if (allResponded && allStatuses.length > 0) {
      this.logger.info('checkAllUsersResponded', 'All files have been completed/declined.');
      this.toaster.success(this.translate.instant('ALL_FILES_RESPONDED'));
      await this.clearFileTransfers();
      await this.updateActiveUploads();
    }
  }

  // =============== File Chunk Processing Methods ===============
  /**
   * Sends all chunks of a file using the self-contained binary protocol.
   * Each chunk contains embedded fileId, eliminating chunk mismatching.
   */
  private async sendFileChunks(fileTransfer: FileUpload): Promise<void> {
    return startNewTrace(() =>
      Sentry.startSpan({ name: 'file.transfer.send', op: 'file.transfer.send' }, async (span) => {
        span.setAttribute('file_size_bytes', fileTransfer.file.size);
        return this.sendFileChunksInner(fileTransfer, span);
      })
    );
  }

  private async sendFileChunksInner(fileTransfer: FileUpload, span: Sentry.Span): Promise<void> {
    const transferId = this.getOrCreateStatusKey(fileTransfer.targetUser, fileTransfer.fileId);
    if (this.processingQueues.get(transferId)) {
      this.logger.warn(
        'sendFileChunks',
        `Already processing ${fileTransfer.fileId.substring(0, 8)}...`
      );
      return;
    }

    this.processingQueues.set(transferId, true);
    const totalChunks = calculateTotalChunks(fileTransfer.file.size, CHUNK_SIZE);
    let chunkIndex = Math.floor(fileTransfer.currentOffset / CHUNK_SIZE);

    const PROGRESS_FLUSH_INTERVAL_MS = 250;
    let lastProgressFlush = 0;

    this.logger.info(
      'sendFileChunks',
      `Starting: ${fileTransfer.file.name}, size=${fileTransfer.file.size}, chunks=${totalChunks}`
    );

    try {
      while (fileTransfer.currentOffset < fileTransfer.file.size) {
        const userMap = await this.getFileTransfers(fileTransfer.targetUser);
        if (!userMap?.has(fileTransfer.fileId)) {
          this.logger.warn(
            'sendFileChunks',
            `File transfer cancelled for fileId=${fileTransfer.fileId}`
          );
          break;
        }

        if (fileTransfer.isPaused) {
          this.logger.warn('sendFileChunks', `Upload paused for fileId=${fileTransfer.fileId}`);
          break;
        }

        const dataChannel = this.getDataChannel(fileTransfer.targetUser);
        if (!dataChannel || dataChannel.readyState !== 'open') {
          this.logger.error(
            'sendFileChunks',
            `Data channel not available for ${fileTransfer.targetUser}`
          );
          this.initiateConnection(fileTransfer.targetUser);
          await new Promise((resolve) => setTimeout(resolve, 1000));

          const errorCount = this.consecutiveErrorCounts.get(transferId) ?? 0;
          this.consecutiveErrorCounts.set(transferId, errorCount + 1);
          if (errorCount > this.maxConsecutiveErrors) {
            span.setAttribute('outcome', 'aborted_channel_unavailable');
            span.setStatus({ code: 2, message: 'channel_unavailable' });
            await this.stopFileUpload(fileTransfer.targetUser, fileTransfer.fileId);
            break;
          }
          continue;
        }

        // Check buffer before sending
        if (dataChannel.bufferedAmount > MAX_BUFFERED_AMOUNT * 0.7) {
          this.logger.warn('sendFileChunks', `Buffer high, pausing for ${fileTransfer.targetUser}`);
          fileTransfer.isPaused = true;
          break;
        }

        // Prepare chunk data
        const start = fileTransfer.currentOffset;
        const end = Math.min(start + CHUNK_SIZE, fileTransfer.file.size);
        const blob = fileTransfer.file.slice(start, end);

        try {
          const chunkData = await blob.arrayBuffer();

          // Encode chunk with embedded metadata (fileId, index, total)
          const encodedChunk = encodeChunk(fileTransfer.fileId, chunkIndex, totalChunks, chunkData);

          // Send the self-contained chunk
          const sent = this.sendRawData(encodedChunk, fileTransfer.targetUser);
          if (!sent) {
            this.logger.warn(
              'sendFileChunks',
              `Failed to send chunk ${chunkIndex}/${totalChunks} for ${fileTransfer.fileId.substring(0, 8)}...`
            );
            await new Promise((resolve) => setTimeout(resolve, 500));
            continue;
          }

          // Log first chunk sent
          if (chunkIndex === 0) {
            this.logger.info(
              'sendFileChunks',
              `First chunk sent for ${fileTransfer.file.name} (encoded size: ${encodedChunk.byteLength})`
            );
          }

          // Update progress
          fileTransfer.currentOffset = end;
          fileTransfer.progress = parseFloat(((end / fileTransfer.file.size) * 100).toFixed(2));
          chunkIndex++;

          // Reset error count on success
          this.consecutiveErrorCounts.set(transferId, 0);

          const now = Date.now();
          if (
            now - lastProgressFlush >= PROGRESS_FLUSH_INTERVAL_MS &&
            !fileTransfer.isPaused &&
            userMap.has(fileTransfer.fileId)
          ) {
            lastProgressFlush = now;
            userMap.set(fileTransfer.fileId, fileTransfer);
            await this.setFileTransfers(fileTransfer.targetUser, userMap);
            await this.updateActiveUploads();
          }

          // Log progress every MB
          if (fileTransfer.currentOffset % MB < CHUNK_SIZE) {
            const mbSent = (fileTransfer.currentOffset / MB).toFixed(2);
            this.logger.info('sendFileChunks', `${fileTransfer.fileId}: ${mbSent}MB sent`);
          }
        } catch (error) {
          this.logger.error('sendFileChunks', `Error preparing chunk: ${error}`);
          const errorCount = this.consecutiveErrorCounts.get(transferId) ?? 0;
          this.consecutiveErrorCounts.set(transferId, errorCount + 1);

          if (errorCount >= this.maxConsecutiveErrors) {
            span.setAttribute('outcome', 'aborted_max_errors');
            span.setStatus({ code: 2, message: 'max_consecutive_errors' });
            await this.stopFileUpload(fileTransfer.targetUser, fileTransfer.fileId);
            break;
          }
          await new Promise((resolve) => setTimeout(resolve, 500));
        }
      }

      // Check if transfer completed
      if (fileTransfer.currentOffset >= fileTransfer.file.size) {
        this.logger.info(
          'sendFileChunks',
          `Queued all chunks for ${fileTransfer.fileId} to ${fileTransfer.targetUser}`
        );
        span.setAttribute('outcome', 'queued_all_chunks');
        span.setStatus({ code: 1, message: 'ok' });
        fileTransfer.progress = 100;
        fileTransfer.phase = 'finalizing';

        const userMap = await this.getFileTransfers(fileTransfer.targetUser);
        if (userMap?.has(fileTransfer.fileId)) {
          userMap.set(fileTransfer.fileId, fileTransfer);
          await this.setFileTransfers(fileTransfer.targetUser, userMap);
        }
        await this.updateActiveUploads();
      }
    } finally {
      this.processingQueues.set(transferId, false);

      if (!fileTransfer.isPaused) {
        this.activeFilePerUser.set(fileTransfer.targetUser, null);
        await this.processNextFileInQueue(fileTransfer.targetUser);
      } else {
        this.logger.info(
          'sendFileChunks',
          `File ${fileTransfer.fileId.substring(0, 8)}... paused, waiting for buffer to empty`
        );
      }
    }
  }

  // =============== Outgoing Group Aggregation ===============
  /** Registers a logical send to `total` recipients before per-peer prep. */
  public beginUploadGroup(groupId: string, total: number): void {
    this.outgoingGroups.set(groupId, { total, completed: 0, failed: 0 });
  }

  /** Records a per-peer terminal outcome and re-derives the bubble status. */
  private markGroupOutcome(groupId: string | undefined, success: boolean): void {
    if (!groupId) return;
    const group = this.outgoingGroups.get(groupId);
    if (!group) return;
    if (success) group.completed++;
    else group.failed++;
    this.recomputeGroup(groupId);
  }

  private recomputeGroup(groupId: string): void {
    const group = this.outgoingGroups.get(groupId);
    if (!group) return;
    const resolved = group.completed + group.failed >= group.total;
    this.outgoingGroupStatus$.next({
      groupId,
      delivered: group.completed,
      total: group.total,
      resolved,
    });
    if (resolved) this.outgoingGroups.delete(groupId);
  }
}
