import { taskpool } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { ArticleDocument } from '../../model/Article';
import { searchBlocks, decodeBlockHits } from '../parser/ReaderSearchCore';
import { searchReaderTask } from '../parser/ReaderSearchTask';

const SEARCH_TIMEOUT_MS: number = 2000;
const DOMAIN: number = 0x0000;
const TAG: string = 'flowpage';

export class ReaderSearchIndex {
  haystack: string = '';
  starts: number[] = [];
}

export class ReaderSearchService {
  static buildIndex(article: ArticleDocument): ReaderSearchIndex {
    const index = new ReaderSearchIndex();
    const blocks = article.blocks;
    if (blocks.length === 0) {
      return index;
    }
    const parts: string[] = [];
    let position = 0;
    for (let i = 0; i < blocks.length; i++) {
      const lowered = blocks[i].text.toLowerCase();
      index.starts.push(position);
      parts.push(lowered);
      position += lowered.length + 1;
    }
    index.haystack = parts.join('\n');
    return index;
  }

  static async search(index: ReaderSearchIndex, query: string): Promise<number[]> {
    const needle = query.trim().toLowerCase();
    if (needle.length === 0 || index.starts.length === 0) {
      return [];
    }
    try {
      const task = new taskpool.Task(searchReaderTask, index.haystack, index.starts, needle);
      const encoded = await ReaderSearchService.runWithTimeout(task);
      return decodeBlockHits(encoded);
    } catch (error) {
      // taskpool unavailable or timed out: the synchronous scan keeps search working
      hilog.warn(DOMAIN, TAG, '%{public}s', 'reader search taskpool failed, falling back to sync scan');
      return ReaderSearchService.searchSync(index, needle);
    }
  }

  static searchSync(index: ReaderSearchIndex, needle: string): number[] {
    return decodeBlockHits(searchBlocks(index.haystack, index.starts, needle));
  }

  private static runWithTimeout(task: taskpool.Task): Promise<string> {
    return new Promise<string>((resolve: (value: string) => void, reject: (reason: Object) => void) => {
      let settled = false;
      const timer = setTimeout(() => {
        if (settled) {
          return;
        }
        settled = true;
        try {
          taskpool.cancel(task);
        } catch (error) {
          // the task may already be gone
        }
        reject(new Error('search-timeout'));
      }, SEARCH_TIMEOUT_MS);
      taskpool.execute(task).then((result: Object) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        if (typeof result === 'string') {
          resolve(result);
        } else {
          reject(new Error('search-bad-result'));
        }
      }).catch((error: Object) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(new Error('search-failed'));
      });
    });
  }
}
