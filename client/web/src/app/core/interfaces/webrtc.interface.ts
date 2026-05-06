import { BehaviorSubject, Subject } from 'rxjs';
import { ChatMessage, DataChannelMessage } from '../../utils/constants';

export interface IWebRTCService {
  dataChannelOpen$: BehaviorSubject<boolean>;
  chatMessages$: Subject<ChatMessage>;
  fileOffers$: Subject<{
    fileName: string;
    fileSize: number;
    fromUser: string;
    fileId: string;
  }>;
  fileResponses$: Subject<{ accepted: boolean; fromUser: string; fileId: string }>;
  fileUploadCancelled$: Subject<{ fromUser: string; fileId: string }>;
  fileDownloadCancelled$: Subject<{ fromUser: string; fileId: string }>;
  bufferedAmountLow$: Subject<string>;
  incomingFileChunk$: Subject<{
    fromUser: string;
    fileId: string;
    chunkIndex: number;
    totalChunks: number;
    chunk: ArrayBuffer;
    isValid: boolean;
  }>;

  initiateConnection(targetUser: string): void;
  sendData(data: DataChannelMessage, targetUser: string): void;
  closeConnection(targetUser: string): void;
  closeAllConnections(): void;
}
