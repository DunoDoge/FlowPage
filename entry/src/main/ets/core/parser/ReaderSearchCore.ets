const BLOCK_SEPARATOR: string = '\n';

/**
 * Pure block-search over a prebuilt lowercase haystack. Equivalent to scanning
 * `blocks[i].text.toLowerCase().indexOf(needle) >= 0` per block: matches are
 * case-insensitive and never cross block boundaries; a needle containing the
 * separator cannot match at all. Returns hit block indices as a comma-joined
 * string ('' when no hits), so the value can cross taskpool unchanged.
 */
export function searchBlocks(haystack: string, starts: number[], needle: string): string {
  if (needle.length === 0 || starts.length === 0 || haystack.length === 0) {
    return '';
  }
  if (needle.indexOf(BLOCK_SEPARATOR) >= 0) {
    return '';
  }
  const hits: string[] = [];
  const total = starts.length;
  for (let i = 0; i < total; i++) {
    const start = starts[i];
    const end = i + 1 < total ? starts[i + 1] - BLOCK_SEPARATOR.length : haystack.length;
    if (end - start < needle.length) {
      continue;
    }
    const at = haystack.indexOf(needle, start);
    if (at < 0) {
      // no occurrence beyond this block; later blocks search a suffix only
      break;
    }
    if (at + needle.length <= end) {
      hits.push(i.toString());
    }
  }
  return hits.join(',');
}

export function decodeBlockHits(encoded: string): number[] {
  if (encoded.length === 0) {
    return [];
  }
  const parts = encoded.split(',');
  const hits: number[] = [];
  for (let i = 0; i < parts.length; i++) {
    const value = parseInt(parts[i]);
    if (!isNaN(value) && value >= 0) {
      hits.push(value);
    }
  }
  return hits;
}
