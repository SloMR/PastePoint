import enTranslations from './localizations/en.json';
import arTranslations from './localizations/ar.json';
import esTranslations from './localizations/es.json';
import frTranslations from './localizations/fr.json';
import ruTranslations from './localizations/ru.json';
import zhCNTranslations from './localizations/zh-CN.json';

export type TranslationObject = Record<string, string>;

export interface LanguageDef {
  code: string;
  nativeName: string;
  englishName: string;
  direction: 'ltr' | 'rtl';
  translations: TranslationObject;
}

/**
 * The single source of truth for supported languages. Add a row here and the
 * loader, switcher, type system, and direction handling all pick it up
 * automatically — no other file needs to change.
 *
 * Keep `en` first; it's the fallback locale across the app.
 */
export const LANGUAGES = [
  {
    code: 'en',
    nativeName: 'English',
    englishName: 'English',
    direction: 'ltr',
    translations: enTranslations,
  },
  {
    code: 'ar',
    nativeName: 'العربية',
    englishName: 'Arabic',
    direction: 'rtl',
    translations: arTranslations,
  },
  {
    code: 'es',
    nativeName: 'Español',
    englishName: 'Spanish',
    direction: 'ltr',
    translations: esTranslations,
  },
  {
    code: 'fr',
    nativeName: 'Français',
    englishName: 'French',
    direction: 'ltr',
    translations: frTranslations,
  },
  {
    code: 'ru',
    nativeName: 'Русский',
    englishName: 'Russian',
    direction: 'ltr',
    translations: ruTranslations,
  },
  {
    code: 'zh-CN',
    nativeName: '简体中文',
    englishName: 'Chinese (Simplified)',
    direction: 'ltr',
    translations: zhCNTranslations,
  },
] as const satisfies readonly LanguageDef[];

export type LanguageCode = (typeof LANGUAGES)[number]['code'];

const LANGUAGE_LOOKUP = new Map<string, LanguageDef>(LANGUAGES.map((l) => [l.code, l]));

export function getLanguage(code: string): LanguageDef | undefined {
  return LANGUAGE_LOOKUP.get(code);
}

export function isSupportedLanguage(code: string): code is LanguageCode {
  return LANGUAGE_LOOKUP.has(code);
}

export const DEFAULT_LANGUAGE: LanguageCode = 'en';
