import { bootstrapApplication } from '@angular/platform-browser';
import * as Sentry from '@sentry/angular';
import { appConfig } from './app/app.config';
import { AppComponent } from './app/app.component';
import { TranslateService } from '@ngx-translate/core';
import { LANGUAGE_PREFERENCE_KEY } from './app/utils/constants';
import { environment } from './environments/environment';
import { name as pkgName, version as pkgVersion } from '../package.json';

// Initialize Sentry before bootstrapping the app so it can capture errors.
// Skip during SSR/prerender (no `window`)
if (typeof window !== 'undefined' && environment.sentry?.enabled && environment.sentry.dsn) {
  Sentry.init({
    dsn: environment.sentry.dsn,
    environment: environment.sentry.environment,
    release: `${pkgName}@${pkgVersion}`,
    sendDefaultPii: false,
    maxBreadcrumbs: 50,
    tracesSampleRate: environment.sentry.tracesSampleRate ?? 0,
    enableLogs: environment.sentry.enableLogs ?? false,
    replaysSessionSampleRate: 0,
    replaysOnErrorSampleRate: 0,
    integrations: [
      Sentry.browserTracingIntegration({
        instrumentPageLoad: false,
        ignoreResourceSpans: [
          'resource.img',
          'resource.script',
          'resource.css',
          'resource.other',
          'resource.link',
        ],
        ignorePerformanceApiSpans: [/.*/],
        enableLongAnimationFrame: false,
        enableLongTask: false,
      }),
    ],
    initialScope: {
      user: { ip_address: '127.0.0.1' },
    },
    beforeSendTransaction(event) {
      // Strip browser navigation-timing child spans and paint entries — they
      // add noise without actionable signal for this app.
      const IGNORED_OPS = new Set([
        'browser.DNS',
        'browser.TLS/SSL',
        'browser.connect',
        'browser.cache',
        'browser.request',
        'browser.response',
        'browser.loadEvent',
        'browser.unloadEvent',
        'browser.domContentLoadedEvent',
        'paint',
      ]);
      if (event.spans) {
        event.spans = event.spans.filter(
          (span) =>
            !IGNORED_OPS.has(span.op ?? '') &&
            !(span.op === 'http.client' && span.description?.includes('.js.map'))
        );
      }
      if (event.contexts?.['device']) {
        delete event.contexts['device']['timezone'];
        delete event.contexts['device']['locale'];
      }
      if (event.contexts?.['culture']) {
        delete event.contexts['culture'];
      }
      return event;
    },
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
