import { Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslateModule } from '@ngx-translate/core';

import { FileDownload, FileUpload, MemberConnectionState } from '../../../../utils/constants';
import { LanguageCode } from '../../../../core/i18n/languages';
import { LanguageSwitcherComponent } from '../../../../core/components/language-switcher/language-switcher.component';

@Component({
  selector: 'app-chat-sidebar',
  imports: [CommonModule, RouterLink, TranslateModule, LanguageSwitcherComponent],
  templateUrl: './chat-sidebar.component.html',
  styleUrl: './chat-sidebar.component.css',
})
export class ChatSidebarComponent {
  @Input() rooms: string[] = [];
  @Input() members: string[] = [];
  @Input() currentRoom = '';
  @Input() sessionCode = '';
  @Input() activeUploads: FileUpload[] = [];
  @Input() activeDownloads: FileDownload[] = [];
  @Input() memberConnectionStatus: Map<string, boolean> = new Map();
  @Input() memberConnectionState: Map<string, MemberConnectionState> = new Map();
  @Input() isRTL = false;
  @Input() isDarkMode = false;
  @Input() isMenuOpen = false;
  @Input() skipDrawerAnim = false;
  @Input() currentUser: string | null = null;
  @Input() appVersion = '';
  @Input() currentLanguage: LanguageCode = 'en';

  @Output() isMenuOpenChange = new EventEmitter<boolean>();
  @Output() switchLanguage = new EventEmitter<LanguageCode>();

  @Output() joinRoomRequested = new EventEmitter<string>();
  @Output() createRoomRequested = new EventEmitter<void>();
  @Output() copySessionCodeRequested = new EventEmitter<void>();
  @Output() qrCodeRequested = new EventEmitter<void>();
  @Output() createPrivateSessionRequested = new EventEmitter<void>();
  @Output() joinPrivateSessionRequested = new EventEmitter<void>();
  @Output() endSessionRequested = new EventEmitter<void>();
  @Output() filePickerRequested = new EventEmitter<string>();
  @Output() cancelUploadRequested = new EventEmitter<FileUpload>();
  @Output() cancelDownloadRequested = new EventEmitter<FileDownload>();

  protected isConnectedToMember(member: string): boolean {
    return this.memberConnectionStatus.get(member) ?? false;
  }

  protected memberDotClass(member: string): Record<string, boolean> {
    const state = this.memberConnectionState.get(member) ?? 'disconnected';
    return {
      'bg-green-500': state === 'connected',
      'bg-yellow-400': state === 'connecting',
      'bg-red-500': state === 'disconnected',
    };
  }

  protected memberDotTitle(member: string): string {
    const state = this.memberConnectionState.get(member) ?? 'disconnected';
    return state === 'connected'
      ? 'Connected'
      : state === 'connecting'
        ? 'Connecting…'
        : 'Not connected';
  }

  protected progressValue(progress: number): number {
    if (!Number.isFinite(progress)) {
      return 0;
    }

    return Math.min(100, Math.max(0, progress));
  }

  protected progressLabel(progress: number): number {
    const safeProgress = this.progressValue(progress);
    return safeProgress >= 100 ? 100 : Math.floor(safeProgress);
  }

  protected getProgressBarWidth(progress: number): string {
    const safeProgress = this.progressValue(progress);
    return `${safeProgress}%`;
  }

  protected truncateFilename(filename: string, maxLength: number = 30): string {
    if (filename.length <= maxLength) {
      return filename;
    }

    const lastDotIndex = filename.lastIndexOf('.');
    if (lastDotIndex === -1) {
      return filename.slice(0, maxLength) + '...';
    }

    const extension = filename.slice(lastDotIndex);
    const baseName = filename.slice(0, lastDotIndex);
    const availableLength = maxLength - extension.length - 3;

    if (availableLength <= 0) {
      return filename.slice(0, maxLength) + '...';
    }

    return baseName.slice(0, availableLength) + '...' + extension;
  }
}
