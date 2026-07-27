import { environment } from '../../environments/environment';
import { extractSessionCode, extractSessionCodeFromUrl } from './session-link.util';

describe('session-link.util', () => {
  const code = 'AbCd123456';
  const inviteUrl = `https://${environment.webUrl}/private/${code}`;
  const foreignUrl = `https://evil.example.com/private/${code}`;

  describe('extractSessionCodeFromUrl', () => {
    it('returns the code from an invite URL on our own host', () => {
      expect(extractSessionCodeFromUrl(inviteUrl)).toBe(code);
    });

    it('refuses a bare code, so a stray QR cannot join a session', () => {
      expect(extractSessionCodeFromUrl(code)).toBeNull();
    });

    it('refuses an invite URL on a foreign host', () => {
      expect(extractSessionCodeFromUrl(foreignUrl)).toBeNull();
    });

    it('refuses a path segment that is not a valid code', () => {
      expect(extractSessionCodeFromUrl(`https://${environment.webUrl}/private/short`)).toBeNull();
      expect(
        extractSessionCodeFromUrl(`https://${environment.webUrl}/private/not-alphanumeric!`)
      ).toBeNull();
    });

    it('refuses a non-private path', () => {
      expect(extractSessionCodeFromUrl(`https://${environment.webUrl}/public/${code}`)).toBeNull();
    });

    it('returns null for input that is not a URL', () => {
      expect(extractSessionCodeFromUrl('not a url')).toBeNull();
    });
  });

  describe('extractSessionCode', () => {
    it('accepts a bare code', () => {
      expect(extractSessionCode(code)).toBe(code);
    });

    it('accepts an invite URL', () => {
      expect(extractSessionCode(inviteUrl)).toBe(code);
    });

    it('trims surrounding whitespace', () => {
      expect(extractSessionCode(`  ${code}  `)).toBe(code);
    });

    it('rejects a code of the wrong length', () => {
      expect(extractSessionCode('ABC')).toBeNull();
      expect(extractSessionCode(`${code}XYZ`)).toBeNull();
    });

    it('rejects empty input', () => {
      expect(extractSessionCode('   ')).toBeNull();
    });

    it('rejects an invite URL on a foreign host', () => {
      expect(extractSessionCode(foreignUrl)).toBeNull();
    });
  });
});
