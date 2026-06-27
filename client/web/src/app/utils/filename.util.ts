/**
 * Filename truncation helpers shared by the chat UI (input chips, message
 * bubbles, sidebar transfer rows) so the elision logic lives in one place.
 */

/** Truncate to `maxLength`, keeping the extension and eliding the tail of the base name. */
export function truncateFilename(filename: string, maxLength = 30): string {
  if (filename.length <= maxLength) {
    return filename;
  }

  const lastDotIndex = filename.lastIndexOf('.');
  if (lastDotIndex === -1) {
    return filename.slice(0, maxLength) + '...';
  }

  const extension = filename.slice(lastDotIndex);
  const baseName = filename.slice(0, lastDotIndex);
  const availableLength = maxLength - extension.length - 3;

  if (availableLength <= 0) {
    return filename.slice(0, maxLength) + '...';
  }

  return baseName.slice(0, availableLength) + '...' + extension;
}

/** Middle-truncate to `maxLength`, keeping head + tail of the base name and the extension. */
export function middleTruncateFilename(name: string, maxLength = 22): string {
  if (name.length <= maxLength) {
    return name;
  }

  const dot = name.lastIndexOf('.');
  const ext = dot > 0 ? name.slice(dot) : '';
  const base = dot > 0 ? name.slice(0, dot) : name;
  const keep = Math.max(maxLength - ext.length - 1, 4);
  const head = Math.ceil(keep / 2);
  const tail = Math.floor(keep / 2);

  return `${base.slice(0, head)}…${base.slice(base.length - tail)}${ext}`;
}
