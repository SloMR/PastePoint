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
import { LANGUAGES, LanguageCode } from '../../i18n/languages';

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
  @Output() languageChange = new EventEmitter<LanguageCode>();

  protected readonly languages = LANGUAGES;
  protected readonly isOpen = signal(false);

  private host = inject(ElementRef<HTMLElement>);

  protected toggle(): void {
    this.isOpen.update((open) => !open);
  }

  protected select(code: LanguageCode): void {
    this.isOpen.set(false);
    if (code !== this.current) this.languageChange.emit(code);
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
    if (this.isOpen()) this.isOpen.set(false);
  }
}
