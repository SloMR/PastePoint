import {
  Component,
  ElementRef,
  EventEmitter,
  Input,
  Output,
  SecurityContext,
  ViewChild,
  inject,
} from '@angular/core';
import { CommonModule, DatePipe } from '@angular/common';
import { DomSanitizer } from '@angular/platform-browser';
import { TranslateModule } from '@ngx-translate/core';
import Autolinker from 'autolinker';

import { ChatMessage, ChatMessageType, FileTransferStatus } from '../../../../utils/constants';
import { FileSizePipe } from '../../../../utils/file-size.pipe';
import { middleTruncateFilename as middleTruncateFilenameUtil } from '../../../../utils/filename.util';
import { avatarFor } from '../../../../utils/avatar.util';
import { MessageActionsComponent } from '../message-actions/message-actions.component';
import { BlurredPreviewComponent } from '../blurred-preview/blurred-preview.component';
import { WelcomeComponent } from '../welcome/welcome.component';

@Component({
  selector: 'app-chat-messages',
  imports: [
    CommonModule,
    DatePipe,
    FileSizePipe,
    TranslateModule,
    MessageActionsComponent,
    BlurredPreviewComponent,
    WelcomeComponent,
  ],
  providers: [FileSizePipe],
  templateUrl: './chat-messages.component.html',
  styleUrl: './chat-messages.component.css',
})
export class ChatMessagesComponent {
  @Input() messages: ChatMessage[] = [];
  @Input() sessionCode = '';
  @Input() memberCount = 0;
  @Input() isRTL = false;
  @Input() isDarkMode = false;
  @Input() currentUser: string | null = null;

  @Output() acceptFile = new EventEmitter<ChatMessage>();
  @Output() declineFile = new EventEmitter<ChatMessage>();
  @Output() blockRequested = new EventEmitter<string>();
  @Output() reportRequested = new EventEmitter<ChatMessage>();
  @Output() connectDeviceRequested = new EventEmitter<void>();
  @Output() showQrRequested = new EventEmitter<void>();
  @Output() copyCodeRequested = new EventEmitter<void>();

  @ViewChild('messageContainer') messageContainer!: ElementRef;

  protected readonly ChatMessageType = ChatMessageType;
  protected readonly FileTransferStatus = FileTransferStatus;
  private readonly revealedPreviews = new Set<string>();

  private sanitizer = inject(DomSanitizer);

  protected isPreviewRevealed(msg: ChatMessage): boolean {
    const id = msg.fileTransfer?.fileId;
    return id ? this.revealedPreviews.has(id) : false;
  }

  protected revealPreview(msg: ChatMessage): void {
    const id = msg.fileTransfer?.fileId;
    if (id) {
      this.revealedPreviews.add(id);
    }
  }

  trackMessage(index: number, message: ChatMessage): string {
    if (message.type === ChatMessageType.ATTACHMENT && message.fileTransfer?.fileId) {
      return `att-${message.fileTransfer.fileId}`;
    }

    const ts =
      message.timestamp instanceof Date ? message.timestamp.getTime() : `${message.timestamp}`;
    return `${message.from}-${ts}`;
  }

  isMyMessage(msg: ChatMessage): boolean {
    return msg.isMine === true;
  }

  protected avatarFor(msg: ChatMessage): string {
    return avatarFor(msg.from, this.isMyMessage(msg));
  }

  protected convertUrlsToLinks(
    text: string,
    isDarkMode: boolean,
    isMyMessage: boolean = false
  ): string {
    if (!text) return this.sanitizer.sanitize(SecurityContext.HTML, '') || '';

    const escapeHtml = (unsafe: string): string => {
      return unsafe
        .replace(/&/g, '&amp;')
        .replace(/</g, '&lt;')
        .replace(/>/g, '&gt;')
        .replace(/"/g, '&quot;')
        .replace(/'/g, '&#039;');
    };

    const processedText = escapeHtml(text);

    const linkClasses = isMyMessage
      ? isDarkMode
        ? 'text-blue-400 hover:text-blue-800 underline break-all'
        : 'text-blue-600 hover:text-blue-400 underline break-all'
      : 'text-blue-200 hover:text-blue-500 underline break-all';

    const textWithLinks = Autolinker.link(processedText, {
      urls: true,
      email: false,
      phone: false,
      mention: false,
      hashtag: false,
      newWindow: true,
      className: linkClasses,
      stripPrefix: false,
      sanitizeHtml: true,
    });

    const sanitizedHtml = this.sanitizer.sanitize(SecurityContext.HTML, textWithLinks);
    return sanitizedHtml || '';
  }

  protected middleTruncateFilename(filename: string, maxLength = 30): string {
    return middleTruncateFilenameUtil(filename, maxLength);
  }
}
