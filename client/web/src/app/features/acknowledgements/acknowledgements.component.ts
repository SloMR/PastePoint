import { Component, ChangeDetectorRef, PLATFORM_ID, OnInit, inject } from '@angular/core';
import { CommonModule, isPlatformBrowser } from '@angular/common';
import { HttpClient } from '@angular/common/http';
import { ActivatedRoute, RouterLink } from '@angular/router';
import { TranslateModule } from '@ngx-translate/core';

import { PageHeaderComponent } from '../../core/components/layout/page-header/page-header.component';
import { PageFooterComponent } from '../../core/components/layout/page-footer/page-footer.component';
import { ThemeService } from '../../core/services/ui/theme.service';
import packageJson from '../../../../package.json';
import { NGXLogger } from 'ngx-logger';
import { MetaService } from '../../core/services/ui/meta.service';
import { LanguageService } from '../../core/services/ui/language.service';
import { LanguageCode, getLanguage } from '../../core/i18n/languages';
import { THEME_PREFERENCE_KEY, ACKNOWLEDGEMENTS_URL } from '../../utils/constants';

export interface Acknowledgement {
  name: string;
  version: string;
  license: string;
  text: string;
}

@Component({
  selector: 'app-acknowledgements',
  imports: [CommonModule, RouterLink, TranslateModule, PageHeaderComponent, PageFooterComponent],
  templateUrl: './acknowledgements.component.html',
  styleUrl: './acknowledgements.component.css',
})
export class AcknowledgementsComponent implements OnInit {
  private platformId = inject(PLATFORM_ID);
  private cdr = inject(ChangeDetectorRef);
  private themeService = inject(ThemeService);
  private languageService = inject(LanguageService);
  private logger = inject(NGXLogger);
  private metaService = inject(MetaService);
  private route = inject(ActivatedRoute);
  private http = inject(HttpClient);

  isDarkMode = false;
  isEmbedded = false;

  currentLanguage: LanguageCode = 'en';
  appVersion: string = packageJson.version;

  acknowledgements: Acknowledgement[] = [];
  expanded = new Set<string>();
  isLoading = true;
  loadFailed = false;

  ngOnInit(): void {
    this.isEmbedded = this.route.snapshot.queryParamMap.get('app') === '1';

    if (!isPlatformBrowser(this.platformId)) {
      this.metaService.updateAcknowledgementsMetadata();
      return;
    }

    const themePreference = localStorage.getItem(THEME_PREFERENCE_KEY);
    this.isDarkMode = themePreference === 'dark';
    this.applyTheme(this.isDarkMode);

    this.metaService.updateAcknowledgementsMetadata();
    this.currentLanguage = this.languageService.getCurrentLanguage();

    this.loadAcknowledgements();
  }

  private loadAcknowledgements(): void {
    this.http.get<{ packages: Acknowledgement[] }>(ACKNOWLEDGEMENTS_URL).subscribe({
      next: ({ packages }) => {
        this.acknowledgements = packages ?? [];

        this.isLoading = false;
        this.loadFailed = this.acknowledgements.length === 0;
        this.cdr.detectChanges();
      },
      error: (error) => {
        this.logger.warn('loadAcknowledgements', 'Third-party notices unavailable', error);

        this.isLoading = false;
        this.loadFailed = true;
        this.cdr.detectChanges();
      },
    });
  }

  toggle(name: string): void {
    if (this.expanded.has(name)) {
      this.expanded.delete(name);
    } else {
      this.expanded.add(name);
    }
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
