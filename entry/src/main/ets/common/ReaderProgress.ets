export function readerProgressRatio(yOffset: number, contentBottom: number, viewportHeight: number): number {
  if (!(contentBottom > 0) || !(viewportHeight > 0)) {
    return 0;
  }
  if (contentBottom <= viewportHeight) {
    return 1;
  }
  const scrollable = contentBottom - viewportHeight;
  const offset = yOffset < 0 ? 0 : (yOffset > scrollable ? scrollable : yOffset);
  return offset / scrollable;
}

export function readerBlockProgress(index: number, total: number): number {
  if (total <= 1 || index <= 0) {
    return 0;
  }
  return Math.min(0.99, index / (total - 1));
}
