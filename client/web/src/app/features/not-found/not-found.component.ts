import { Component, ChangeDetectorRef, PLATFORM_ID, OnInit, inject } from '@angular/core';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { RouterLink } from '@angular/router';
import { TranslateModule, TranslateService } from '@ngx-translate/core';

import { PageHeaderComponent } from '../../core/components/layout/page-header/page-header.component';
import { PageFooterComponent } from '../../core/components/layout/page-footer/page-footer.component';
import { ThemeService } from '../../core/services/ui/theme.service';
import packageJson from '../../../../package.json';
import { NGXLogger } from 'ngx-logger';
import { MigrationService } from '../../core/services/migration/migration.service';
import { MetaService } from '../../core/services/ui/meta.service';
import { LanguageService } from '../../core/services/ui/language.service';
import { LanguageCode, getLanguage } from '../../core/i18n/languages';
import { THEME_PREFERENCE_KEY } from '../../utils/constants';

@Component({
  imports: [CommonModule, RouterLink, TranslateModule, PageHeaderComponent, PageFooterComponent],
  selector: 'app-not-found',
  templateUrl: './not-found.component.html',
  styleUrl: './not-found.component.css',
})
export class NotFoundComponent implements OnInit {
  private platformId = inject(PLATFORM_ID);
  protected translate = inject<TranslateService>(TranslateService);
  private cdr = inject(ChangeDetectorRef);
  private themeService = inject(ThemeService);
  private languageService = inject(LanguageService);
  private logger = inject(NGXLogger);
  private migrationService = inject(MigrationService);
  private metaService = inject(MetaService);

  isDarkMode = false;
  currentLanguage: LanguageCode = 'en';
  appVersion: string = packageJson.version;

  ngOnInit(): void {
    if (!isPlatformBrowser(this.platformId)) {
      this.metaService.updateNotFoundMetadata();
      return;
    }
    // Check if migration is needed due to version change
    const migrationPerformed = this.migrationService.checkAndMigrateIfNeeded(this.appVersion, true);
    if (migrationPerformed) {
      this.logger.debug('ngOnInit', 'Migration performed due to version change');
    } else {
      this.logger.debug('ngOnInit', 'No migration needed');
    }

    const themePreference = localStorage.getItem(THEME_PREFERENCE_KEY);
    this.isDarkMode = themePreference === 'dark';
    this.applyTheme(this.isDarkMode);

    // Set specific meta tags for 404 page
    this.metaService.updateNotFoundMetadata();

    // Get current language from language service
    this.currentLanguage = this.languageService.getCurrentLanguage();
  }

  toggleTheme(): void {
    this.isDarkMode = !this.isDarkMode;
    this.themeService.setThemePreference(this.isDarkMode);
    this.applyTheme(this.isDarkMode);
    this.cdr.detectChanges();
  }

  private applyTheme(isDark: boolean): void {
    if (isPlatformBrowser(this.platformId)) {
      const htmlElement = document.documentElement;
      if (isDark) {
        htmlElement.classList.add('dark');
        htmlElement.setAttribute('data-theme', 'dark');
      } else {
        htmlElement.classList.remove('dark');
        htmlElement.setAttribute('data-theme', 'light');
      }
    }
  }

  switchLanguage(language: LanguageCode) {
    this.languageService.setLanguagePreference(language);
    this.currentLanguage = language;
    this.cdr.detectChanges();
  }

  get isRTL(): boolean {
    if (!isPlatformBrowser(this.platformId)) return false;
    return document.dir === 'rtl' || getLanguage(this.currentLanguage)?.direction === 'rtl';
  }
}
