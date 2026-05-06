import { TranslateLoader } from '@ngx-translate/core';
import { Observable, of } from 'rxjs';
import { DEFAULT_LANGUAGE, LanguageCode, TranslationObject, getLanguage } from './languages';

export type { LanguageCode } from './languages';

export class InMemoryTranslateLoader implements TranslateLoader {
  getTranslation(lang: LanguageCode | string): Observable<TranslationObject> {
    const def = getLanguage(lang) ?? getLanguage(DEFAULT_LANGUAGE)!;
    return of(def.translations);
  }
}
