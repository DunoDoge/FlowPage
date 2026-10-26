import { searchBlocks } from './ReaderSearchCore';

@Concurrent
export function searchReaderTask(haystack: string, starts: number[], needle: string): string {
  return searchBlocks(haystack, starts, needle);
}
