import { provideHttpClientTesting, HttpTestingController } from '@angular/common/http/testing';
import { provideHttpClient, withXhr } from '@angular/common/http';
import { LoggerModule, NgxLoggerLevel, TOKEN_LOGGER_CONFIG } from 'ngx-logger';
import {
  TranslateModule,
  TranslateLoader,
  TranslateService,
  TranslateStore,
} from '@ngx-translate/core';
import { MockHotToastService } from './mock-toastr.service';
import { MockTranslateService } from './mock-translate.service';
import { of } from 'rxjs';
import { HotToastService } from '@ngxpert/hot-toast';

// Mock translate loader - This is still used for TranslateModule configuration
export class MockTranslateLoader implements TranslateLoader {
  getTranslation() {
    return of({
      APP_TITLE: 'PastePoint',
      TOGGLE_THEME: 'Toggle Theme',
      USER_INFO: 'User Info',
    });
  }
}

export const TestImports = [
  TranslateModule.forRoot({
    loader: { provide: TranslateLoader, useClass: MockTranslateLoader },
  }),
  LoggerModule.forRoot({
    level: NgxLoggerLevel.DEBUG,
    disableConsoleLogging: true,
  }),
];

export const TestProviders = [
  provideHttpClient(withXhr()),
  provideHttpClientTesting(),
  TranslateStore,
  {
    provide: TOKEN_LOGGER_CONFIG,
    useValue: {
      level: NgxLoggerLevel.DEBUG,
      disableConsoleLogging: true,
    },
  },
  {
    provide: HotToastService,
    useClass: MockHotToastService,
  },
  {
    provide: TranslateService,
    useClass: MockTranslateService,
  },
];

export { HttpTestingController };
