/** Number of peer avatars bundled as `bottts-00.svg` … `bottts-(N-1).svg`. */
export const AVATAR_COUNT = 24;

const AVATAR_BASE = '/icons/avatars';
export const SELF_AVATAR = `${AVATAR_BASE}/bottts-self.svg`;

/** Deterministic, locale-independent string hash (djb2). */
function avatarHash(seed: string): number {
  let hash = 5381;
  for (let i = 0; i < seed.length; i++) {
    hash = ((hash << 5) + hash + seed.charCodeAt(i)) >>> 0;
  }
  return hash;
}

export function avatarFor(name: string, isMine: boolean): string {
  if (isMine) {
    return SELF_AVATAR;
  }

  const index = avatarHash(name) % AVATAR_COUNT;
  return `${AVATAR_BASE}/bottts-${String(index).padStart(2, '0')}.svg`;
}
