import * as Sentry from '@sentry/angular';
import { INGXLoggerMetadata, INGXLoggerMonitor, NgxLoggerLevel } from 'ngx-logger';

export class SentryLoggerMonitor implements INGXLoggerMonitor {
  onLog(log: INGXLoggerMetadata): void {
    if (!log) {
      return;
    }
    const message = formatMessage(log);

    switch (log.level) {
      case NgxLoggerLevel.FATAL:
      case NgxLoggerLevel.ERROR: {
        const err = pickError(log) ?? new Error(message);
        Sentry.captureException(err, { level: 'error' });
        break;
      }
      case NgxLoggerLevel.WARN: {
        Sentry.logger.warn(message);
        Sentry.addBreadcrumb({ category: 'log', level: 'warning', message });
        break;
      }
      case NgxLoggerLevel.INFO: {
        Sentry.addBreadcrumb({ category: 'log', level: 'info', message });
        break;
      }
      default:
        // LOG / DEBUG / TRACE
        break;
    }
  }
}

function formatMessage(log: INGXLoggerMetadata): string {
  const parts: string[] = [];
  if (log.fileName) {
    parts.push(log.fileName);
  }
  parts.push(typeof log.message === 'string' ? log.message : JSON.stringify(log.message));
  return parts.join(' :: ');
}

function pickError(log: INGXLoggerMetadata): Error | undefined {
  const additional = log.additional;
  if (!Array.isArray(additional)) {
    return undefined;
  }
  for (const value of additional) {
    if (value instanceof Error) {
      return value;
    }
  }
  return undefined;
}
