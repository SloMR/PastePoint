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
import { combineLatest, Subscription } from 'rxjs';
import { distinctUntilChanged, filter, map } from 'rxjs/operators';
import { isPlatformBrowser } from '@angular/common';

import { ThemeService } from '../../core/services/ui/theme.service';
import { ChatService } from '../../core/services/communication/chat.service';
import { BlockService } from '../../core/services/communication/block.service';
import { buildReportMailto } from '../../utils/report-mailto';
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
  MemberConnectionState,
  MB,
  NAVIGATION_DELAY_MS,
  CONNECTION_WARNING_DELAY_MS,
  SESSION_CODE_KEY,
  THEME_PREFERENCE_KEY,
  PREVIEW_MIME_TYPE,
  SUPPORT_EMAIL,
} from '../../utils/constants';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { SessionService } from '../../core/services/session/session.service';
import packageJson from '../../../../package.json';
import { NGXLogger } from 'ngx-logger';
import { MigrationService } from '../../core/services/migration/migration.service';
import { MetaService } from '../../core/services/ui/meta.service';
import { LanguageService } from '../../core/services/ui/language.service';
import { LanguageCode, getLanguage } from '../../core/i18n/languages';
import { Router } from '@angular/router';
import { HotToastService } from '@ngxpert/hot-toast';
import { PreviewService } from '../../core/services/ui/preview.service';
import { FileSizePipe } from '../../utils/file-size.pipe';
import { middleTruncateFilename as middleTruncateFilenameUtil } from '../../utils/filename.util';
import { JoinSessionPopupComponent } from './components/popups/join-session-popup/join-session-popup.component';
import { CreateRoomPopupComponent } from './components/popups/create-room-popup/create-room-popup.component';
import { EndSessionPopupComponent } from './components/popups/end-session-popup/end-session-popup.component';
import { QrCodePopupComponent } from './components/popups/qr-code-popup/qr-code-popup.component';
import { ConnectionWarningComponent } from './components/connection-warning/connection-warning.component';
import { ServerReconnectComponent } from './components/server-reconnect/server-reconnect.component';
import { ChatInputComponent, StagedAttachment } from './components/chat-input/chat-input.component';
import { ChatMessagesComponent } from './components/chat-messages/chat-messages.component';
import { SplashComponent } from '../../core/components/splash/splash.component';
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
    TranslateModule,
    RouterLink,
    JoinSessionPopupComponent,
    CreateRoomPopupComponent,
    EndSessionPopupComponent,
    QrCodePopupComponent,
    ConnectionWarningComponent,
    ServerReconnectComponent,
    ChatInputComponent,
    ChatMessagesComponent,
    ChatSidebarComponent,
    SplashComponent,
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
  private blockService = inject(BlockService);
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
  protected stagedFiles: StagedAttachment[] = [];
  protected showSplash = true;

  message = '';
  newRoomName = '';
  SessionCode = '';
  newSessionCode = '';

  messages: ChatMessage[] = [];
  rooms: string[] = [];
  members: string[] = [];
  memberConnectionStatus = new Map<string, boolean>(); // true = connected, false = failed
  memberConnectionState = new Map<string, MemberConnectionState>(); // green / yellow / red dot
  showConnectionWarning = false;
  isReconnectingToServer = false;

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
  private isSending = false;
  private isInitialBootstrap = true;
  private currentTransitionId = 0;
  private lastMessagesLength: number = 0;
  private connectionInitTimeouts: ReturnType<typeof setTimeout>[] = [];
  private navigationTimeout: ReturnType<typeof setTimeout> | null = null;
  private statusCheckIntervalId: ReturnType<typeof setInterval> | null = null;
  private connectionWarningDismissed = false;
  private connectionWarningTimeouts = new Map<string, ReturnType<typeof setTimeout>>();
  private themeTransitionTimeout: ReturnType<typeof setTimeout> | null = null;

  appVersion: string = packageJson.version;

  private visibilityChangeListener = () => {
    if (
      document.visibilityState === 'visible' &&
      this.SessionCode &&
      !this.wsConnectionService.isConnected()
    ) {
      this.logger.info('visibilitychange', 'Page visible, reconnecting if needed');
      this.connect(this.SessionCode).catch((err: unknown) => {
        this.logger.warn('visibilitychange', `Reconnect after visibility change failed: ${err}`);
      });
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

    this.subscriptions.push(
      this.wsConnectionService.reconnectState$.subscribe((state) => {
        this.ngZone.run(() => {
          this.isReconnectingToServer = state !== null;
          this.cdr.detectChanges();
        });
      })
    );

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

    this.initializeChat();

    // Listen to changes in the user's name
    this.subscriptions.push(
      this.userService.user$.subscribe((username: unknown) => {
        if (username) {
          this.ngZone.run(() => {
            this.logger.info('ngOnInit', `Username is set to: ${username}`);
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
   * Runtime language switch — accepts any code from the registry.
   */
  switchLanguage(language: LanguageCode) {
    this.ngZone.run(() => {
      this.languageService.setLanguagePreference(language);
      this.currentLanguage = language;
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
    const minHeight = 24;

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
      combineLatest([
        this.roomService.members$,
        this.userService.user$,
        this.blockService.blockedPeers$,
      ])
        .pipe(
          filter(([, currentUser]) => currentUser.trim().length > 0),
          map(([allMembers, currentUser, blocked]) =>
            allMembers.filter((m) => m !== currentUser && !blocked.has(m))
          ),
          distinctUntilChanged(
            (previous, current) =>
              previous.length === current.length &&
              previous.every((member, index) => member === current[index])
          )
        )
        .subscribe((nextMembers: string[]) => {
          this.ngZone.run(() => {
            const previousMembers = this.members;
            const departedMembers = previousMembers.filter(
              (member) => !nextMembers.includes(member)
            );

            this.members = nextMembers;

            departedMembers.forEach((member) => {
              this.logger.info(
                'members',
                `Closing WebRTC connection for departed member: ${member}`
              );
              this.webrtcService.closeConnection(member);
              this.memberConnectionStatus.delete(member);
              this.memberConnectionState.delete(member);
              void this.fileTransferService.handlePeerLeft(member);
            });

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
                this.memberConnectionState.set(member, 'connecting');
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

    // Aggregate status for the sender's own outgoing files (echo bubble).
    this.subscriptions.push(
      this.fileTransferService.outgoingGroupStatus$.subscribe(
        ({ groupId, delivered, total, resolved }) => {
          this.ngZone.run(() => {
            const updated = this.chatService.messages$.value.map((msg) => {
              if (
                msg.type === ChatMessageType.ATTACHMENT &&
                msg.fileTransfer?.groupId === groupId
              ) {
                const status =
                  delivered > 0
                    ? FileTransferStatus.COMPLETED // Sent / Sent to X of N
                    : resolved
                      ? FileTransferStatus.DECLINED // Not delivered
                      : FileTransferStatus.ACCEPTED; // Sending…
                return {
                  ...msg,
                  fileTransfer: {
                    ...msg.fileTransfer,
                    status,
                    deliveredCount: delivered,
                    recipientCount: total,
                  },
                };
              }
              return msg;
            });
            this.chatService.replaceMessages(updated as ChatMessage[]);
            this.cdr.detectChanges();
          });
        }
      )
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

    // Receiver bubble: reflect the terminal status of an incoming download
    // (completed / cancelled / failed) once it stops.
    this.subscriptions.push(
      this.fileTransferService.downloadStatus$.subscribe(({ fileId, status }) => {
        this.ngZone.run(() => {
          this.updateFileTransferMessageStatus(fileId, status);
          this.cdr.detectChanges();
        });
      })
    );

    // When a peer disconnects after being connected, restart warning timeout
    this.subscriptions.push(
      this.webrtcService.peerDisconnected$.subscribe((member) => {
        this.ngZone.run(() => {
          if (!this.members.includes(member)) return;
          this.memberConnectionStatus.set(member, false);
          this.memberConnectionState.set(
            member,
            this.webrtcService.isConnectedOrConnecting(member) ? 'connecting' : 'disconnected'
          );
          this.scheduleConnectionWarning(member);
          this.cdr.detectChanges();
        });
      })
    );

    // When a peer connects, cancel its warning timeout and hide banner if all peers are up
    this.subscriptions.push(
      this.webrtcService.peerConnected$.subscribe((member) => {
        this.ngZone.run(() => {
          if (!this.members.includes(member)) return;
          this.memberConnectionStatus.set(member, true);
          this.memberConnectionState.set(member, 'connected');
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

    const attemptedCode = this.SessionCode;
    this.connect(attemptedCode || undefined).catch(() => {
      // Public session keeps retrying behind the reconnect banner; only a
      // private session falls back to public on failure.
      if (attemptedCode) {
        this.fallbackToPublic();
      }
    });

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
      this.enableThemeTransition();
      this.themeService.setThemePreference(this.isDarkMode);
      this.applyTheme(this.isDarkMode);
      this.cdr.detectChanges();
    });
  }

  /**
   * Adds `theme-transition` on <html> so the whole UI animates the theme change
   * together (see styles.css), then removes it once the 300ms transition ends.
   * Only on user toggle — not on initial load.
   */
  private enableThemeTransition(): void {
    if (!isPlatformBrowser(this.platformId)) {
      return;
    }

    const root = document.documentElement;
    root.classList.add('theme-transition');

    if (this.themeTransitionTimeout) {
      clearTimeout(this.themeTransitionTimeout);
    }
    this.themeTransitionTimeout = setTimeout(() => {
      root.classList.remove('theme-transition');
      this.themeTransitionTimeout = null;
    }, 350);
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
        const err =
          error instanceof Error ? error : new Error(`WebSocket connection failed: ${error}`);
        this.logger.error('connect', err.message, err);
        throw err;
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

    const transitionId = ++this.currentTransitionId;
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
    this.memberConnectionState.clear();
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
      // Superseded by a newer transition — leave its state alone.
      if (transitionId !== this.currentTransitionId) return;
    } catch (err) {
      if (transitionId !== this.currentTransitionId) return;
      this.logger.error('enterSession', `Failed to connect to new session: ${err}`);
      if (code) {
        this.fallbackToPublic();
      }
    } finally {
      if (transitionId === this.currentTransitionId) {
        this.isNavigatingIntentionally = false;
      }
    }
  }

  /**
   * ==========================================================
   * BLOCK USER
   * Blocks the peer and clears their messages. Dropping them from `members`
   * takes the connection down through the departed-member path above.
   * ==========================================================
   */
  blockUser(peer: string): void {
    if (!peer) return;

    this.blockService.block(peer);
    this.chatService.removeMessagesFrom(peer);
    this.toaster.success(this.translate.instant('BLOCKED_USER_TOAST', { user: peer }));
  }

  /**
   * ==========================================================
   * REPORT USER
   * Blocks first, then opens a pre-filled report. Blocking is not contingent
   * on the mail being sent — the content must leave the feed either way.
   * ==========================================================
   */
  reportUser(message: ChatMessage): void {
    this.blockUser(message.from);

    const url = buildReportMailto(
      SUPPORT_EMAIL,
      this.translate.instant('REPORT_EMAIL_SUBJECT'),
      this.translate.instant('REPORT_EMAIL_INTRO'),
      message,
      this.SessionCode.length > 0,
      this.appVersion
    );
    window.location.href = url;
  }

  /**
   * ==========================================================
   * SEND MESSAGE
   * Sends the chat message to other members via WebRTC, then clears
   * the input field and scrolls chat down.
   * ==========================================================
   */
  async sendMessage(messageForm: NgForm): Promise<void> {
    if (this.isSending) return;

    const hasText = !!this.message.trim();
    const hasFiles = this.stagedFiles.length > 0;

    if (!hasText && !hasFiles) {
      this.toaster.warning(this.translate.instant('MESSAGE_REQUIRED'));
      return;
    }

    const otherMembers = this.members.filter((m) => m !== this.userService.user);
    if (otherMembers.length === 0) {
      this.toaster.warning(this.translate.instant('NO_MEMBERS_TO_SEND_MESSAGE'));
      return;
    }

    this.isSending = true;
    try {
      // 1) Staged attachments first — cleared only after a successful send so a
      //    failure keeps the chips (and the text) for the user to retry.
      if (hasFiles) {
        const filesToSend = this.stagedFiles.map((s) => s.file);
        await this.sendFilesToRecipients(filesToSend, otherMembers);
        this.stagedFiles = [];
      }

      // 2) Send the text message, if any.
      if (hasText) {
        const messageText = this.message;
        let hasSuccessfulSend = false;

        // Wait for all send operations to complete
        const sendPromises = otherMembers.map(async (member) => {
          try {
            await this.chatService.sendMessage(messageText, member, ChatMessageType.TEXT);
            hasSuccessfulSend = true;
          } catch (error) {
            this.logger.error('sendMessage', `Failed to send message to ${member}: ${error}`);
            this.toaster.error(this.translate.instant('FAILED_TO_SEND_MESSAGE', { member }));
          }
        });

        await Promise.all(sendPromises);

        // Only add to local chat if at least one send was successful
        if (hasSuccessfulSend) {
          this.chatService.addMessageToLocal(messageText, ChatMessageType.TEXT);
        }
      }

      // 3) Reset the input.
      this.ngZone.run(() => {
        this.message = '';
        messageForm.resetForm({ message: '' });
        this.cdr.detectChanges();
        this.scrollToBottom();
        requestAnimationFrame(() => {
          this.autoResizeTextarea();
          this.messageTextarea?.nativeElement.focus();
        });
      });
    } catch (error) {
      this.logger.error('sendMessage', `Failed to send attachments: ${error}`);
      this.toaster.error(this.translate.instant('FAILED_TO_SEND_FILES'));
    } finally {
      this.isSending = false;
    }
  }

  /**
   * ==========================================================
   * TRUNCATE FILENAME
   * Truncates a filename while preserving the file extension
   * ==========================================================
   */
  protected truncateFilename(filename: string, maxLength = 30): string {
    return middleTruncateFilenameUtil(filename, maxLength);
  }

  /**
   * ==========================================================
   * CREATE FILE MESSAGES (LOCAL)
   * Creates local chat messages for files being sent (sender-side only).
   * Recipients create their own messages from the file offer directly.
   * ==========================================================
   */
  private async createLocalFileMessages(
    files: File[],
    groupIds: Map<File, string>,
    recipientCount: number
  ): Promise<void> {
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

      const groupId = groupIds.get(file)!;
      this.chatService.addMessageToLocal(fileMessageText, ChatMessageType.ATTACHMENT, {
        previewUrl,
        previewMime,
        fileTransfer: {
          fileId: groupId,
          fileName: file.name,
          fileSize: file.size,
          fromUser: this.userService.user,
          status: FileTransferStatus.ACCEPTED,
          groupId,
          deliveredCount: 0,
          recipientCount,
        },
      });
    }
  }

  /**
   * ==========================================================
   * FILES SELECTED (main attach button + per-member picker)
   * Per-member picks (overrideRecipients set) send immediately to that
   * member. Picks from the main attach button are staged as chips above
   * the input and sent on the next message submit.
   * ==========================================================
   */
  onFilesSelected(event: Event): void {
    const input = event.target as HTMLInputElement;
    const files = input.files ? Array.from(input.files) : [];
    input.value = '';

    if (files.length === 0) {
      this.toaster.warning(this.translate.instant('NO_FILES_SELECTED'));
      return;
    }

    if (this.overrideRecipients && this.overrideRecipients.length > 0) {
      const recipients = this.overrideRecipients;
      this.overrideRecipients = null;
      this.sendFilesToRecipients(files, recipients).catch((error) => {
        this.logger.error('onFilesSelected', `Failed to send files: ${error}`);
        this.toaster.error(this.translate.instant('FAILED_TO_SEND_FILES'));
      });
      return;
    }

    this.stageFiles(files);
  }

  /**
   * ==========================================================
   * STAGE / UNSTAGE FILES
   * Hold picked files as removable chips until the user hits send.
   * ==========================================================
   */
  protected stageFiles(files: File[]): void {
    const staged = files.map((file) => ({ id: crypto.randomUUID(), file }));
    this.stagedFiles = [...this.stagedFiles, ...staged];
    this.cdr.detectChanges();
  }

  protected removeStagedFile(id: string): void {
    this.stagedFiles = this.stagedFiles.filter((s) => s.id !== id);
    this.cdr.detectChanges();
  }

  /**
   * ==========================================================
   * SEND FILES TO RECIPIENTS
   * Shared upload path: one group id per file (links the echo bubble to
   * its per-peer uploads), prepare + connect, then send offers per peer.
   * ==========================================================
   */
  private async sendFilesToRecipients(filesToSend: File[], recipients: string[]): Promise<void> {
    if (filesToSend.length === 0 || recipients.length === 0) {
      this.toaster.warning(this.translate.instant('NO_USERS_FOR_UPLOAD'));
      return;
    }

    // One group id per file links its echo bubble to its per-peer uploads.
    const groupIds = new Map<File, string>();
    for (const file of filesToSend) {
      const groupId = crypto.randomUUID();
      groupIds.set(file, groupId);
      this.fileTransferService.beginUploadGroup(groupId, recipients.length);
    }

    // Create local chat messages for each file being sent
    await this.createLocalFileMessages(filesToSend, groupIds, recipients.length);

    // First prepare all files for all recipients
    for (const fileToSend of filesToSend) {
      for (const member of recipients) {
        await this.fileTransferService.prepareFileForSending(
          fileToSend,
          member,
          groupIds.get(fileToSend)!
        );
        if (!this.webrtcService.isConnectedOrConnecting(member)) {
          this.logger.info(
            'sendFilesToRecipients',
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
        this.logger.debug('sendFilesToRecipients', `Sent ${filesToSend.length} files to ${member}`);
      }
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
  private updateFileTransferMessageStatus(fileId: string, status: FileTransferStatus): void {
    const currentMessages = this.chatService.messages$.value;
    const updatedMessages = currentMessages.map((msg) => {
      if (msg.type === ChatMessageType.ATTACHMENT && msg.fileTransfer?.fileId === fileId) {
        const statusText = this.translate.instant(this.fileTransferStatusLabelKey(status));
        const fileSizeLabel = this.fileSizePipe.transform(msg.fileTransfer.fileSize, 2);

        return {
          ...msg,
          text: `${this.truncateFilename(msg.fileTransfer.fileName)} (${fileSizeLabel})\n${statusText}`,
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

  /** i18n key for the status line shown under a file-transfer bubble. */
  private fileTransferStatusLabelKey(status: FileTransferStatus): string {
    switch (status) {
      case FileTransferStatus.ACCEPTED:
        return 'FILE_TRANSFER_ACCEPTED';
      case FileTransferStatus.DECLINED:
        return 'FILE_TRANSFER_DECLINED';
      case FileTransferStatus.COMPLETED:
        return 'FILE_TRANSFER_COMPLETED';
      case FileTransferStatus.CANCELLED:
        return 'FILE_TRANSFER_CANCELLED';
      case FileTransferStatus.FAILED:
        return 'FILE_TRANSFER_FAILED';
      default:
        return 'FILE_TRANSFER_ACCEPTED';
    }
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
        this.clearMessages();
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
      // Cross-route nav: Angular tears down this component, ngOnDestroy
      // handles cleanup, and the new instance at '/' connects to public.
      void this.router.navigateByUrl('/');
    });
  }

  /**
   * ==========================================================
   * OPEN CHAT SESSION
   * Navigates to /private/:code. Cross-route transitions (public -> private)
   * destroy/recreate the component; only same-route /private/A -> /private/B
   * goes through the paramMap -> enterSession() path.
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
   * The browser hides the HTTP status of a failed WS upgrade, so a join
   * failure could be a bad code or an unreachable server — toast covers both.
   */
  private fallbackToPublic(): void {
    this.clearSessionCode();
    this.toaster.error(this.translate.instant('SESSION_JOIN_FAILED'));
    void this.router.navigateByUrl('/');
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
    // Clear any existing connection initialization timeouts before reacting
    // to the latest membership snapshot.
    this.connectionInitTimeouts.forEach((timeout) => clearTimeout(timeout));
    this.connectionInitTimeouts = [];

    if (!this.members || this.members.length === 0) {
      this.logger.info(
        'initiateConnectionsWithMembers',
        'No members in the room, skipping WebRTC.'
      );

      if (this.statusCheckIntervalId) {
        clearInterval(this.statusCheckIntervalId);
        this.statusCheckIntervalId = null;
      }
      return;
    }

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
      const shouldInitiate = this.userService.user < member;

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

        // Keep the status maps in sync for the UI (red/yellow/green circles)
        otherMembers.forEach((member) => {
          const connected = this.webrtcService.isConnected(member);
          this.memberConnectionStatus.set(member, connected);
          this.memberConnectionState.set(
            member,
            connected
              ? 'connected'
              : this.webrtcService.isConnectedOrConnecting(member)
                ? 'connecting'
                : 'disconnected'
          );
        });

        // Clean up warning timeouts for members who left
        for (const [member, timeoutId] of this.connectionWarningTimeouts.entries()) {
          if (!otherMembers.includes(member)) {
            clearTimeout(timeoutId);
            this.connectionWarningTimeouts.delete(member);
          }
        }

        if (this.showConnectionWarning && !this.isIsolatedFromPeers) {
          this.showConnectionWarning = false;
          this.connectionWarningDismissed = false;
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

  private get isIsolatedFromPeers(): boolean {
    const otherMembers = this.members.filter((m) => m !== this.userService.user);
    return otherMembers.length > 0 && !otherMembers.some((m) => this.isConnectedToMember(m));
  }

  protected get hasNoConnectedPeers(): boolean {
    const otherMembers = this.members.filter((m) => m !== this.userService.user);
    if (otherMembers.length === 0) return true;
    return !otherMembers.some((m) => this.isConnectedToMember(m));
  }

  protected get isSendDisabled(): boolean {
    return (
      this.isSending ||
      (!this.message.trim() && this.stagedFiles.length === 0) ||
      this.hasNoConnectedPeers
    );
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
        if (this.isIsolatedFromPeers && !this.connectionWarningDismissed) {
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
    // Hide the banner as soon as any peer is reachable, or everyone has left.
    if (!this.isIsolatedFromPeers) {
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
    return document.dir === 'rtl' || getLanguage(this.currentLanguage)?.direction === 'rtl';
  }

  /**
   * ==========================================================
   * DRAG & DROP (whole chat view)
   * Files dropped anywhere over the conversation area are sent.
   * The overlay only shows when files (not text) are dragged.
   * ==========================================================
   */
  protected isDraggingFiles = false;

  protected onChatDragOver(event: DragEvent): void {
    event.preventDefault();
    if (event.dataTransfer) {
      event.dataTransfer.dropEffect = 'copy';
    }
  }

  protected onChatDragEnter(event: DragEvent): void {
    if (event.dataTransfer && Array.from(event.dataTransfer.types).includes('Files')) {
      this.isDraggingFiles = true;
    }
  }

  protected onChatDragLeave(event: DragEvent): void {
    const rect = (event.currentTarget as HTMLElement).getBoundingClientRect();
    if (
      event.clientX <= rect.left ||
      event.clientX >= rect.right ||
      event.clientY <= rect.top ||
      event.clientY >= rect.bottom
    ) {
      this.isDraggingFiles = false;
    }
  }

  protected onChatDrop(event: DragEvent): void {
    event.preventDefault();
    this.isDraggingFiles = false;
    if (!event.dataTransfer?.files) return;
    const files = Array.from(event.dataTransfer.files);
    if (files.length === 0) return;
    this.handleFilesDropped(files);
  }

  protected onChatPaste(event: ClipboardEvent): void {
    const files = Array.from(event.clipboardData?.files ?? []);
    if (files.length === 0) return;

    event.preventDefault();
    this.handleFilesDropped(files);
  }

  /**
   * ==========================================================
   * HANDLE FILES DROPPED
   * Dropped files are staged as chips above the input (same as the
   * attach button) and sent on the next message submit.
   * ==========================================================
   */
  protected handleFilesDropped(files: File[]): void {
    if (files.length === 0) return;

    // Discard drops into an empty room — keep the original feedback rather than
    // holding files that have nowhere to go.
    const otherMembers = this.members.filter((m) => m !== this.userService.user);
    if (otherMembers.length === 0) {
      this.toaster.info(this.translate.instant('NO_USERS_FOR_UPLOAD'));
      return;
    }

    this.stageFiles(files);
  }
}
