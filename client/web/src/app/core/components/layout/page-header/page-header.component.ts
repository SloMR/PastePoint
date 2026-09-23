import { Component, EventEmitter, Input, Output, ChangeDetectionStrategy } from '@angular/core';
import { CommonModule, NgOptimizedImage } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslatePipe } from '@ngx-translate/core';
import { LanguageCode } from '../../../i18n/languages';
import { LanguageSwitcherComponent } from '../../language-switcher/language-switcher.component';

@Component({
  selector: 'app-page-header',
  imports: [CommonModule, RouterLink, NgOptimizedImage, TranslatePipe, LanguageSwitcherComponent],
  templateUrl: './page-header.component.html',
  changeDetection: ChangeDetectionStrategy.Eager,
  styleUrl: './page-header.component.css',
})
export class PageHeaderComponent {
  @Input() isDarkMode = false;
  @Input() currentLanguage: LanguageCode = 'en';

  @Output() toggleTheme = new EventEmitter<void>();
  @Output() switchLanguage = new EventEmitter<LanguageCode>();
}
