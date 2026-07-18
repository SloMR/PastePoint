import { NgxLoggerLevel } from 'ngx-logger';

export const environment = {
  production: false,
  apiUrl: '127.0.0.1',
  webUrl: '127.0.0.1',
  logLevel: NgxLoggerLevel.DEBUG,
  enableSourceMaps: true,
  disableFileDetails: false,
  disableConsoleLogging: false,
  sentry: {
    enabled: false,
    dsn: '',
    environment: 'docker-dev',
    tracesSampleRate: 0.25,
    enableLogs: true,
  },
};
