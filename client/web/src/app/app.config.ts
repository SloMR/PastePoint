import {
  ApplicationConfig,
  ErrorHandler,
  importProvidersFrom,
  inject,
  provideAppInitializer,
  provideZoneChangeDetection,
} from '@angular/core';
import { provideRouter, withNavigationErrorHandler, withPreloading } from '@angular/router';
import { Router } from '@angular/router';
import * as Sentry from '@sentry/angular';

import { routes } from './app.routes';
import { SelectivePreloadingStrategy } from './core/services/ui/selective-preloading.strategy';
import { provideClientHydration, withEventReplay } from '@angular/platform-browser';
import { TranslateLoader, TranslateModule } from '@ngx-translate/core';
import { InMemoryTranslateLoader } from './core/i18n/translate-loader';
import { ThemeService } from './core/services/ui/theme.service';
import { LanguageService } from './core/services/ui/language.service';
import { provideHttpClient, withFetch } from '@angular/common/http';
import { LoggerModule, NGXLogger, TOKEN_LOGGER_RULES_SERVICE } from 'ngx-logger';
import { environment } from '../environments/environment';
import { DatePipe } from '@angular/common';
import { provideHotToastConfig } from '@ngxpert/hot-toast';
import {
  SentryLoggerMonitor,
  SentryLoggerRulesService,
} from './core/services/monitoring/sentry-logger-monitor';
import { reloadOnceForChunkError } from './utils/chunk-reload';

// Reload once on a stale-chunk load error (after a deploy); otherwise report.
function createAppErrorHandler(): ErrorHandler {
  const sentryHandler = Sentry.createErrorHandler({ showDialog: false });

  return {
    handleError(error: unknown): void {
      if (reloadOnceForChunkError(error)) {
        return;
      }
      sentryHandler.handleError(error);
    },
  };
}

// Theme initialization function
export function initializeTheme(themeService: ThemeService): () => Promise<void> {
  return () => {
    return new Promise((resolve) => {
      themeService.initializeTheme();
      setTimeout(resolve, 10);
    });
  };
}

// Language initialization function
export function initializeLanguage(languageService: LanguageService): () => Promise<void> {
  return () => {
    return new Promise((resolve) => {
      languageService.initializeLanguage();
      setTimeout(resolve, 10);
    });
  };
}

export const appConfig: ApplicationConfig = {
  providers: [
    {
      provide: ErrorHandler,
      useValue: createAppErrorHandler(),
    },
    { provide: Sentry.TraceService, deps: [Router] },
    provideAppInitializer(() => void inject(Sentry.TraceService)),
    provideHttpClient(withFetch()),
    provideZoneChangeDetection({ eventCoalescing: true, runCoalescing: true }),
    provideRouter(
      routes,
      withPreloading(SelectivePreloadingStrategy),
      withNavigationErrorHandler((e) => {
        reloadOnceForChunkError(e.error);
      })
    ),
    provideClientHydration(withEventReplay()),
    provideHotToastConfig({
      position: 'top-center',
      duration: 2000,
      dismissible: true,
      autoClose: true,
      stacking: 'depth',
      visibleToasts: 3,
      reverseOrder: true,
      style: {
        borderRadius: '20px',
        zIndex: '99999',
        whiteSpace: 'normal',
        wordBreak: 'break-word',
      },
    }),
    // Initialize translation module with in-memory loader
    importProvidersFrom(
      TranslateModule.forRoot({
        fallbackLang: 'en',
        loader: {
          provide: TranslateLoader,
          useClass: InMemoryTranslateLoader,
        },
      }),
      LoggerModule.forRoot(
        {
          level: environment.logLevel,
          timestampFormat: 'yyyy-MM-dd HH:mm:ss',
          enableSourceMaps: typeof window !== 'undefined' && environment.enableSourceMaps,
          disableFileDetails: environment.disableFileDetails,
          disableConsoleLogging: environment.disableConsoleLogging,
        },
        {
          ruleProvider: { provide: TOKEN_LOGGER_RULES_SERVICE, useClass: SentryLoggerRulesService },
        }
      )
    ),
    DatePipe,
    // Forward ngx-logger output to Sentry (when Sentry is initialized).
    // Registered as an app initializer so it's wired up before any logs flow.
    provideAppInitializer(() => {
      if (environment.sentry?.enabled && environment.sentry.dsn) {
        const logger = inject(NGXLogger);
        logger.registerMonitor(new SentryLoggerMonitor());
      }
    }),
    // Initialize theme on app startup using app initializer
    provideAppInitializer(() => {
      const themeService = inject(ThemeService);
      void initializeTheme(themeService)();
    }),
    // Initialize language on app startup using app initializer
    provideAppInitializer(() => {
      const languageService = inject(LanguageService);
      void initializeLanguage(languageService)();
    }),
  ],
};
