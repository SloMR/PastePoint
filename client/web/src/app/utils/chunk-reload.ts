const CHUNK_LOAD_ERROR =
  /Failed to fetch dynamically imported module|Loading chunk \d+ failed|ChunkLoadError|Importing a module script failed|is not a valid JavaScript MIME type|error loading dynamically imported module/i;

let reloadTriggered = false;

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return CHUNK_LOAD_ERROR.test(message);
}

/**
 * Reloads the page once on a stale-chunk load failure; a page that is already
 * a reload reports instead (loop guard via navigation type, no storage).
 * @returns true if a reload was triggered (caller should stop handling the error).
 */
export function reloadOnceForChunkError(error: unknown): boolean {
  if (typeof window === 'undefined' || !isChunkLoadError(error)) {
    return false;
  }

  if (reloadTriggered) {
    return true;
  }

  const [navigation] = performance.getEntriesByType('navigation');
  const wasReloaded = (navigation as PerformanceNavigationTiming | undefined)?.type === 'reload';
  if (wasReloaded) {
    return false;
  }

  reloadTriggered = true;
  window.location.reload();
  return true;
}
