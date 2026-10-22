import { ArticleDocument } from './Article';

export enum MetadataApplyResult {
  FAILED = 0,
  WROTE_SNAPSHOT = 1,
  KEPT_OLD = 2,
  EMPTY = 3
}

export function classifyMetadataWrite(
  success: boolean,
  autoSnapshot: boolean,
  hasSnapshot: boolean,
  hasArticle: boolean
): MetadataApplyResult {
  if (!success) {
    return MetadataApplyResult.FAILED;
  }
  if (!autoSnapshot) {
    return hasSnapshot ? MetadataApplyResult.KEPT_OLD : MetadataApplyResult.EMPTY;
  }
  if (hasArticle) {
    return MetadataApplyResult.WROTE_SNAPSHOT;
  }
  return hasSnapshot ? MetadataApplyResult.KEPT_OLD : MetadataApplyResult.EMPTY;
}

export class MetadataResult {
  title: string = '';
  description: string = '';
  siteName: string = '';
  faviconUrl: string = '';
  coverUrl: string = '';
  article: ArticleDocument = new ArticleDocument();
  success: boolean = false;
}
