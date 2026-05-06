import {
  AfterViewInit,
  ChangeDetectionStrategy,
  ChangeDetectorRef,
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  ElementRef,
  NgZone,
  OnDestroy,
  OnInit,
  PLATFORM_ID,
  ViewChild,
  inject,
} from '@angular/core';
import { Subscription } from 'rxjs';
import { isPlatformBrowser, NgOptimizedImage, UpperCasePipe } from '@angular/common';

import { ThemeService } from '../../core/services/ui/theme.service';
import { ChatService } from '../../core/services/communication/chat.service';
import { HeartbeatService } from '../../core/services/communication/heartbeat.service';
import { RoomService } from '../../core/services/room-management/room.service';
import { FileTransferService } from '../../core/services/file-management/file-transfer.service';
import { WebRTCService } from '../../core/services/communication/webrtc.service';
import { WebSocketConnectionService } from '../../core/services/communication/websocket-connection.service';
import { UserService } from '../../core/services/user-management/user.service';
import { FormsModule, NgForm } from '@angular/forms';
import { FlowbiteService } from '../../core/services/ui/flowbite.service';
import { TranslateModule, TranslateService } from '@ngx-translate/core';
import {
  ChatMessage,
  ChatMessageType,
  FileDownload,
  FileTransferStatus,
  FileUpload,
  MB,
  NAVIGATION_DELAY_MS,
  CONNECTION_WARNING_DELAY_MS,
  SESSION_CODE_KEY,
  THEME_PREFERENCE_KEY,
  PREVIEW_MIME_TYPE,
} from '../../utils/constants';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { SessionService } from '../../core/services/session/session.service';
import packageJson from '../../../../package.json';
import { NGXLogger } from 'ngx-logger';
import { MigrationService } from '../../core/services/migration/migration.service';
import { MetaService } from '../../core/services/ui/meta.service';
import { LanguageService } from '../../core/services/ui/language.service';
import { LanguageCode } from '../../core/i18n/translate-loader';
import { Router } from '@angular/router';
import { HotToastService } from '@ngxpert/hot-toast';
import { PreviewService } from '../../core/services/ui/preview.service';
import { FileSizePipe } from '../../utils/file-size.pipe';
import { JoinSessionPopupComponent } from './components/popups/join-session-popup/join-session-popup.component';
import { CreateRoomPopupComponent } from './components/popups/create-room-popup/create-room-popup.component';
import { EndSessionPopupComponent } from './components/popups/end-session-popup/end-session-popup.component';
import { QrCodePopupComponent } from './components/popups/qr-code-popup/qr-code-popup.component';
import { ConnectionWarningComponent } from './components/connection-warning/connection-warning.component';
import { ChatInputComponent } from './components/chat-input/chat-input.component';
import { ChatMessagesComponent } from './components/chat-messages/chat-messages.component';
import { ChatSidebarComponent } from './components/chat-sidebar/chat-sidebar.component';

/**
 * ==========================================================
 * COMPONENT DECORATOR
 * Defines the component's selector, modules, template, and style.
 * ==========================================================
 */
@Component({
  selector: 'app-chat',
  imports: [
    FormsModule,
    UpperCasePipe,
    TranslateModule,
    NgOptimizedImage,
    RouterLink,
    JoinSessionPopupComponent,
    CreateRoomPopupComponent,
    EndSessionPopupComponent,
    QrCodePopupComponent,
    ConnectionWarningComponent,
    ChatInputComponent,
    ChatMessagesComponent,
    ChatSidebarComponent,
  ],
  providers: [FileSizePipe],
  templateUrl: './chat.component.html',
  styleUrls: ['./chat.component.css'],
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class ChatComponent implements OnInit, OnDestroy, AfterViewInit {
  userService = inject(UserService);
  private chatService = inject(ChatService);
  private heartbeatService = inject(HeartbeatService);
  private roomService = inject(RoomService);
  private fileTransferService = inject(FileTransferService);
  private webrtcService = inject(WebRTCService);
  private wsConnectionService = inject(WebSocketConnectionService);
  private themeService = inject(ThemeService);
  private languageService = inject(LanguageService);
  private cdr = inject(ChangeDetectorRef);
  private ngZone = inject(NgZone);
  private toaster = inject(HotToastService);
  private flowbiteService = inject(FlowbiteService);
  private sessionService = inject(SessionService);
  private route = inject(ActivatedRoute);
  private logger = inject(NGXLogger);
  private migrationService = inject(MigrationService);
  private metaService = inject(MetaService);
  private router = inject(Router);
  private previewService = inject(PreviewService);
  private fileSizePipe = inject(FileSizePipe);
  protected translate = inject<TranslateService>(TranslateService);
  private platformId = inject(PLATFORM_ID);

  /**
   * ==========================================================
   * PUBLIC PROPERTIES
   * Bound to the template for data-binding and user interactions.
   * ==========================================================
   */
  protected readonly MB: number = MB;
  protected readonly ChatMessageType = ChatMessageType;
  message = '';
  newRoomName = '';
  SessionCode = '';
  newSessionCode = '';

  messages: ChatMessage[] = [];
  rooms: string[] = [];
  members: string[] = [];
  memberConnectionStatus = new Map<string, boolean>(); // true = connected, false = failed
  showConnectionWarning = false;

  currentRoom = 'main';
  isDarkMode = false;
  currentLanguage: LanguageCode = 'en';
  isMenuOpen = false;

  isOpenCreateRoom = false;
  isOpenJoinSessionPopup = false;
  isOpenEndSessionPopup = false;
  isOpenQRCodePopup = false;
  skipDrawerAnim = false;

  activeUploads: FileUpload[] = [];
  activeDownloads: FileDownload[] = [];

  private isNavigatingIntentionally = false;
  private isInitialBootstrap = true;
  private lastMessagesLength: number = 0;
  private connectionInitTimeouts: ReturnType<typeof setTimeout>[] = [];
  private navigationTimeout: ReturnType<typeof setTimeout> | null = null;
  private statusCheckIntervalId: ReturnType<typeof setInterval> | null = null;
  private connectionWarningDismissed = false;
  private connectionWarningTimeouts = new Map<string, ReturnType<typeof setTimeout>>();

  appVersion: string = packageJson.version;

  private visibilityChangeListener = () => {
    if (
      document.visibilityState === 'visible' &&
      this.SessionCode &&
      !this.wsConnectionService.isConnected()
    ) {
      this.logger.info('visibilitychange', 'Page visible, reconnecting if needed');
      void this.connect(this.SessionCode);
    }
  };
  private beforeUnloadHandler = () => {
    if (!this.isNavigatingIntentionally) {
      this.clearSessionCode();
    }
  };

  /**
   * ==========================================================
   * PRIVATE SUBSCRIPTIONS
   * Handles RxJS subscriptions to clean up on destroy.
   * ==========================================================
   */
  private subscriptions: Subscription[] = [];
  public FileTransferStatus = FileTransferStatus;
  private overrideRecipients: string[] | null = null;
  private createdPreviewUrls: string[] = [];

  /**
   * ==========================================================
   * VIEWCHILD REFERENCES
   * Direct references to DOM elements for scrolling, focusing, etc.
   * ==========================================================
   */
  @ViewChild('messageInput', { static: true }) messageInput!: ElementRef;
  @ViewChild(ChatInputComponent) chatInput?: ChatInputComponent;
  @ViewChild(ChatMessagesComponent) chatMessages?: ChatMessagesComponent;

  protected get messageTextarea(): ElementRef | undefined {
    return this.chatInput?.messageTextarea;
  }

  protected get fileInput(): ElementRef<HTMLInputElement> | undefined {
    return this.chatInput?.fileInput;
  }

  protected get messageContainer(): ElementRef | undefined {
    return this.chatMessages?.messageContainer;
  }

  /**
   * ==========================================================
   * LIFECYCLE HOOK: NGONINIT
   * Called once after component construction. Used here
   * to configure theme, subscribe to route params, and
   * initialize chat data once the user is set.
   * ==========================================================
   */
  ngOnInit(): void {
    if (isPlatformBrowser(this.platformId)) {
      import('emoji-picker-element');
    }

    if (!isPlatformBrowser(this.platformId)) {
      const privateSession = this.route.snapshot.paramMap.get('code');
      this.metaService.updateChatMetadata(!!privateSession);
      return;
    }

    // Initialize the chat service and set up the heartbeat monitor
    this.startHeartbeatMonitor();

    // Check if migration is needed due to version change
    const migrationPerformed = this.migrationService.checkAndMigrateIfNeeded(this.appVersion, true);
    if (migrationPerformed) {
      this.logger.debug('ngOnInit', 'Migration performed due to version change');
    } else {
      this.logger.debug('ngOnInit', 'No migration needed');
    }

    // Load Flowbite (if needed)
    this.flowbiteService.loadFlowbite(() => {
      this.logger.debug('ngOnInit', `Flowbite loaded`);
    });

    // Check if route has a session code in URL but don't connect yet.
    // First emission seeds SessionCode for ngAfterViewInit's initial connect();
    // subsequent emissions (from in-app navigation) trigger a full session
    // transition via enterSession().
    this.subscriptions.push(
      this.route.paramMap.subscribe((params) => {
        this.ngZone.run(() => {
          const sessionCode = params.get('code');
          const storedSessionCode = localStorage.getItem(SESSION_CODE_KEY);

          if (this.isInitialBootstrap) {
            this.isInitialBootstrap = false;

            if (sessionCode && this.sessionService.isValidSessionCode(sessionCode)) {
              const sanitized = this.sessionService.sanitizeSessionCode(sessionCode);
              this.SessionCode = sanitized;
              localStorage.setItem(SESSION_CODE_KEY, sanitized);
              this.metaService.updateChatMetadata(true);
            } else if (
              storedSessionCode &&
              this.sessionService.isValidSessionCode(storedSessionCode)
            ) {
              this.SessionCode = this.sessionService.sanitizeSessionCode(storedSessionCode);
              this.metaService.updateChatMetadata(true);
            } else {
              if (sessionCode && !this.sessionService.isValidSessionCode(sessionCode)) {
                this.logger.warn('ngOnInit', 'Invalid session code in URL, clearing');
              }
              if (storedSessionCode && !this.sessionService.isValidSessionCode(storedSessionCode)) {
                this.logger.warn('ngOnInit', 'Invalid session code in localStorage, clearing');
                this.clearSessionCode();
              }
              this.chatService.clearMessages();
              this.messages = [];
              this.metaService.updateChatMetadata(false);
            }
            this.cdr.detectChanges();
            return;
          }

          // Subsequent emission: in-app navigation between sessions.
          const newCode =
            sessionCode && this.sessionService.isValidSessionCode(sessionCode)
              ? this.sessionService.sanitizeSessionCode(sessionCode)
              : null;
          const currentCode = this.SessionCode || null;
          if (newCode !== currentCode) {
            this.isNavigatingIntentionally = true;
            void this.enterSession(newCode);
          }
        });
      })
    );

    // Listen to changes in the user's name
    this.subscriptions.push(
      this.userService.user$.subscribe((username: unknown) => {
        if (username) {
          this.ngZone.run(() => {
            this.logger.info('ngOnInit', `Username is set to: ${username}`);
            this.initializeChat();
          });
        }
      })
    );

    // Load theme preference from localStorage
    const themePreference = localStorage.getItem(THEME_PREFERENCE_KEY);
    this.isDarkMode = themePreference === 'dark';
    this.applyTheme(this.isDarkMode);

    // Get current language from language service
    this.currentLanguage = this.languageService.getCurrentLanguage();
    this.logger.debug(
      'ngOnInit',
      'Chat component - initial currentLanguage:',
      this.currentLanguage
    );

    // Add a small delay to ensure language service has fully initialized
    setTimeout(() => {
      this.currentLanguage = this.languageService.getCurrentLanguage();
      this.logger.debug(
        'ngOnInit',
        'Chat component - currentLanguage after timeout:',
        this.currentLanguage
      );
      this.cdr.detectChanges();
    }, 100);
  }

  /**
   * ==========================================================
   * LIFECYCLE HOOK: NGONDESTROY
   * Cleans up all subscriptions and closes any WebRTC connections
   * when the component is torn down.
   * ==========================================================
   */
  ngOnDestroy(): void {
    this.unsubscribeAll();
    this.closeConnections();
    this.clearMessages();

    for (const url of this.createdPreviewUrls) {
      try {
        URL.revokeObjectURL(url);
      } catch (e) {
        this.logger.warn('ngOnDestroy', 'Failed to revoke preview URL', e as unknown);
      }
    }
    this.createdPreviewUrls = [];

    if (!this.isNavigatingIntentionally && this.SessionCode) {
      this.clearSessionCode();
    }

    this.heartbeatService.stop();

    // Clear all connection initialization timeouts
    this.connectionInitTimeouts.forEach((timeout) => clearTimeout(timeout));
    this.connectionInitTimeouts = [];

    // Clear navigation timeout
    if (this.navigationTimeout) {
      clearTimeout(this.navigationTimeout);
      this.navigationTimeout = null;
    }

    // Clear status check interval
    if (this.statusCheckIntervalId) {
      clearInterval(this.statusCheckIntervalId);
      this.statusCheckIntervalId = null;
      this.logger.debug('ngOnDestroy', 'Status check interval cleared');
    }

    // Clear connection warning timeouts
    for (const timeoutId of this.connectionWarningTimeouts.values()) {
      clearTimeout(timeoutId);
    }
    this.connectionWarningTimeouts.clear();

    if (isPlatformBrowser(this.platformId) && this.visibilityChangeListener) {
      document.removeEventListener('visibilitychange', this.visibilityChangeListener);
    }

    if (isPlatformBrowser(this.platformId) && this.beforeUnloadHandler) {
      window.removeEventListener('beforeunload', this.beforeUnloadHandler);
    }
  }

  /**
   * ==========================================================
   * UNSUBSCRIBE ALL
   * Cleans up all subscriptions to prevent memory leaks.
   * ==========================================================
   */
  unsubscribeAll(): void {
    this.subscriptions.forEach((subscription) => {
      subscription.unsubscribe();
    });
    this.subscriptions = [];
  }

  /**
   * ==========================================================
   * CLEAR MESSAGES
   * Clears the chat messages and resets the local messages array.
   * ==========================================================
   */
  clearMessages(): void {
    this.chatService.clearMessages();
    this.messages = [];
  }

  /**
   * ==========================================================
   * CLOSE ALL CONNECTIONS
   * Closes all WebRTC connections and disconnects the WebSocket.
   * ==========================================================
   */
  closeConnections(): void {
    this.webrtcService.closeAllConnections();
    this.wsConnectionService.disconnect(!this.isNavigatingIntentionally);
    this.logger.debug('closeConnections', 'All WebRTC connections closed');
  }

  /**
   * ==========================================================
   * HEARTBEAT MONITOR
   * Subscribes to HeartbeatService.suspended$ and reacts to suspensions
   * by warning the user and forcing a page reload.
   * ==========================================================
   */
  private startHeartbeatMonitor(): void {
    this.subscriptions.push(
      this.heartbeatService.suspended$.subscribe(() => {
        this.toaster.warning(this.translate.instant('AUTO_REFRESH_NOTICE'));
        if (isPlatformBrowser(this.platformId)) {
          setTimeout(() => {
            window.location.reload();
          }, 2000);
        }
      })
    );
    this.heartbeatService.start();
  }

  /**
   * ==========================================================
   * LANGUAGE SWITCHER
   * Allows runtime switching between English and Arabic.
   * ==========================================================
   */
  switchLanguage(language: string) {
    this.ngZone.run(() => {
      const languageCode = language as LanguageCode;
      this.languageService.setLanguagePreference(languageCode);
      this.currentLanguage = languageCode;
      this.skipDrawerAnim = true;
      setTimeout(() => (this.skipDrawerAnim = false), 100);
      this.cdr.detectChanges();
    });
  }

  /**
   * ==========================================================
   * HANDLE ENTER KEY
   * Prevents default behavior if shift isn't pressed
   * and sends the message instead.
   * ==========================================================
   */
  onEnterKey(event: KeyboardEvent, messageForm: NgForm): void {
    if (!event.shiftKey) {
      event.preventDefault();
      if (!this.isSendDisabled) {
        void this.sendMessage(messageForm);
      }
    }
  }

  /**
   * ==========================================================
   * AUTO RESIZE TEXTAREA
   * Automatically adjusts textarea height based on content
   * with a maximum height limit
   * ==========================================================
   */
  protected autoResizeTextarea(): void {
    if (!isPlatformBrowser(this.platformId) || !this.messageTextarea?.nativeElement) {
      return;
    }

    const textarea = this.messageTextarea.nativeElement;
    const maxHeight = 120;
    const minHeight = 40;

    textarea.style.height = 'auto';
    const newHeight = Math.min(Math.max(textarea.scrollHeight, minHeight), maxHeight);
    textarea.style.height = newHeight + 'px';

    if (textarea.scrollHeight > maxHeight) {
      textarea.style.overflowY = 'auto';
    } else {
      textarea.style.overflowY = 'hidden';
    }
  }

  /**
   * ==========================================================
   * INITIALIZE CHAT
   * Subscribes to relevant observables and updates local
   * properties to reflect chat state (messages, rooms, etc.).
   * ==========================================================
   */
  private initializeChat() {
    // Listen for new messages
    this.subscriptions.push(
      this.chatService.messages$.subscribe((messages: ChatMessage[]) => {
        this.ngZone.run(() => {
          const previousLength = this.lastMessagesLength;
          this.messages = [...messages];
          this.cdr.detectChanges();

          // Auto-scroll only when new messages are added, not when items are edited in place
          if (this.messages.length > previousLength) {
            this.scrollToBottom();
          }

          this.lastMessagesLength = this.messages.length;
        });
      })
    );

    // Listen for available rooms
    this.subscriptions.push(
      this.roomService.rooms$.subscribe((rooms: string[]) => {
        this.ngZone.run(() => {
          this.rooms = rooms;
          this.cdr.detectChanges();
        });
      })
    );

    // Listen for current members in the room
    this.subscriptions.push(
      this.roomService.members$.subscribe((allMembers: string[]) => {
        this.ngZone.run(() => {
          // Filter out the local user's own name
          this.members = allMembers.filter((m) => m !== this.userService.user);

          // Clean up timeouts for members who left
          for (const [member, timeoutId] of this.connectionWarningTimeouts.entries()) {
            if (!this.members.includes(member)) {
              clearTimeout(timeoutId);
              this.connectionWarningTimeouts.delete(member);
            }
          }

          // For new members, start a warning timeout
          this.members.forEach((member) => {
            if (!this.memberConnectionStatus.has(member)) {
              this.memberConnectionStatus.set(member, false);
              this.scheduleConnectionWarning(member);
            }
          });

          this.cdr.detectChanges();
          this.initiateConnectionsWithMembers();
        });
      })
    );

    // Listen for active file uploads
    this.subscriptions.push(
      this.fileTransferService.activeUploads$.subscribe((uploads: FileUpload[]) => {
        this.logger.info('activeUploads', `Active uploads: ${uploads.length} (length)`);
        this.ngZone.run(() => {
          this.activeUploads = uploads;
          this.cdr.detectChanges();
        });
      })
    );

    // Listen for active file downloads
    this.subscriptions.push(
      this.fileTransferService.activeDownloads$.subscribe((downloads: FileDownload[]) => {
        this.logger.info('activeDownloads', `Active downloads: ${downloads.length} (length)`);
        this.ngZone.run(() => {
          this.activeDownloads = downloads;
          const currentMessages = this.chatService.messages$.value;
          const updatedMessages = currentMessages.map((msg) => {
            if (msg.type === ChatMessageType.ATTACHMENT && msg.fileTransfer) {
              const fileTransfer = msg.fileTransfer;
              const match =
                fileTransfer &&
                downloads.find(
                  (d) => d.fileId === fileTransfer.fileId && d.fromUser === fileTransfer.fromUser
                );
              if (match && match.previewDataUrl) {
                return {
                  ...msg,
                  previewUrl: match.previewDataUrl,
                  previewMime: match.previewMime,
                };
              }
            }
            return msg;
          });
          this.chatService.replaceMessages(updatedMessages);
          this.cdr.detectChanges();
        });
      })
    );

    // When a peer disconnects after being connected, restart warning timeout
    this.subscriptions.push(
      this.webrtcService.peerDisconnected$.subscribe((member) => {
        this.ngZone.run(() => {
          this.memberConnectionStatus.set(member, false);
          this.scheduleConnectionWarning(member);
          this.cdr.detectChanges();
        });
      })
    );

    // When a peer connects, cancel its warning timeout and hide banner if all peers are up
    this.subscriptions.push(
      this.webrtcService.peerConnected$.subscribe((member) => {
        this.ngZone.run(() => {
          this.memberConnectionStatus.set(member, true);
          this.clearConnectionWarning(member);
          this.cdr.detectChanges();
        });
      })
    );

    // Listen for incoming file offers
    this.subscriptions.push(
      this.fileTransferService.incomingFileOffers$.subscribe((incomingFiles: FileDownload[]) => {
        this.logger.info(
          'incomingFileOffers',
          `Incoming file offers: ${incomingFiles.length} (length)`
        );
        this.ngZone.run(() => {
          const currentMessages = this.chatService.messages$.value;
          let updatedMessages = [...currentMessages];

          // Mark any pending file-offer messages as cancelled if they are no longer in incoming offers
          const incomingIds = new Set(incomingFiles.map((f) => f.fileId));
          updatedMessages = updatedMessages.map((msg) => {
            if (
              msg.type === ChatMessageType.ATTACHMENT &&
              msg.fileTransfer?.status === FileTransferStatus.PENDING &&
              !incomingIds.has(msg.fileTransfer.fileId)
            ) {
              const cancelledText = `${msg.fileTransfer.fileName} - ${this.translate.instant('FILE_UPLOAD_CANCELLED')}`;
              return {
                ...msg,
                text: cancelledText,
                fileTransfer: {
                  ...msg.fileTransfer,
                  status: FileTransferStatus.DECLINED,
                },
              };
            }
            return msg;
          });

          incomingFiles.forEach((fileDownload: FileDownload) => {
            // Check if we already have a message for this file
            const existingIndex = updatedMessages.findIndex(
              (msg) =>
                msg.type === ChatMessageType.ATTACHMENT &&
                msg.fileTransfer?.fileId === fileDownload.fileId
            );

            if (existingIndex === -1) {
              // Create message directly from file offer (with preview)
              updatedMessages.push({
                from: fileDownload.fromUser,
                text: fileDownload.fileName,
                type: ChatMessageType.ATTACHMENT,
                timestamp: new Date(),
                previewUrl: fileDownload.previewDataUrl,
                previewMime: fileDownload.previewMime,
                fileTransfer: {
                  fileId: fileDownload.fileId,
                  fileName: fileDownload.fileName,
                  fileSize: fileDownload.fileSize,
                  fromUser: fileDownload.fromUser,
                  status: FileTransferStatus.PENDING,
                },
              });
            } else {
              // Update existing message with preview if available
              if (!updatedMessages[existingIndex].previewUrl && fileDownload.previewDataUrl) {
                updatedMessages[existingIndex] = {
                  ...updatedMessages[existingIndex],
                  previewUrl: fileDownload.previewDataUrl,
                  previewMime: fileDownload.previewMime,
                };
              }
            }
          });

          this.chatService.replaceMessages(updatedMessages);
          this.cdr.detectChanges();
        });
      })
    );
  }

  /**
   * ==========================================================
   * LIFECYCLE HOOK: NGAFTERVIEWINIT
   * Called after view initialization to handle focus, route
   * checks (if no code, default to main session).
   * ==========================================================
   */
  ngAfterViewInit(): void {
    if (!isPlatformBrowser(this.platformId)) return;

    if (this.SessionCode) {
      this.connect(this.SessionCode);
    } else {
      void this.connect();
    }

    document.addEventListener('visibilitychange', this.visibilityChangeListener);
    window.addEventListener('beforeunload', this.beforeUnloadHandler);

    this.cdr.detectChanges();
    if (this.messageInput?.nativeElement) {
      this.messageInput.nativeElement.focus();
    }

    requestAnimationFrame(() => {
      this.autoResizeTextarea();
    });
  }

  /**
   * ==========================================================
   * THEME TOGGLER
   * Toggles between dark and light modes, applying CSS classes.
   * ==========================================================
   */
  toggleTheme(): void {
    this.ngZone.run(() => {
      this.isDarkMode = !this.isDarkMode;
      this.themeService.setThemePreference(this.isDarkMode);
      this.applyTheme(this.isDarkMode);
      this.cdr.detectChanges();
    });
  }

  /**
   * ==========================================================
   * APPLY THEME
   * Sets the <html> data-theme attribute to "dark" or "light".
   * ==========================================================
   */
  private applyTheme(isDarkMode: boolean): void {
    if (typeof document !== 'undefined') {
      const htmlElement = document.documentElement;
      if (isDarkMode) {
        htmlElement.classList.add('dark');
        htmlElement.setAttribute('data-theme', 'dark');
      } else {
        htmlElement.classList.remove('dark');
        htmlElement.setAttribute('data-theme', 'light');
      }
    }
  }

  /**
   * ==========================================================
   * CONNECT
   * Establishes a WebSocket connection to a session (if provided).
   * Upon success, lists rooms and grabs the username.
   * ==========================================================
   */
  connect(code?: string): Promise<void> {
    // Store session code in component for later reconnection
    if (code) {
      this.SessionCode = code;
    }

    if (this.wsConnectionService.isConnected()) {
      this.logger.debug('connect', 'Already connected, skipping connection');
      return Promise.resolve();
    }

    return this.wsConnectionService
      .connect(code)
      .then(() => {
        this.logger.info('connect', `Connected to session: ${code ?? 'No code provided'}`);
        this.roomService.listRooms();
        this.chatService.getUsername();
        if (code) {
          this.toaster.success(this.translate.instant('CONNECTED_TO_PRIVATE_SESSION'));
        }
      })
      .catch((error: unknown) => {
        this.logger.error('connect', `WebSocket connection failed: ${error}`);
        throw error;
      });
  }

  /**
   * ==========================================================
   * ENTER SESSION
   * Single point of state-transition: tears down everything related
   * to the current session, updates SessionCode + storage + metadata,
   * then connects to the new one. Called by the paramMap subscription
   * whenever the route's :code segment changes after initial bootstrap.
   * ==========================================================
   */
  private async enterSession(code: string | null): Promise<void> {
    if (!isPlatformBrowser(this.platformId)) return;

    this.logger.info('enterSession', `Switching to session: ${code ?? 'public'}`);

    // ---- Tear down previous session ----
    this.webrtcService.closeAllConnections();
    this.wsConnectionService.disconnect();

    this.connectionInitTimeouts.forEach((id) => clearTimeout(id));
    this.connectionInitTimeouts = [];
    this.connectionWarningTimeouts.forEach((id) => clearTimeout(id));
    this.connectionWarningTimeouts.clear();
    if (this.statusCheckIntervalId) {
      clearInterval(this.statusCheckIntervalId);
      this.statusCheckIntervalId = null;
    }

    this.roomService.reset();
    this.chatService.clearMessages();

    this.messages = [];
    this.members = [];
    this.rooms = [];
    this.activeUploads = [];
    this.activeDownloads = [];
    this.memberConnectionStatus.clear();
    this.showConnectionWarning = false;
    this.connectionWarningDismissed = false;
    this.currentRoom = 'main';
    this.overrideRecipients = null;
    this.lastMessagesLength = 0;

    // ---- Update session code (memory + storage + meta) ----
    if (code) {
      const sanitized = this.sessionService.sanitizeSessionCode(code);
      this.SessionCode = sanitized;
      localStorage.setItem(SESSION_CODE_KEY, sanitized);
      this.metaService.updateChatMetadata(true);
    } else {
      this.SessionCode = '';
      localStorage.removeItem(SESSION_CODE_KEY);
      this.metaService.updateChatMetadata(false);
    }

    this.cdr.detectChanges();

    // ---- Connect to the new session ----
    try {
      await this.connect(this.SessionCode || undefined);
    } catch (err) {
      this.logger.error('enterSession', `Failed to connect to new session: ${err}`);
    } finally {
      // Settle the navigation intent so beforeUnload semantics remain correct
      // for whatever the user does next.
      this.isNavigatingIntentionally = false;
    }
  }

  /**
   * ==========================================================
   * SEND MESSAGE
   * Sends the chat message to other members via WebRTC, then clears
   * the input field and scrolls chat down.
   * ==========================================================
   */
  async sendMessage(messageForm: NgForm): Promise<void> {
    if (this.message.trim()) {
      const otherMembers = this.members.filter((m) => m !== this.userService.user);
      if (otherMembers.length === 0) {
        this.toaster.warning(this.translate.instant('NO_MEMBERS_TO_SEND_MESSAGE'));
        return;
      }

      const messageText = this.message;
      let hasSuccessfulSend = false;

      // Wait for all send operations to complete
      const sendPromises = otherMembers.map(async (member) => {
        try {
          await this.chatService.sendMessage(messageText, member, ChatMessageType.TEXT);
          hasSuccessfulSend = true;
          return { member, success: true };
        } catch (error) {
          this.logger.error('sendMessage', `Failed to send message to ${member}: ${error}`);
          this.toaster.error(this.translate.instant('FAILED_TO_SEND_MESSAGE', { member }));
          return { member, success: false };
        }
      });

      await Promise.all(sendPromises);

      // Only add to local chat if at least one send was successful
      if (hasSuccessfulSend) {
        this.chatService.addMessageToLocal(messageText, ChatMessageType.TEXT);
      }

      this.ngZone.run(() => {
        this.message = '';
        messageForm.resetForm({ message: '' });
        this.cdr.detectChanges();
        this.scrollToBottom();
        requestAnimationFrame(() => {
          this.autoResizeTextarea();
        });
      });
    } else {
      this.toaster.warning(this.translate.instant('MESSAGE_REQUIRED'));
    }
  }

  /**
   * ==========================================================
   * TRUNCATE FILENAME
   * Truncates a filename while preserving the file extension
   * ==========================================================
   */
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

  /**
   * ==========================================================
   * CREATE FILE MESSAGES (LOCAL)
   * Creates local chat messages for files being sent (sender-side only).
   * Recipients create their own messages from the file offer directly.
   * ==========================================================
   */
  private async createLocalFileMessages(files: File[]): Promise<void> {
    for (const file of files) {
      const truncatedFilename = this.truncateFilename(file.name);
      const fileSizeLabel = this.fileSizePipe.transform(file.size, 2);
      const fileMessageText = `${this.translate.instant('FILE_SENT')}: ${truncatedFilename} (${fileSizeLabel})`;

      // Add message locally for the sender (with preview)
      let previewUrl: string | undefined;
      let previewMime: string | undefined;
      const mime = file.type || '';
      if (mime.startsWith('image/')) {
        try {
          previewUrl = URL.createObjectURL(file);
          this.createdPreviewUrls.push(previewUrl);
          previewMime = mime;
        } catch (e) {
          this.logger.warn('createPreview', 'Failed to create image preview URL', e as unknown);
        }
      } else if (mime === 'application/pdf') {
        try {
          const thumb = await this.previewService.createPdfThumbnailFromFile(file);
          if (thumb) {
            previewUrl = thumb;
            previewMime = PREVIEW_MIME_TYPE;
          }
        } catch (e) {
          this.logger.warn('createPreview', 'Failed to create PDF thumbnail', e as unknown);
        }
      }

      this.chatService.addMessageToLocal(fileMessageText, ChatMessageType.ATTACHMENT, {
        previewUrl,
        previewMime,
      });
    }
  }

  /**
   * ==========================================================
   * SEND ATTACHMENTS
   * Triggers file sending to other users via FileTransferService.
   * Attempts to establish WebRTC connections if not already open.
   * ==========================================================
   */
  async sendAttachments(event: Event): Promise<void> {
    const input = event.target as HTMLInputElement;
    if (input.files && input.files.length > 0) {
      const filesToSend = Array.from(input.files);

      const defaultRecipients = this.members.filter((m) => m !== this.userService.user);
      const recipients =
        this.overrideRecipients && this.overrideRecipients.length > 0
          ? this.overrideRecipients
          : defaultRecipients;

      if (recipients.length === 0) {
        this.toaster.warning(this.translate.instant('NO_USERS_FOR_UPLOAD'));
        this.overrideRecipients = null;
        return;
      }

      // Create local chat messages for each file being sent
      await this.createLocalFileMessages(filesToSend);

      // First prepare all files for all recipients
      for (const fileToSend of filesToSend) {
        for (const member of recipients) {
          await this.fileTransferService.prepareFileForSending(fileToSend, member);
          if (!this.webrtcService.isConnectedOrConnecting(member)) {
            this.logger.info(
              'sendAttachments',
              `Initiating connection to ${member} for file transfer`
            );
            this.webrtcService.initiateConnection(member);
          }
        }
      }

      // Then send all file offers once per recipient
      for (const member of recipients) {
        const connectionReady = await this.waitForFileTransferConnection(member);
        if (connectionReady) {
          await this.fileTransferService.sendAllFileOffers(member);
          this.logger.debug('sendAttachments', `Sent ${filesToSend.length} files to ${member}`);
        }
      }

      input.value = '';
      this.overrideRecipients = null;
    } else {
      this.toaster.warning(this.translate.instant('NO_FILES_SELECTED'));
    }
  }

  /**
   * ==========================================================
   * OPEN FILE PICKER FOR SPECIFIC USER
   * Triggers hidden input to choose files and target a single user.
   * ==========================================================
   */
  openFilePickerForMember(member: string): void {
    this.overrideRecipients = [member];
    if (this.fileInput?.nativeElement) {
      this.fileInput.nativeElement.value = '';
      this.fileInput.nativeElement.click();
    }
  }

  /**
   * ==========================================================
   * ACCEPT INCOMING FILE
   * User confirms file download from another user.
   * ==========================================================
   */
  public async acceptIncomingFile(message: ChatMessage): Promise<void> {
    if (!message.fileTransfer) return;

    await this.fileTransferService.acceptFileOffer(
      message.fileTransfer.fromUser,
      message.fileTransfer.fileId
    );

    // Update the message status and text
    this.updateFileTransferMessageStatus(message.fileTransfer.fileId, FileTransferStatus.ACCEPTED);
  }

  /**
   * ==========================================================
   * DECLINE INCOMING FILE
   * User declines file transfer request from another user.
   * ==========================================================
   */
  public async declineIncomingFile(message: ChatMessage): Promise<void> {
    if (!message.fileTransfer) return;

    await this.fileTransferService.declineFileOffer(
      message.fileTransfer.fromUser,
      message.fileTransfer.fileId
    );

    // Update the message status and text
    this.updateFileTransferMessageStatus(message.fileTransfer.fileId, FileTransferStatus.DECLINED);
  }

  /**
   * ==========================================================
   * UPDATE FILE TRANSFER MESSAGE STATUS
   * Updates the status and text of a file transfer message
   * ==========================================================
   */
  private updateFileTransferMessageStatus(
    fileId: string,
    status: FileTransferStatus.ACCEPTED | FileTransferStatus.DECLINED
  ): void {
    const currentMessages = this.chatService.messages$.value;
    const updatedMessages = currentMessages.map((msg) => {
      if (msg.type === ChatMessageType.ATTACHMENT && msg.fileTransfer?.fileId === fileId) {
        const statusText =
          status === FileTransferStatus.ACCEPTED
            ? this.translate.instant('FILE_TRANSFER_ACCEPTED')
            : this.translate.instant('FILE_TRANSFER_DECLINED');
        const fileSizeLabel = this.fileSizePipe.transform(msg.fileTransfer.fileSize, 2);

        return {
          ...msg,
          text: `${this.truncateFilename(msg.fileTransfer.fileName)} (${fileSizeLabel}) - ${statusText}`,
          fileTransfer: {
            ...msg.fileTransfer,
            status,
          },
        };
      }
      return msg;
    });

    this.chatService.replaceMessages(updatedMessages);
  }

  /**
   * ==========================================================
   * CANCEL UPLOAD
   * Invoked by the user to cancel an ongoing file upload.
   * ==========================================================
   */
  public async cancelUpload(upload: FileUpload): Promise<void> {
    await this.fileTransferService.stopFileUpload(upload.targetUser, upload.fileId);
  }

  /**
   * ==========================================================
   * CANCEL DOWNLOAD
   * Invoked by the user to cancel an ongoing file download.
   * ==========================================================
   */
  public async cancelDownload(download: FileDownload): Promise<void> {
    await this.fileTransferService.cancelFileDownload(download.fromUser, download.fileId);
  }

  /**
   * ==========================================================
   * JOIN ROOM
   * Joins a given chat room if it's not the current one.
   * ==========================================================
   */
  joinRoom(room: string): void {
    if (room !== this.currentRoom) {
      this.ngZone.run(() => {
        this.roomService.joinRoom(room);
        this.roomService.listRooms();
        this.currentRoom = room;
        this.isMenuOpen = false;
        this.toaster.success(this.translate.instant('ROOM_JOINED_SUCCESS', { roomName: room }));
        this.cdr.detectChanges();
      });
    } else {
      this.logger.debug('joinRoom', `User already in room: ${room}`);
    }
  }

  /**
   * ==========================================================
   * OPEN CREATE ROOM POPUP
   * Opens the create room popup with proper DOM timing.
   * ==========================================================
   */
  openCreateRoomPopup(): void {
    this.isOpenCreateRoom = true;
    this.cdr.detectChanges();
    requestAnimationFrame(() => {
      const input = document.querySelector(
        'input[ng-reflect-model="newRoomName"]'
      ) as HTMLInputElement;
      input?.focus();
    });
  }

  /**
   * ==========================================================
   * OPEN JOIN SESSION POPUP
   * Opens the join session popup with proper DOM timing.
   * ==========================================================
   */
  openJoinSessionPopup(): void {
    this.isOpenJoinSessionPopup = true;
    this.cdr.detectChanges();
    requestAnimationFrame(() => {
      const input = document.querySelector(
        'input[ng-reflect-model="newSessionCode"]'
      ) as HTMLInputElement;
      input?.focus();
    });
  }

  /**
   * ==========================================================
   * OPEN END SESSION POPUP
   * Opens the end session popup with proper DOM timing.
   * ==========================================================
   */
  openEndSessionPopup(): void {
    this.isOpenEndSessionPopup = true;
    this.cdr.detectChanges();
  }

  /**
   * ==========================================================
   * CLOSE POPUP
   * Closes any popup with proper DOM timing.
   * ==========================================================
   */
  closePopup(popupType: 'create' | 'join' | 'end' | 'qr'): void {
    requestAnimationFrame(() => {
      switch (popupType) {
        case 'create':
          this.isOpenCreateRoom = false;
          this.newRoomName = '';
          break;
        case 'join':
          this.isOpenJoinSessionPopup = false;
          this.newSessionCode = '';
          break;
        case 'end':
          this.isOpenEndSessionPopup = false;
          break;
        case 'qr':
          this.isOpenQRCodePopup = false;
          break;
      }
      this.cdr.detectChanges();
    });
  }

  /**
   * ==========================================================
   * CREATE ROOM
   * Creates or joins a new room based on the room name input.
   * ==========================================================
   */
  createRoom(): void {
    if (this.newRoomName.trim() && this.newRoomName !== this.currentRoom) {
      this.joinRoom(this.newRoomName.trim());
      this.ngZone.run(() => {
        this.newRoomName = '';
        requestAnimationFrame(() => {
          this.isOpenCreateRoom = false;
          this.cdr.detectChanges();
        });
      });
    } else {
      this.toaster.warning(this.translate.instant('ENTER_VALID_ROOM'));
    }
  }

  /**
   * ==========================================================
   * CREATE PRIVATE SESSION
   * Requests a new session code from the server, then navigates to it.
   * ==========================================================
   */
  createPrivateSession(): void {
    this.sessionService.createNewSessionCode().subscribe({
      next: (res) => {
        this.ngZone.run(() => {
          const code = res.code;
          this.openChatSession(code);
          this.cdr.detectChanges();
        });
      },
      error: (err) => {
        this.logger.error('createPrivateSession', 'Failed to create new session code:', err);
        this.toaster.error(this.translate.instant('SESSION_CREATION_FAILED'));
      },
    });
  }

  /**
   * ==========================================================
   * JOIN PRIVATE SESSION
   * Navigates to an existing session code entered by the user.
   * ==========================================================
   */
  joinPrivateSession(): void {
    const code = this.newSessionCode.trim();
    this.ngZone.run(() => {
      this.cdr.detectChanges();
    });
    if (!code) {
      this.logger.error('joinPrivateSession', 'Session code is required to join a session.');
      return;
    }

    if (!this.sessionService.isValidSessionCode(code)) {
      this.logger.error('joinPrivateSession', 'Invalid session code format');
      this.toaster.error(this.translate.instant('INVALID_SESSION_CODE_FORMAT'));
      return;
    }

    requestAnimationFrame(() => {
      this.isOpenJoinSessionPopup = false;
      this.newSessionCode = '';
      this.cdr.detectChanges();
      this.openChatSession(code);
    });
  }

  /**
   * ==========================================================
   * END SESSION
   * Navigates to an existing session code entered by the user.
   * ==========================================================
   */
  endSession(): void {
    requestAnimationFrame(() => {
      this.isOpenEndSessionPopup = false;
      this.cdr.detectChanges();
      this.toaster.success(this.translate.instant('SESSION_ENDED_SUCCESS'));
      // paramMap subscription detects the code change and calls enterSession(null),
      // which tears down WebRTC/WS and reconnects to public.
      void this.router.navigateByUrl('/');
    });
  }

  /**
   * ==========================================================
   * OPEN CHAT SESSION
   * Validates the code and triggers SPA navigation to /private/:code.
   * The actual session-state teardown and reconnection is handled by
   * the paramMap subscription -> enterSession() flow, so this method
   * is only responsible for the navigation itself.
   * ==========================================================
   */
  private openChatSession(code: string): void {
    if (!this.sessionService.isValidSessionCode(code)) {
      this.logger.error('openChatSession', 'Invalid session code format, navigation aborted');
      this.toaster.error(this.translate.instant('INVALID_SESSION_CODE_FORMAT'));
      return;
    }

    if (!isPlatformBrowser(this.platformId)) return;

    const sanitizedCode = this.sessionService.sanitizeSessionCode(code);
    if (sanitizedCode === this.SessionCode) {
      this.logger.debug('openChatSession', `Already in session: ${sanitizedCode}`);
      return;
    }

    this.logger.debug('openChatSession', `Opening chat session with code: ${sanitizedCode}`);

    if (this.navigationTimeout) {
      clearTimeout(this.navigationTimeout);
    }

    // Small delay so the popup close animation and toast can render before
    // the URL change kicks off the session-transition pipeline.
    this.navigationTimeout = setTimeout(() => {
      this.navigationTimeout = null;
      void this.router.navigateByUrl(`/private/${sanitizedCode}`);
    }, NAVIGATION_DELAY_MS);
  }

  /**
   * ==========================================================
   * COPY SESSION CODE
   * Copies the current session code to the user's clipboard.
   * ==========================================================
   */
  copySessionCode(): void {
    if (!this.SessionCode) {
      this.toaster.warning(this.translate.instant('NO_SESSION_TO_COPY'));
      return;
    }

    navigator.clipboard.writeText(this.SessionCode).then(
      () => this.toaster.success(this.translate.instant('COPY_SESSION_SUCCESS')),
      (err) => {
        this.logger.error('copySessionCode', 'Failed to copy session code:', err);
        this.toaster.error(this.translate.instant('COPY_SESSION_FAILED'));
      }
    );
  }

  /**
   * ==========================================================
   * GET SESSION URL
   * Returns the full URL for the current session (used by QR popup).
   * ==========================================================
   */
  protected get sessionUrl(): string {
    if (!this.SessionCode || !isPlatformBrowser(this.platformId)) {
      return '';
    }
    return `${window.location.origin}/private/${this.SessionCode}`;
  }

  /**
   * ==========================================================
   * OPEN QR CODE POPUP
   * Opens the QR code popup; the popup itself handles generation.
   * ==========================================================
   */
  openQRCodePopup(): void {
    this.isOpenQRCodePopup = true;
    this.cdr.detectChanges();
  }

  /**
   * ==========================================================
   * CLEAR SESSION CODE
   * Removes the session code from localStorage and resets
   * the SessionCode property.
   * =========================================================
   */
  private clearSessionCode(): void {
    if (isPlatformBrowser(this.platformId)) {
      localStorage.removeItem(SESSION_CODE_KEY);
    }

    this.SessionCode = '';
  }

  /**
   * ==========================================================
   * WAIT FOR FILE TRANSFER CONNECTION
   * Waits for WebRTC connection to be ready for file transfer with retry logic
   * ==========================================================
   */
  private async waitForFileTransferConnection(member: string): Promise<boolean> {
    const maxRetries = 50; // 5 seconds total (50 * 100ms)
    let retryCount = 0;

    while (retryCount < maxRetries) {
      if (this.webrtcService.isReadyForFileTransfer(member)) {
        return true;
      }

      if (!this.webrtcService.isConnectedOrConnecting(member)) {
        this.webrtcService.initiateConnection(member);
      }

      retryCount++;
      await new Promise((resolve) => setTimeout(resolve, 100));
    }

    this.logger.warn(
      'waitForFileTransferConnection',
      `File transfer connection timeout with user: ${member} after ${retryCount} retries`
    );
    return false;
  }

  /**
   * ==========================================================
   * INITIATE CONNECTIONS WITH ROOM MEMBERS
   * Attempts to open a WebRTC connection with each peer.
   * Updates connection status indicators.
   * ==========================================================
   */
  private initiateConnectionsWithMembers(): void {
    if (!this.members || this.members.length === 0) {
      this.logger.info(
        'initiateConnectionsWithMembers',
        'No members in the room, skipping WebRTC.'
      );
      return;
    }

    // Clear any existing connection initialization timeouts
    this.connectionInitTimeouts.forEach((timeout) => clearTimeout(timeout));
    this.connectionInitTimeouts = [];

    this.logger.info('initiateConnectionsWithMembers', 'Initiating connections with other members');

    // Filter out self AND already connected/connecting peers
    const otherMembers = this.members.filter((m) => {
      if (m === this.userService.user) {
        return false;
      }

      // Skip if already connected or connecting
      const isConnectedOrConnecting = this.webrtcService.isConnectedOrConnecting(m);
      if (isConnectedOrConnecting) {
        this.logger.debug(
          'initiateConnectionsWithMembers',
          `Skipping ${m} - already connected/connecting`
        );
      }
      return !isConnectedOrConnecting;
    });

    if (otherMembers.length === 0) {
      this.logger.info('initiateConnectionsWithMembers', 'No new members to connect to');
      return;
    }

    // Stagger connection initiation to prevent race conditions
    // Callers initiate immediately, callees wait to give callers time to send offers
    otherMembers.forEach((member, index) => {
      // Determine if we should be the caller for this member
      const shouldInitiate = this.userService.user.localeCompare(member) < 0;

      // Callers start at 1000ms, callees wait an additional 500ms
      const baseDelay = 1000;
      const staggerDelay = shouldInitiate ? 0 : 500;
      const indexDelay = index * 100; // Small delay between multiple members

      const timeoutId = setTimeout(
        () => {
          this.webrtcService.initiateConnection(member);

          // Check connection status after a delay
          const statusCheckTimeoutId = setTimeout(() => {
            const isConnected = this.webrtcService.isConnected(member);
            this.ngZone.run(() => {
              this.memberConnectionStatus.set(member, isConnected);
              this.cdr.detectChanges();
            });
          }, 2000); // Check after 2 seconds (connection usually establishes within 1-2s)

          this.connectionInitTimeouts.push(statusCheckTimeoutId);
        },
        baseDelay + staggerDelay + indexDelay
      );

      this.connectionInitTimeouts.push(timeoutId);
    });

    // Clear any existing status check interval before creating a new one
    if (this.statusCheckIntervalId) {
      clearInterval(this.statusCheckIntervalId);
      this.statusCheckIntervalId = null;
    }

    // Periodically sync connection status map for the UI (red/green circles)
    this.statusCheckIntervalId = setInterval(() => {
      if (this.members.length === 0) {
        if (this.statusCheckIntervalId) {
          clearInterval(this.statusCheckIntervalId);
          this.statusCheckIntervalId = null;
        }
        return;
      }

      this.ngZone.run(() => {
        const otherMembers = this.members.filter((m) => m !== this.userService.user);

        // Keep the status map in sync for the UI (red/green circles)
        otherMembers.forEach((member) => {
          this.memberConnectionStatus.set(member, this.webrtcService.isConnected(member));
        });

        // Clean up warning timeouts for members who left
        for (const [member, timeoutId] of this.connectionWarningTimeouts.entries()) {
          if (!otherMembers.includes(member)) {
            clearTimeout(timeoutId);
            this.connectionWarningTimeouts.delete(member);
          }
        }

        this.cdr.detectChanges();
      });
    }, 3000);
  }

  /**
   * ==========================================================
   * GET CONNECTION STATUS
   * Returns true if connected via WebRTC, false otherwise
   * ==========================================================
   */
  protected isConnectedToMember(member: string): boolean {
    return this.memberConnectionStatus.get(member) ?? false;
  }

  protected get hasNoConnectedPeers(): boolean {
    const otherMembers = this.members.filter((m) => m !== this.userService.user);
    if (otherMembers.length === 0) return true;
    return !otherMembers.some((m) => this.isConnectedToMember(m));
  }

  protected get isSendDisabled(): boolean {
    return !this.message.trim() || this.hasNoConnectedPeers;
  }

  protected dismissConnectionWarning(): void {
    this.showConnectionWarning = false;
    this.connectionWarningDismissed = true;
    this.cdr.detectChanges();
  }

  protected refreshPage(): void {
    if (isPlatformBrowser(this.platformId)) {
      window.location.reload();
    }
  }

  private scheduleConnectionWarning(member: string): void {
    if (this.connectionWarningTimeouts.has(member)) return;
    const timeoutId = setTimeout(() => {
      this.ngZone.run(() => {
        this.connectionWarningTimeouts.delete(member);
        if (
          this.members.includes(member) &&
          !this.webrtcService.isConnected(member) &&
          !this.connectionWarningDismissed
        ) {
          this.showConnectionWarning = true;
          this.cdr.detectChanges();
        }
      });
    }, CONNECTION_WARNING_DELAY_MS);
    this.connectionWarningTimeouts.set(member, timeoutId);
  }

  private clearConnectionWarning(member: string): void {
    const timeoutId = this.connectionWarningTimeouts.get(member);
    if (timeoutId) {
      clearTimeout(timeoutId);
      this.connectionWarningTimeouts.delete(member);
    }
    // Hide banner if all peers are now connected
    const otherMembers = this.members.filter((m) => m !== this.userService.user);
    if (otherMembers.length > 0 && otherMembers.every((m) => this.webrtcService.isConnected(m))) {
      this.showConnectionWarning = false;
      this.connectionWarningDismissed = false;
    }
  }

  /**
   * ==========================================================
   * SCROLL TO BOTTOM
   * Ensures the latest messages are visible in the chat area.
   * ==========================================================
   */
  private scrollToBottom(): void {
    if (!isPlatformBrowser(this.platformId)) return;
    try {
      const container = this.messageContainer?.nativeElement;
      if (container) {
        container.scrollTop = container.scrollHeight;
      }
    } catch (err) {
      this.logger.error('scrollToBottom', `Could not scroll to bottom: ${err}`);
    }
  }

  /**
   * ==========================================================
   * RTL CHECK
   * Determines if the current language is RTL (e.g., Arabic).
   * ==========================================================
   */
  get isRTL(): boolean {
    if (!isPlatformBrowser(this.platformId)) return false;
    return document.dir === 'rtl' || this.currentLanguage === 'ar';
  }

  /**
   * ==========================================================
   * HANDLE FILES DROPPED
   * Processes files dropped into the chat input area
   * ==========================================================
   */
  protected async handleFilesDropped(files: File[]): Promise<void> {
    const otherMembers = this.members.filter((m) => m !== this.userService.user);

    if (otherMembers.length === 0) {
      this.toaster.info(this.translate.instant('NO_USERS_FOR_UPLOAD'));
      return;
    }

    if (files.length === 0) return;

    // Create local chat messages for each file being sent
    await this.createLocalFileMessages(files);

    // First prepare all files for all members
    for (const fileToSend of files) {
      for (const member of otherMembers) {
        await this.fileTransferService.prepareFileForSending(fileToSend, member);
        if (!this.webrtcService.isConnectedOrConnecting(member)) {
          this.logger.info(
            'handleFilesDropped',
            `Initiating connection to ${member} for file transfer`
          );
          this.webrtcService.initiateConnection(member);
        }
      }
    }

    // Then send all file offers once per member
    for (const member of otherMembers) {
      const connectionReady = await this.waitForFileTransferConnection(member);

      if (connectionReady) {
        await this.fileTransferService.sendAllFileOffers(member);
        this.logger.debug('handleFilesDropped', `Sent ${files.length} files to ${member}`);
      }
    }
  }
}
