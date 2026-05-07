import { bootstrapApplication } from '@angular/platform-browser';
import * as Sentry from '@sentry/angular';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';
import { TranslateService } from '@ngx-translate/core';
import { LANGUAGE_PREFERENCE_KEY } from './app/utils/constants';
import { environment } from './environments/environment';

// Initialize Sentry before bootstrapping the app so it can capture errors
if (environment.sentry?.enabled && environment.sentry.dsn) {
  Sentry.init({
    dsn: environment.sentry.dsn,
    environment: environment.sentry.environment,
    release: 'web@0.17.0',
    sendDefaultPii: false,
    maxBreadcrumbs: 50,
    tracesSampleRate: 0,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    beforeSend(event) {
      // Strip user-identifying data before the event leaves the browser.
      event.user = { ip_address: '127.0.0.1' };
      delete event.server_name;
      if (event.request) {
        delete event.request.cookies;
        delete event.request.headers;
        delete event.request.data;
        delete event.request.query_string;
      }
      // Strip browser-derived locale signals from the device / culture contexts
      if (event.contexts?.['device']) {
        delete event.contexts['device']['timezone'];
        delete event.contexts['device']['locale'];
      }
      if (event.contexts?.['culture']) {
        delete event.contexts['culture'];
      }
      return event;
    },
  });
}

function getStoredLanguage(): string {
  if (typeof window !== 'undefined' && window.localStorage) {
    return localStorage.getItem(LANGUAGE_PREFERENCE_KEY) ?? 'en';
  }
  return 'en';
}

// Set document attributes immediately
const storedLang = getStoredLanguage();
if (typeof document !== 'undefined') {
  document.documentElement.lang = storedLang;
  document.documentElement.dir = storedLang === 'ar' ? 'rtl' : 'ltr';
}

// Then bootstrap with the correct language
bootstrapApplication(AppComponent, appConfig).then((appRef) => {
  const translate = appRef.injector.get(TranslateService);
  translate.setDefaultLang(storedLang);
  translate.use(storedLang);
});
