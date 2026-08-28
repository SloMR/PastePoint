import { NgxLoggerLevel } from 'ngx-logger';

export const environment = {
  production: true,
  apiUrl: 'pastepoint.com',
  webUrl: 'pastepoint.com',
  logLevel: NgxLoggerLevel.ERROR,
  enableSourceMaps: false,
  disableFileDetails: true,
  disableConsoleLogging: true,
  sentry: {
    enabled: true,
    dsn: 'https://00ffd0bf7c24fb3eb38318cefb4607c3@o4510159565160448.ingest.de.sentry.io/4511350203088976',
    environment: 'production',
    tracesSampleRate: 1.0,
    enableLogs: true,
  },
};
