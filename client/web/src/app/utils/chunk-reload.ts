const CHUNK_LOAD_ERROR =
  /Failed to fetch dynamically imported module|Loading chunk \d+ failed|ChunkLoadError/i;

export function isChunkLoadError(error: unknown): boolean {
  const message = error instanceof Error ? error.message : String(error);
  return CHUNK_LOAD_ERROR.test(message);
}

/**
 * Reloads the page once when `error` is a stale-chunk load failure.
 * @returns true if a reload was triggered (caller should stop handling the error).
 */
export function reloadOnceForChunkError(error: unknown): boolean {
  if (typeof window === 'undefined' || !isChunkLoadError(error)) {
    return false;
  }

  const [navigation] = performance.getEntriesByType('navigation');
  const wasReloaded = (navigation as PerformanceNavigationTiming | undefined)?.type === 'reload';
  if (wasReloaded) {
    return false;
  }

  window.location.reload();
  return true;
}
