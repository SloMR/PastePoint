import { NgxLoggerLevel } from 'ngx-logger';

export const environment = {
  production: true,
  apiUrl: 'pastepoint.com',
  logLevel: NgxLoggerLevel.ERROR,
  enableSourceMaps: false,
  disableFileDetails: true,
  disableConsoleLogging: true,
  sentry: {
    enabled: true,
    dsn: '',
    environment: 'production',
    tracesSampleRate: 0.25,
    enableLogs: true,
  },
};
