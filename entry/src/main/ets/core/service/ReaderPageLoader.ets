import { url } from '@kit.ArkTS';
import { normalizeUrl } from '../../common/UrlUtil';
import { ArticleDocument } from '../../model/Article';
import { MetadataService } from './MetadataService';

const DOCUMENT_EXTENSIONS: string[] = [
  '.pdf', '.zip', '.rar', '.7z', '.png', '.jpg', '.jpeg', '.gif', '.webp', '.svg',
  '.mp4', '.mp3', '.m3u8', '.apk', '.dmg', '.exe'
];

export class ReaderPageResult {
  success: boolean = false;
  title: string = '';
  article: ArticleDocument = new ArticleDocument();
  error: string = '';
}

export class ReaderPageLoader {
  static isLikelyDocument(target: string): boolean {
    const normalized = normalizeUrl(target);
    if (normalized.length === 0) {
      return false;
    }
    try {
      const parsed = new url.URL(normalized);
      const path = parsed.pathname.toLowerCase();
      for (let i = 0; i < DOCUMENT_EXTENSIONS.length; i++) {
        if (path.endsWith(DOCUMENT_EXTENSIONS[i])) {
          return false;
        }
      }
      return true;
    } catch (error) {
      return false;
    }
  }

  static async load(target: string): Promise<ReaderPageResult> {
    const result = new ReaderPageResult();
    const normalized = normalizeUrl(target);
    if (normalized.length === 0) {
      result.error = '这个链接打不开';
      return result;
    }
    const metadata = await MetadataService.fetch(normalized, true, true);
    if (!metadata.success) {
      result.error = '这一页没有打开';
      return result;
    }
    if (metadata.article.blocks.length === 0) {
      result.error = '没能翻出这一页的正文';
      return result;
    }
    result.success = true;
    result.title = metadata.title.length > 0 ? metadata.title : metadata.siteName;
    result.article = metadata.article;
    return result;
  }
}
