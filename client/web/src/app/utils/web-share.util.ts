import { isPlatformBrowser } from '@angular/common';

/** True when this platform can hand a URL to the OS share sheet. */
export function canWebShare(platformId: object): boolean {
  return isPlatformBrowser(platformId) && typeof navigator.share === 'function';
}

/** Opens the OS share sheet, treating a dismissal as success. */
export async function shareUrl(url: string): Promise<void> {
  try {
    await navigator.share({ url });
  } catch {
    // dismissed
  }
}
