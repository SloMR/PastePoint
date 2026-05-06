import { LanguageCode } from '../i18n/languages';

export interface ILanguageService {
  initializeLanguage(): void;
  setLanguagePreference(language: LanguageCode): void;
  getCurrentLanguage(): LanguageCode;
}
