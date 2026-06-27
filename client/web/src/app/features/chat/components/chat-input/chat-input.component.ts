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

export interface EnterKeyEvent {
  event: KeyboardEvent;
  form: NgForm;
}

@Component({
  selector: 'app-chat-input',
  imports: [CommonModule, FormsModule, TranslateModule],
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

  @Output() messageChange = new EventEmitter<string>();

  @Output() messageSubmit = new EventEmitter<NgForm>();
  @Output() enterKey = new EventEmitter<EnterKeyEvent>();
  @Output() autoResize = new EventEmitter<void>();
  @Output() filesAttached = new EventEmitter<Event>();

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
