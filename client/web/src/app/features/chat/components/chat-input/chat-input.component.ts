import {
  Component,
  CUSTOM_ELEMENTS_SCHEMA,
  ElementRef,
  EventEmitter,
  Input,
  OnDestroy,
  Output,
  PLATFORM_ID,
  ViewChild,
  inject,
} from '@angular/core';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { FormsModule, NgForm } from '@angular/forms';
import { TranslateModule } from '@ngx-translate/core';
import type { EmojiClickEvent } from 'emoji-picker-element/shared';
import { FileSizePipe } from '../../../../utils/file-size.pipe';

export interface EnterKeyEvent {
  event: KeyboardEvent;
  form: NgForm;
}

export interface StagedAttachment {
  id: string;
  file: File;
}

@Component({
  selector: 'app-chat-input',
  imports: [CommonModule, FormsModule, TranslateModule, FileSizePipe],
  templateUrl: './chat-input.component.html',
  styleUrl: './chat-input.component.css',
  schemas: [CUSTOM_ELEMENTS_SCHEMA],
})
export class ChatInputComponent implements OnDestroy {
  @Input() message = '';
  @Input() isRTL = false;
  @Input() isDarkMode = false;
  @Input() hasNoConnectedPeers = false;
  @Input() isSendDisabled = false;
  @Input() stagedFiles: StagedAttachment[] = [];

  @Output() messageChange = new EventEmitter<string>();

  @Output() messageSubmit = new EventEmitter<NgForm>();
  @Output() enterKey = new EventEmitter<EnterKeyEvent>();
  @Output() autoResize = new EventEmitter<void>();
  @Output() filesAttached = new EventEmitter<Event>();
  @Output() removeStagedFile = new EventEmitter<string>();

  @ViewChild('messageTextarea', { static: false }) messageTextarea!: ElementRef;
  @ViewChild('fileInput', { static: false }) fileInput!: ElementRef<HTMLInputElement>;

  protected isEmojiPickerVisible = false;
  protected isHoveringOverPicker = false;

  private emojiPickerHideTimeout: ReturnType<typeof setTimeout> | null = null;
  private elementRef = inject(ElementRef);
  private platformId = inject(PLATFORM_ID);

  ngOnDestroy(): void {
    if (this.emojiPickerHideTimeout) {
      clearTimeout(this.emojiPickerHideTimeout);
      this.emojiPickerHideTimeout = null;
    }
  }

  protected stagedDisplayName(name: string, maxLength = 22): string {
    if (name.length <= maxLength) return name;

    const dot = name.lastIndexOf('.');
    const ext = dot > 0 ? name.slice(dot) : '';
    const base = dot > 0 ? name.slice(0, dot) : name;
    const keep = Math.max(maxLength - ext.length - 1, 4);
    const head = Math.ceil(keep / 2);
    const tail = Math.floor(keep / 2);
    return `${base.slice(0, head)}…${base.slice(base.length - tail)}${ext}`;
  }

  protected openEmojiPicker(): void {
    this.isEmojiPickerVisible = true;
    setTimeout(() => this.injectEmojiPickerScrollbarStyles());
  }

  protected handleEmojiIconMouseLeave(): void {
    if (this.emojiPickerHideTimeout) {
      clearTimeout(this.emojiPickerHideTimeout);
    }

    this.emojiPickerHideTimeout = setTimeout(() => {
      this.emojiPickerHideTimeout = null;
      if (!this.isHoveringOverPicker) {
        this.isEmojiPickerVisible = false;
      }
    }, 150);
  }

  protected addEmoji(event: EmojiClickEvent): void {
    const { emoji, skinTone } = event.detail;
    if (!('unicode' in emoji)) return;

    const unicode =
      skinTone && emoji.skins?.[skinTone - 1]?.unicode
        ? emoji.skins[skinTone - 1].unicode
        : emoji.unicode;

    const updated = this.message + unicode;
    this.message = updated;
    this.messageChange.emit(updated);
  }

  private injectEmojiPickerScrollbarStyles(): void {
    if (!isPlatformBrowser(this.platformId)) return;
    const picker = this.elementRef.nativeElement.querySelector('emoji-picker') as HTMLElement & {
      shadowRoot: ShadowRoot | null;
    };
    if (!picker?.shadowRoot || picker.shadowRoot.querySelector('#pp-scrollbar')) return;

    const style = document.createElement('style');
    style.id = 'pp-scrollbar';
    style.textContent = `
      .tabpanel { scrollbar-width: thin; scrollbar-color: rgba(125,211,252,.5) transparent; }
      .tabpanel::-webkit-scrollbar { width: 4px; }
      .tabpanel::-webkit-scrollbar-track { background: transparent; }
      .tabpanel::-webkit-scrollbar-thumb { background: rgba(125,211,252,.5); border-radius: 9999px; }
      :host(.dark) .tabpanel { scrollbar-color: rgba(75,85,99,.6) transparent; }
      :host(.dark) .tabpanel::-webkit-scrollbar-thumb { background: rgba(75,85,99,.6); }
      .nav { overflow-x: auto; scrollbar-width: none; }
      .nav::-webkit-scrollbar { display: none; }
    `;
    picker.shadowRoot.appendChild(style);
  }
}
