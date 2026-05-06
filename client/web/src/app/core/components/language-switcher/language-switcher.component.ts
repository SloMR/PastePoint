import {
  ChangeDetectionStrategy,
  Component,
  ElementRef,
  EventEmitter,
  HostListener,
  Input,
  Output,
  inject,
  signal,
} from '@angular/core';
import { TranslateModule } from '@ngx-translate/core';
import { LANGUAGES, LanguageCode, getLanguage } from '../../i18n/languages';

@Component({
  selector: 'app-language-switcher',
  standalone: true,
  imports: [TranslateModule],
  templateUrl: './language-switcher.component.html',
  styleUrls: ['./language-switcher.component.css'],
  changeDetection: ChangeDetectionStrategy.OnPush,
})
export class LanguageSwitcherComponent {
  @Input() current: LanguageCode = 'en';
  @Output() change = new EventEmitter<LanguageCode>();

  protected readonly languages = LANGUAGES;
  protected readonly isOpen = signal(false);

  private host = inject(ElementRef<HTMLElement>);

  protected get currentLabel(): string {
    return getLanguage(this.current)?.nativeName ?? this.current;
  }

  protected toggle(): void {
    this.isOpen.update((open) => !open);
  }

  protected select(code: LanguageCode): void {
    this.isOpen.set(false);
    if (code !== this.current) this.change.emit(code);
  }

  @HostListener('document:click', ['$event'])
  protected onDocumentClick(event: MouseEvent): void {
    if (!this.isOpen()) return;
    const target = event.target as Node | null;
    if (target && !this.host.nativeElement.contains(target)) {
      this.isOpen.set(false);
    }
  }

  @HostListener('document:keydown.escape')
  protected onEscape(): void {
    this.isOpen.set(false);
  }
}
