import type { Breadcrumb, Event } from '@sentry/angular';

const SESSION_CODE_IN_PATH = /(\/(?:private|ws)\/)[A-Za-z0-9]+/g;

/**
 * Redacts private session codes from URLs/messages
 */
export function scrubSessionCodes(text: string): string {
  return text.replace(SESSION_CODE_IN_PATH, '$1[code]');
}

/**
 * Scrubs one Sentry breadcrumb in place
 */
export function scrubBreadcrumb(breadcrumb: Breadcrumb): Breadcrumb {
  if (breadcrumb.message) {
    breadcrumb.message = scrubSessionCodes(breadcrumb.message);
  }

  for (const key of ['url', 'from', 'to'] as const) {
    const value = breadcrumb.data?.[key];
    if (typeof value === 'string' && breadcrumb.data) {
      breadcrumb.data[key] = scrubSessionCodes(value);
    }
  }
  return breadcrumb;
}

/** Redacts session codes from every string value of span or trace data. */
function scrubData(data: Record<string, unknown> | undefined): void {
  if (!data) return;
  for (const [key, value] of Object.entries(data)) {
    if (typeof value === 'string') {
      data[key] = scrubSessionCodes(value);
    }
  }
}

/**
 * Strips identifying request details and session codes from an error or transaction event in place
 */
export function scrubEvent<T extends Event>(event: T): T {
  event.user = { ip_address: '127.0.0.1' };
  delete event.server_name;
  if (event.request) {
    delete event.request.cookies;
    delete event.request.data;
    delete event.request.query_string;
    if (event.request.url) {
      event.request.url = scrubSessionCodes(event.request.url);
    }
    // The referring page can be a private session URL
    for (const name of Object.keys(event.request.headers ?? {})) {
      if (name.toLowerCase() === 'referer') {
        delete event.request.headers?.[name];
      }
    }
  }
  if (event.transaction) {
    event.transaction = scrubSessionCodes(event.transaction);
  }
  if (event.message) {
    event.message = scrubSessionCodes(event.message);
  }
  for (const exception of event.exception?.values ?? []) {
    if (exception.value) {
      exception.value = scrubSessionCodes(exception.value);
    }
  }
  scrubData(event.contexts?.trace?.data);
  for (const span of event.spans ?? []) {
    if (span.description) {
      span.description = scrubSessionCodes(span.description);
    }
    scrubData(span.data);
  }
  // Browser-derived locale signals
  if (event.contexts?.['device']) {
    delete event.contexts['device']['timezone'];
    delete event.contexts['device']['locale'];
  }
  if (event.contexts?.['culture']) {
    delete event.contexts['culture'];
  }
  return event;
}
