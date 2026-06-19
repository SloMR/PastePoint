import { Injectable } from '@angular/core';
import { FileDownload, FILE_TRANSFER_MESSAGE_TYPES } from '../../../utils/constants';
import { FileTransferBaseService } from './file-transfer-base.service';

@Injectable({
  providedIn: 'root',
})
export class FileOfferService extends FileTransferBaseService {
  // =============== Constructor ===============
  constructor() {
    super();
  }

  // =============== File Offer Methods ===============
  /**
   * Receives and processes a file offer from another user.
   * If the fileId already exists, updates it with new fields (preview, hash).
   * This allows instant notification followed by preview update.
   */
  public async receiveFileOffer(offer: {
    fileId: string;
    fileName: string;
    fileSize: number;
    fromUser: string;
    fileHash?: string;
    previewDataUrl?: string;
    previewMime?: string;
  }): Promise<void> {
    const { fromUser, fileId, fileSize, fileHash, previewDataUrl, previewMime } = offer;
    const fileName = this.sanitizeFileName(offer.fileName);

    let fileTransfers = await this.getIncomingFileTransfers(fromUser);
    if (!fileTransfers) {
      fileTransfers = new Map<string, FileDownload>();
      await this.setIncomingFileTransfers(fromUser, fileTransfers);
    }

    const existingDownload = fileTransfers.get(fileId);

    if (existingDownload) {
      // Update existing entry with new fields (preview/hash came in second message)
      if (fileHash) {
        existingDownload.expectedHash = fileHash;
      }
      if (previewDataUrl) {
        existingDownload.previewDataUrl = previewDataUrl;
      }
      if (previewMime) {
        existingDownload.previewMime = previewMime;
      }
      this.logger.debug('receiveFileOffer', `Updated existing offer ${fileId} with preview/hash`);
    } else {
      // Create new entry
      const fileDownload: FileDownload = {
        fileId,
        fileName,
        fileSize,
        fromUser,
        receivedSize: 0,
        receivedChunks: new Map<number, Blob>(),
        totalChunks: 0,
        progress: 0,
        isAccepted: false,
        lastActivity: Date.now(),
        previewDataUrl,
        previewMime,
        expectedHash: fileHash,
      };
      fileTransfers.set(fileId, fileDownload);
      this.logger.debug('receiveFileOffer', `Created new offer ${fileId} from ${fromUser}`);
    }

    await this.setIncomingFileTransfers(fromUser, fileTransfers);
    await this.updateIncomingFileOffers();
  }

  /**
   * Accepts a file offer and notifies the sender
   */
  public async acceptFileOffer(fromUser: string, fileId: string): Promise<void> {
    const userMap = await this.getIncomingFileTransfers(fromUser);
    if (!userMap) {
      this.logger.error('acceptFileOffer', `No incoming file map found from user: ${fromUser}`);
      return;
    }

    const fileDownload = userMap.get(fileId);
    if (!fileDownload) {
      this.logger.error('acceptFileOffer', `No file with id=${fileId} from ${fromUser} to accept`);
      return;
    }

    fileDownload.isAccepted = true;
    fileDownload.lastActivity = Date.now();
    await this.setIncomingFileTransfers(fromUser, userMap);
    await this.updateIncomingFileOffers();

    const message = {
      type: FILE_TRANSFER_MESSAGE_TYPES.FILE_ACCEPT,
      payload: {
        fileId: fileId,
      },
    };

    this.logger.debug(
      'acceptFileOffer',
      `Sending file acceptance to ${fromUser} for fileId=${fileId}`
    );
    this.sendData(message, fromUser);
    await this.updateActiveDownloads();
  }

  /**
   * Declines a file offer and notifies the sender
   */
  public async declineFileOffer(fromUser: string, fileId: string): Promise<void> {
    const userMap = await this.getIncomingFileTransfers(fromUser);
    if (userMap) {
      userMap.delete(fileId);
      if (userMap.size === 0) {
        await this.deleteIncomingFileTransfers(fromUser);
      }
    }
    await this.updateIncomingFileOffers();

    const message = {
      type: FILE_TRANSFER_MESSAGE_TYPES.FILE_DECLINE,
      payload: {
        fileId: fileId,
      },
    };
    this.sendData(message, fromUser);
    this.toaster.info(this.translate.instant('FILE_TRANSFER_DECLINED'));
  }
}
