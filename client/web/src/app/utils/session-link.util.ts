import { environment } from '../../environments/environment';

const SESSION_CODE_PATTERN = /^[a-zA-Z0-9]{10}$/;

/** Invite URL → its code. Host-checked, and a bare code is refused. */
export function extractSessionCodeFromUrl(payload: string): string | null {
  try {
    const url = new URL(payload.trim());
    if (url.host !== environment.webUrl) return null;

    const parts = url.pathname.split('/').filter(Boolean);
    if (parts.length === 2 && parts[0] === 'private' && SESSION_CODE_PATTERN.test(parts[1])) {
      return parts[1];
    }
  } catch {
    // not a URL
  }

  return null;
}

/** Typed or pasted input → its code, accepting a bare code or an invite URL. */
export function extractSessionCode(payload: string): string | null {
  const trimmed = payload.trim();
  if (!trimmed) return null;

  if (SESSION_CODE_PATTERN.test(trimmed)) {
    return trimmed;
  }

  return extractSessionCodeFromUrl(trimmed);
}
