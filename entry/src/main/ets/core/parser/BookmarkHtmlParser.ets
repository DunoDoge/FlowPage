import { ImportedBookmark } from '../../model/ImportResult';
import { domainOf, normalizeUrl } from '../../common/UrlUtil';

export class ParsedBookmarks {
  items: ImportedBookmark[] = [];
  invalidCount: number = 0;
  inFileDuplicates: number = 0;
  invalidUrls: string[] = [];
  // Top-level folder name -> browser semantic kind ('toolbar' | 'unfiled'),
  // from PERSONAL_TOOLBAR_FOLDER / UNFILED_BOOKMARKS_FOLDER H3 attributes.
  // First marker wins for duplicate names; deeper H3s are ignored.
  topMarks: Map<string, string> = new Map();
}

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
    text = text.split(pairs[i][0]).join(pairs[i][1]);
  }
  return text;
}

// Module-level regexes: parse() runs per imported line, keep them shared.
const TAG_STRIP_RE = new RegExp('<[^>]+>', 'g');
const SPACE_RE = new RegExp('\\s+', 'g');
const FOLDER_RE = new RegExp('<H3[^>]*>([\\s\\S]*?)</H3>', 'i');
const ANCHOR_RE = new RegExp('<A\\s+[^>]*>([\\s\\S]*?)</A>', 'i');
const HREF_RE = new RegExp('href\\s*=\\s*["\\\']([^"\\\']+)["\\\']', 'i');
const ADD_DATE_RE = new RegExp('ADD_DATE\\s*=\\s*["\\\']?([0-9]+)', 'i');
const TOOLBAR_RE = new RegExp('PERSONAL_TOOLBAR_FOLDER\\s*=\\s*["\\\']?(true|1)', 'i');
const UNFILED_RE = new RegExp('UNFILED_BOOKMARKS_FOLDER\\s*=\\s*["\\\']?(true|1)', 'i');

function cleanText(input: string): string {
  let text = input;
  text = text.replace(TAG_STRIP_RE, ' ');
  text = decodeEntities(text);
  text = text.replace(SPACE_RE, ' ');
  return text.trim();
}

export class BookmarkHtmlParser {
  static parse(html: string): ImportedBookmark[] {
    return BookmarkHtmlParser.parseAll(html).items;
  }

  static parseAll(html: string): ParsedBookmarks {
    const lines = html.split('\n');
    const parsed = new ParsedBookmarks();
    const stack: string[] = [];
    const seen = new Set<string>();
    let pendingFolder = '';

    for (let i = 0; i < lines.length; i++) {
      const line = lines[i];

      if (line.indexOf('<H3') >= 0) {
        const folderMatch = FOLDER_RE.exec(line);
        pendingFolder = folderMatch !== null ? cleanText(folderMatch[1]) : '';
        // Marker semantics only exist at the root level (stack holds just the
        // outer DL's empty entry); tolerate files missing the outer wrapper.
        if (pendingFolder.length > 0 && stack.length <= 1 && !parsed.topMarks.has(pendingFolder)) {
          if (TOOLBAR_RE.test(line)) {
            parsed.topMarks.set(pendingFolder, 'toolbar');
          } else if (UNFILED_RE.test(line)) {
            parsed.topMarks.set(pendingFolder, 'unfiled');
          }
        }
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

      const hrefMatch = HREF_RE.exec(line);
      if (hrefMatch === null) {
        continue;
      }
      const rawUrl = decodeEntities(hrefMatch[1]);
      const normalized = normalizeUrl(rawUrl);
      if (normalized.length === 0) {
        parsed.invalidCount = parsed.invalidCount + 1;
        parsed.invalidUrls.push(rawUrl);
        continue;
      }
      if (seen.has(normalized)) {
        parsed.inFileDuplicates = parsed.inFileDuplicates + 1;
        continue;
      }
      seen.add(normalized);

      const anchorMatch = ANCHOR_RE.exec(line);
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

      // ADD_DATE is unix seconds; reject absurd values (0 or far future).
      let addedAt = 0;
      const addDateMatch = ADD_DATE_RE.exec(line);
      if (addDateMatch !== null) {
        const seconds = Number(addDateMatch[1]);
        const futureGuard = Math.floor(Date.now() / 1000) + 86400;
        if (Number.isFinite(seconds) && seconds > 0 && seconds < futureGuard) {
          addedAt = seconds * 1000;
        }
      }

      const bookmark = new ImportedBookmark();
      bookmark.url = rawUrl;
      bookmark.title = title;
      bookmark.segments = parts;
      bookmark.addedAt = addedAt;
      parsed.items.push(bookmark);
    }
    return parsed;
  }

  static countFolders(items: ImportedBookmark[]): number {
    const set = new Set<string>();
    for (let i = 0; i < items.length; i++) {
      const path = items[i].segments.join('/');
      if (path.length > 0) {
        set.add(path);
      }
    }
    return set.size;
  }
}
