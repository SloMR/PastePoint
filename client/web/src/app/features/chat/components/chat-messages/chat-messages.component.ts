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
import { truncateFilename as truncateFilenameUtil } from '../../../../utils/filename.util';
import { avatarFor } from '../../../../utils/avatar.util';
import { MessageActionsComponent } from '../message-actions/message-actions.component';

@Component({
  selector: 'app-chat-messages',
  imports: [CommonModule, DatePipe, FileSizePipe, TranslateModule, MessageActionsComponent],
  providers: [FileSizePipe],
  templateUrl: './chat-messages.component.html',
  styleUrl: './chat-messages.component.css',
})
export class ChatMessagesComponent {
  @Input() messages: ChatMessage[] = [];
  @Input() sessionCode = '';
  @Input() isRTL = false;
  @Input() isDarkMode = false;
  @Input() currentUser: string | null = null;

  @Output() acceptFile = new EventEmitter<ChatMessage>();
  @Output() declineFile = new EventEmitter<ChatMessage>();
  @Output() blockRequested = new EventEmitter<string>();
  @Output() reportRequested = new EventEmitter<ChatMessage>();

  @ViewChild('messageContainer') messageContainer!: ElementRef;

  protected readonly ChatMessageType = ChatMessageType;
  protected readonly FileTransferStatus = FileTransferStatus;

  private sanitizer = inject(DomSanitizer);

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

  protected truncateFilename(filename: string, maxLength = 30): string {
    return truncateFilenameUtil(filename, maxLength);
  }
}
