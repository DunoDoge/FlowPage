import { ImportedBookmark } from '../../model/ImportResult';
import { domainOf, normalizeUrl } from '../../common/UrlUtil';

function decodeEntities(input: string): string {
  let text = input;
  const pairs: string[][] = [
    ['&amp;', '&'],
    ['&lt;', '<'],
    ['&gt;', '>'],
    ['&quot;', '"'],
    ['&#39;', '\''],
    ['&apos;', '\''],
    ['&nbsp;', ' ']
  ];
  for (let i = 0; i < pairs.length; i++) {
    text = text.replace(new RegExp(pairs[i][0], 'g'), pairs[i][1]);
  }
  return text;
}

function cleanText(input: string): string {
  let text = input;
  text = text.replace(new RegExp('<[^>]+>', 'g'), ' ');
  text = decodeEntities(text);
  text = text.replace(new RegExp('\\s+', 'g'), ' ');
  return text.trim();
}

export class BookmarkHtmlParser {
  static parse(html: string): ImportedBookmark[] {
    const lines = html.split('\n');
    const result: ImportedBookmark[] = [];
    const stack: string[] = [];
    const seen = new Set<string>();
    let pendingFolder = '';

    const folderReg = new RegExp('<H3[^>]*>([\\s\\S]*?)</H3>', 'i');
    const anchorReg = new RegExp('<A\\s+[^>]*>([\\s\\S]*?)</A>', 'i');
    const hrefReg = new RegExp('href\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      if (line.indexOf('<H3') >= 0) {
        const folderMatch = folderReg.exec(line);
        pendingFolder = folderMatch !== null ? cleanText(folderMatch[1]) : '';
        continue;
      }

      if (line.indexOf('<DL') >= 0) {
        stack.push(pendingFolder);
        pendingFolder = '';
        continue;
      }

      if (line.indexOf('</DL>') >= 0) {
        if (stack.length > 0) {
          stack.pop();
        }
        continue;
      }

      if (line.indexOf('<A') < 0) {
        continue;
      }

      const hrefMatch = hrefReg.exec(line);
      if (hrefMatch === null) {
        continue;
      }
      const rawUrl = decodeEntities(hrefMatch[1]);
      const normalized = normalizeUrl(rawUrl);
      if (normalized.length === 0) {
        continue;
      }
      if (seen.has(normalized)) {
        continue;
      }
      seen.add(normalized);

      const anchorMatch = anchorReg.exec(line);
      let title = anchorMatch !== null ? cleanText(anchorMatch[1]) : '';
      if (title.length === 0) {
        title = domainOf(rawUrl);
      }

      const parts: string[] = [];
      for (let j = 0; j < stack.length; j++) {
        if (stack[j].length > 0) {
          parts.push(stack[j]);
        }
      }
      if (pendingFolder.length > 0) {
        parts.push(pendingFolder);
        pendingFolder = '';
      }

      const bookmark = new ImportedBookmark();
      bookmark.url = rawUrl;
      bookmark.title = title;
      bookmark.folderPath = parts.join('/');
      result.push(bookmark);
    }

    return result;
  }

  static countFolders(items: ImportedBookmark[]): number {
    const set = new Set<string>();
    for (let i = 0; i < items.length; i++) {
      if (items[i].folderPath.length > 0) {
        set.add(items[i].folderPath);
      }
    }
    return set.size;
  }
}
