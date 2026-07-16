import { Component, EventEmitter, Input, Output } from '@angular/core';
import { CommonModule, NgOptimizedImage } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslateModule } from '@ngx-translate/core';
import { LanguageCode } from '../../../i18n/languages';
import { LanguageSwitcherComponent } from '../../language-switcher/language-switcher.component';

@Component({
  selector: 'app-page-header',
  imports: [CommonModule, RouterLink, NgOptimizedImage, TranslateModule, LanguageSwitcherComponent],
  templateUrl: './page-header.component.html',
  styleUrl: './page-header.component.css',
})
export class PageHeaderComponent {
  @Input() isDarkMode = false;
  @Input() currentLanguage: LanguageCode = 'en';

  @Output() toggleTheme = new EventEmitter<void>();
  @Output() switchLanguage = new EventEmitter<LanguageCode>();
}
