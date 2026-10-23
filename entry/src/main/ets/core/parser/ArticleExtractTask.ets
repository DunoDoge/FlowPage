import { ArticleDocument } from '../../model/Article';
import { ArticleCodec } from '../service/ArticleCodec';
import { ArticleExtractor } from './ArticleExtractor';

@Concurrent
export function extractArticleTask(html: string, title: string, baseUrl: string): string {
  const document: ArticleDocument = ArticleExtractor.extract(html, title, baseUrl);
  return ArticleCodec.encode(document);
}
