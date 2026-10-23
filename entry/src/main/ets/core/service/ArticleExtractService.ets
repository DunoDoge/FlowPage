import { taskpool } from '@kit.ArkTS';
import { ArticleDocument } from '../../model/Article';
import { ArticleCodec } from './ArticleCodec';
import { ArticleExtractor } from '../parser/ArticleExtractor';
import { extractArticleTask } from '../parser/ArticleExtractTask';

const TASK_TIMEOUT_MS: number = 4000;

export class ArticleExtractService {
  static async extractAsync(html: string, title: string, baseUrl: string): Promise<ArticleDocument> {
    try {
      const task = new taskpool.Task(extractArticleTask, html, title, baseUrl);
      const encoded = await ArticleExtractService.runWithTimeout(task);
      return ArticleCodec.decode(encoded);
    } catch (error) {
      // A cancelled task may still be running; rebuilding synchronously keeps the reader usable.
    }
    return ArticleExtractor.extract(html, title, baseUrl);
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
        reject(new Error('extract-timeout'));
      }, TASK_TIMEOUT_MS);
      taskpool.execute(task).then((result: Object) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        if (typeof result === 'string') {
          resolve(result);
        } else {
          reject(new Error('extract-bad-result'));
        }
      }).catch((error: Object) => {
        if (settled) {
          return;
        }
        settled = true;
        clearTimeout(timer);
        reject(new Error('extract-failed'));
      });
    });
  }
}
