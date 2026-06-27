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
  @Input() triggerClass =
    'flex cursor-pointer items-center justify-center rounded-lg border w-[44px] h-[44px] border-borderButton bg-pageBackground hover:bg-borderLight dark:bg-surfaceDark dark:border-borderDark dark:hover:bg-baseDark md:w-[56px] md:h-[56px] transition-colors';
  @Input() iconClass = 'h-5 w-5 text-brand dark:text-brandDark';
  @Input() menuClass =
    'absolute end-0 md:start-0 md:end-auto top-full mt-2 z-50 min-w-[11rem] max-w-[calc(100vw-1rem)] overflow-hidden rounded-lg border border-borderLight bg-pageBackground py-1 shadow-lg dark:border-borderDark dark:bg-surfaceDark';
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
