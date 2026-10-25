import { Injectable } from '@angular/core';
import { Observable, of } from 'rxjs';

@Injectable()
export class MockTranslateService {
  public currentLang = 'en';
  public fallbackLang = 'en';

  private translations: Record<string, Record<string, string>> = {
    en: {
      APP_TITLE: 'PastePoint',
      TOGGLE_THEME: 'Toggle Theme',
      USER_INFO: 'User Info',
      ROOMS: 'Rooms',
      NEW_ROOM: 'New Room',
      JOIN_CREATE: 'Join/Create',
      MEMBERS: 'Members',
      PRIVATE_SESSION: 'Private Session',
      SESSION_CODE: 'Session Code',
      GO_BACK_HOME: 'Go Back Home',
      PAGE_NOT_FOUND: 'Page Not Found',
      COPYRIGHT_NOTICE: '© 2026 PastePoint. All rights reserved.',
      VERSION: 'Version',
    },
    ar: {
      APP_TITLE: 'PastePoint',
      TOGGLE_THEME: 'تبديل السمة',
      USER_INFO: 'معلومات المستخدم',
      ROOMS: 'الغرف',
    },
  };
  private _interpolateParams: object | undefined;
  private _langs: string[] | undefined;

  get(key: string | string[], interpolateParams?: object): Observable<string | object> {
    this._interpolateParams = interpolateParams;
    if (typeof key === 'string') {
      return of(this.translations[this.currentLang][key] || key);
    }
    const result: Record<string, string> = {};
    key.forEach((k) => {
      result[k] = this.translations[this.currentLang][k] || k;
    });
    return of(result);
  }

  instant(key: string | string[], interpolateParams?: object): string | unknown {
    this._interpolateParams = interpolateParams;
    if (typeof key === 'string') {
      return this.translations[this.currentLang][key] || key;
    }
    const result: Record<string, string> = {};
    key.forEach((k) => {
      result[k] = this.translations[this.currentLang]?.[k] || k;
    });
    return result;
  }

  getBrowserLang(): string {
    return 'en';
  }

  getCurrentLang(): string {
    return this.currentLang;
  }

  setFallbackLang(lang: string): void {
    this.fallbackLang = lang;
  }

  use(lang: string): Observable<unknown> {
    this.currentLang = lang;
    return of({});
  }

  addLangs(langs: string[]): void {
    this._langs = langs;
  }

  getLangs(): string[] {
    return Object.keys(this.translations);
  }

  getTranslation(lang: string): Observable<unknown> {
    return of(this.translations[lang] || {});
  }

  onLangChange = new Observable();
  onTranslationChange = new Observable();
  onFallbackLangChange = new Observable();
}
