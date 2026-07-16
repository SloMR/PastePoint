import { Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslateModule } from '@ngx-translate/core';

import { FileDownload, FileUpload, MemberConnectionState } from '../../../../utils/constants';
import { LanguageCode } from '../../../../core/i18n/languages';
import {
  splitFilenameExtension,
  truncateFilename as truncateFilenameUtil,
} from '../../../../utils/filename.util';
import { LanguageSwitcherComponent } from '../../../../core/components/language-switcher/language-switcher.component';
import { SELF_AVATAR } from '../../../../utils/avatar.util';

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

  protected readonly selfAvatar = SELF_AVATAR;

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
  @Output() blockRequested = new EventEmitter<string>();
  @Output() cancelUploadRequested = new EventEmitter<FileUpload>();
  @Output() cancelDownloadRequested = new EventEmitter<FileDownload>();

  protected isConnectedToMember(member: string): boolean {
    return this.memberConnectionStatus.get(member) ?? false;
  }

  protected uploadsForMember(member: string): FileUpload[] {
    return this.activeUploads.filter((upload) => upload.targetUser === member);
  }

  protected downloadsForMember(member: string): FileDownload[] {
    return this.activeDownloads.filter((download) => download.fromUser === member);
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

  protected truncateFilename(filename: string, maxLength = 30): string {
    return truncateFilenameUtil(filename, maxLength);
  }

  protected filenameBaseName(filename: string): string {
    return splitFilenameExtension(filename).baseName;
  }

  protected filenameExtension(filename: string): string {
    return splitFilenameExtension(filename).extension;
  }
}
