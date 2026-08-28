import type { Breadcrumb } from '@sentry/angular';

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
