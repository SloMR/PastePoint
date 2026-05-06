import {
  Injectable,
  PLATFORM_ID,
  TransferState,
  makeStateKey,
  StateKey,
  inject,
} from '@angular/core';
import { isPlatformBrowser } from '@angular/common';
import { TranslateService } from '@ngx-translate/core';
import { ILanguageService } from '../../interfaces/language.interface';
import {
  DEFAULT_LANGUAGE,
  LanguageCode,
  getLanguage,
  isSupportedLanguage,
} from '../../i18n/languages';
import { LANGUAGE_PREFERENCE_KEY } from '../../../utils/constants';
import { NGXLogger } from 'ngx-logger';

@Injectable({
  providedIn: 'root',
})
export class LanguageService implements ILanguageService {
  private platformId = inject(PLATFORM_ID);
  private transferState = inject(TransferState);
  private translateService = inject(TranslateService);
  private logger = inject(NGXLogger);

  /**
   * ==========================================================
   * CONSTANTS
   * Storage key for language preference
   * ==========================================================
   */
  private readonly LANGUAGE_STATE_KEY: StateKey<string> =
    makeStateKey<string>(LANGUAGE_PREFERENCE_KEY);

  /**
   * ==========================================================
   * PUBLIC METHODS
   * APIs for language initialization and management
   * ==========================================================
   */
  initializeLanguage(): void {
    if (!isPlatformBrowser(this.platformId)) {
      this.transferState.set(this.LANGUAGE_STATE_KEY, DEFAULT_LANGUAGE);
      this.translateService.setDefaultLang(DEFAULT_LANGUAGE);
      this.translateService.use(DEFAULT_LANGUAGE);
      this.logger.debug('initializeLanguage', 'Language Service (Server):', DEFAULT_LANGUAGE);
      return;
    }

    const stored = this.getLanguagePreference();
    this.logger.debug('initializeLanguage', 'Stored language from localStorage:', stored);

    let preference: LanguageCode;
    if (stored) {
      preference = stored;
    } else if (this.transferState.hasKey(this.LANGUAGE_STATE_KEY)) {
      const transferred = this.transferState.get(this.LANGUAGE_STATE_KEY, DEFAULT_LANGUAGE);
      preference = isSupportedLanguage(transferred) ? transferred : DEFAULT_LANGUAGE;
    } else {
      preference = this.detectBrowserLanguage() ?? DEFAULT_LANGUAGE;
    }

    if (this.transferState.hasKey(this.LANGUAGE_STATE_KEY)) {
      this.transferState.remove(this.LANGUAGE_STATE_KEY);
    }

    this.applyLanguage(preference);
    this.logger.debug('initializeLanguage', 'Language Service initialized with:', preference);
  }

  setLanguagePreference(language: LanguageCode): void {
    if (!isPlatformBrowser(this.platformId)) {
      // Server-side: just apply the language
      this.applyLanguage(language);
    } else {
      // Client-side: store in localStorage and apply
      localStorage.setItem(LANGUAGE_PREFERENCE_KEY, language);
      this.applyLanguage(language);
    }
  }

  getCurrentLanguage(): LanguageCode {
    return this.translateService.currentLang as LanguageCode;
  }

  /**
   * ==========================================================
   * PRIVATE METHODS
   * Utility methods for language operations
   * ==========================================================
   */
  private getLanguagePreference(): LanguageCode | null {
    if (!isPlatformBrowser(this.platformId)) {
      return DEFAULT_LANGUAGE;
    }
    const stored = localStorage.getItem(LANGUAGE_PREFERENCE_KEY);
    return stored && isSupportedLanguage(stored) ? stored : null;
  }

  private detectBrowserLanguage(): LanguageCode | null {
    if (!isPlatformBrowser(this.platformId) || !navigator.languages) return null;
    for (const tag of navigator.languages) {
      if (isSupportedLanguage(tag)) return tag;
      const base = tag.split('-')[0];
      if (isSupportedLanguage(base)) return base;
    }
    return null;
  }

  private applyLanguage(language: LanguageCode): void {
    this.logger.debug('applyLanguage', 'Applying language:', language);
    this.translateService.setDefaultLang(language);
    this.translateService.use(language);

    if (isPlatformBrowser(this.platformId)) {
      document.documentElement.lang = language;
      document.documentElement.dir = getLanguage(language)?.direction ?? 'ltr';
      this.logger.debug(
        'applyLanguage',
        'Document lang/dir set to:',
        document.documentElement.lang,
        document.documentElement.dir
      );
    }
  }
}
