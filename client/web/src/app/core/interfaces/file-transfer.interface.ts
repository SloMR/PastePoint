import { BehaviorSubject } from 'rxjs';
import { FileDownload, FileUpload } from '../../utils/constants';

export interface IFileTransferService {
  activeUploads$: BehaviorSubject<FileUpload[]>;
  activeDownloads$: BehaviorSubject<FileDownload[]>;
  incomingFileOffers$: BehaviorSubject<FileDownload[]>;

  prepareFileForSending(file: File, targetUser: string, batchId: string): Promise<void>;
  beginUploadBatch(batchId: string, total: number): void;
  sendAllFileOffers(targetUser: string): Promise<void>;
  stopFileUpload(targetUser: string, fileId: string): Promise<void>;
  cancelFileDownload(fromUser: string, fileId: string): Promise<void>;
  acceptFileOffer(fromUser: string, fileId: string): Promise<void>;
  declineFileOffer(fromUser: string, fileId: string): Promise<void>;
}
