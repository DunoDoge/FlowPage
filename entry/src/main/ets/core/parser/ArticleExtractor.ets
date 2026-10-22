import { ArticleBlock, ArticleBlockType, ArticleDocument } from '../../model/Article';
import { Limits } from '../../common/Constants';

const LINE_BREAK_MARKER: string = '\uE000';
const MIN_CONTAINER_SCORE: number = 200;
const KNOWN_TAGS: string[] = [
  'html', 'body', 'head', 'title', 'meta', 'link', 'script', 'style', 'noscript',
  'svg', 'iframe', 'template', 'canvas', 'nav', 'header', 'footer', 'aside', 'form',
  'button', 'select', 'option', 'optgroup', 'textarea', 'input', 'label', 'fieldset',
  'legend', 'article', 'main', 'section', 'div', 'span', 'p', 'br', 'hr', 'blockquote',
  'pre', 'code', 'ul', 'ol', 'li', 'h1', 'h2', 'h3', 'h4', 'h5', 'h6', 'table',
  'thead', 'tbody', 'tfoot', 'tr', 'td', 'th', 'caption', 'colgroup', 'col',
  'figure', 'figcaption', 'img', 'picture', 'source', 'video', 'audio', 'track',
  'a', 'strong', 'em', 'b', 'i', 'u', 's', 'small', 'sub', 'sup', 'mark', 'del',
  'ins', 'dl', 'dt', 'dd', 'address', 'details', 'summary', 'time', 'abbr', 'cite',
  'q', 'ruby', 'rt', 'rp', 'bdi', 'bdo', 'wbr', 'area', 'map', 'object', 'param',
  'embed', 'font', 'center', 'big', 'tt', 'strike', 'acronym'
];
const META_NAME_PATTERN: string =
  '(class|id)\\s*=\\s*["\\\']([^"\\\']*(post-meta|entry-meta|article-meta|meta-info|metadata|byline|author|dateline|post-header|entry-header|post-info|entry-info|post-tags|entry-tags|tag-list)[^"\\\']*)["\\\']';
// Names are matched token by token so words like "downloads", "uploads" or
// "unavailable" do not get removed by a bare "ads"/"nav" substring.
const JUNK_NAME_PIECES: string[] = [
  'comment', 'comments', 'share', 'related', 'recommend', 'advert', 'ads',
  'banner', 'cookie', 'breadcrumb', 'social', 'sidebar', 'subscribe', 'toolbar',
  'nav', 'navigation', 'menu', 'footer', 'baseline', 'metadata', 'compat',
  'byline', 'author', 'dateline'
];
const JUNK_NAME_EXACT: string[] = [
  'post-meta', 'entry-meta', 'article-meta', 'meta-info', 'post-header',
  'entry-header', 'post-info', 'entry-info', 'post-tags', 'entry-tags',
  'tag-list', 'article-list'
];
const STRONG_TEASER_NAMES: string[] = ['teaser', 'recommend', 'related', 'promo'];
const WEAK_TEASER_NAMES: string[] = ['card', 'summary'];
const TITLE_SITE_SEPARATORS: string[] = [
  ' - ', ' | ', ' · ', ' — ', ' – ', '｜', '|', '·', '—', '–'
];

class ElementRange {
  start: number = 0;
  end: number = 0;

  static of(start: number, end: number): ElementRange {
    const range = new ElementRange();
    range.start = start;
    range.end = end;
    return range;
  }
}

class ArticleRange {
  start: number = 0;
  openEnd: number = 0;
  closeStart: number = 0;
  end: number = 0;

  static of(start: number, openEnd: number, closeStart: number, end: number): ArticleRange {
    const range = new ArticleRange();
    range.start = start;
    range.openEnd = openEnd;
    range.closeStart = closeStart;
    range.end = end;
    return range;
  }
}

class ContainerCandidate {
  html: string = '';
  score: number = 0;
  semantic: boolean = false;

  static of(html: string, score: number, semantic: boolean): ContainerCandidate {
    const candidate = new ContainerCandidate();
    candidate.html = html;
    candidate.score = score;
    candidate.semantic = semantic;
    return candidate;
  }
}

class BlockContext {
  tag: string = 'body';
  type: number = ArticleBlockType.PARAGRAPH;
  level: number = 0;

  static of(tag: string, type: number, level: number): BlockContext {
    const context = new BlockContext();
    context.tag = tag;
    context.type = type;
    context.level = level;
    return context;
  }
}

function decodeEntities(input: string): string {
  let text = input;
  const numeric = new RegExp('&#(x?[0-9a-fA-F]+);', 'g');
  let result = '';
  let last = 0;
  let match = numeric.exec(text);
  while (match !== null) {
    result = result + text.substring(last, match.index);
    const value = match[1];
    const code = value.charAt(0) === 'x' || value.charAt(0) === 'X'
      ? parseInt(value.substring(1), 16)
      : parseInt(value, 10);
    if (!isNaN(code) && code > 0 && code <= 0x10FFFF) {
      if (code > 0xFFFF) {
        const adjusted = code - 0x10000;
        result = result + String.fromCharCode(0xD800 + (adjusted >> 10));
        result = result + String.fromCharCode(0xDC00 + (adjusted & 0x3FF));
      } else {
        result = result + String.fromCharCode(code);
      }
    } else {
      result = result + match[0];
    }
    last = match.index + match[0].length;
    match = numeric.exec(text);
  }
  result = result + text.substring(last);
  text = result;
  const pairs: string[][] = [
    ['&nbsp;', ' '],
    ['&mdash;', '\u2014'],
    ['&ndash;', '\u2013'],
    ['&hellip;', '\u2026'],
    ['&rsquo;', '\u2019'],
    ['&lsquo;', '\u2018'],
    ['&rdquo;', '\u201D'],
    ['&ldquo;', '\u201C'],
    ['&laquo;', '\u00AB'],
    ['&raquo;', '\u00BB'],
    ['&middot;', '\u00B7'],
    ['&bull;', '\u2022'],
    ['&copy;', '\u00A9'],
    ['&reg;', '\u00AE'],
    ['&trade;', '\u2122'],
    ['&deg;', '\u00B0'],
    ['&times;', '\u00D7'],
    ['&divide;', '\u00F7'],
    ['&frac12;', '\u00BD'],
    ['&euro;', '\u20AC'],
    ['&pound;', '\u00A3'],
    ['&yen;', '\u00A5'],
    ['&lt;', '<'],
    ['&gt;', '>'],
    ['&quot;', '"'],
    ['&apos;', '\''],
    ['&#39;', '\''],
    ['&amp;', '&']
  ];
  for (let i = 0; i < pairs.length; i++) {
    text = text.replace(new RegExp(pairs[i][0], 'g'), pairs[i][1]);
  }
  return text;
}

function cleanBlockText(input: string, isCode: boolean): string {
  let text = decodeEntities(input);
  if (isCode) {
    text = text.split('\r\n').join('\n').split('\r').join('\n');
    const lines = text.split('\n');
    const trimmed: string[] = [];
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].replace(new RegExp('[ \\t]+$', 'g'), '');
      if (trimmed.length === 0 && line.trim().length === 0) {
        continue;
      }
      trimmed.push(line);
    }
    while (trimmed.length > 0 && trimmed[trimmed.length - 1].trim().length === 0) {
      trimmed.pop();
    }
    const kept: string[] = [];
    let blanks = 0;
    for (let i = 0; i < trimmed.length; i++) {
      if (trimmed[i].trim().length === 0) {
        blanks = blanks + 1;
        if (blanks <= 1) {
          kept.push('');
        }
      } else {
        blanks = 0;
        kept.push(trimmed[i]);
      }
    }
    return kept.join('\n').trim();
  }
  text = text.split('\r\n').join('\n').split('\r').join('\n');
  text = text.replace(new RegExp('\\s+', 'g'), ' ').trim();
  const pieces = text.split(LINE_BREAK_MARKER);
  const lines: string[] = [];
  for (let i = 0; i < pieces.length; i++) {
    const line = pieces[i].trim();
    if (line.length === 0 && lines.length === 0) {
      continue;
    }
    lines.push(line);
  }
  while (lines.length > 0 && lines[lines.length - 1].length === 0) {
    lines.pop();
  }
  return lines.join('\n');
}

function strippedTextLength(html: string): number {
  return html.replace(new RegExp('<[a-zA-Z/!?][^>]*>', 'g'), ' ').trim().length;
}

function plainTextOf(html: string): string {
  let text = html;
  text = text.replace(new RegExp('<br\\s*/?>', 'gi'), '\n');
  text = text.replace(new RegExp('</(p|div|li|h[1-6]|blockquote|pre)>', 'gi'), '\n');
  text = text.replace(new RegExp('<[a-zA-Z/!?][^>]*>', 'g'), ' ');
  text = decodeEntities(text);
  text = text.replace(new RegExp('[ \\t\\r]+', 'g'), ' ');
  text = text.replace(new RegExp('\\n\\s*\\n+', 'g'), '\n\n');
  return text.trim();
}

function normalizeTitle(text: string): string {
  return text.split(' ').join('').split('\u3000').join('').split('\n').join('').toLowerCase();
}

function hasCjk(text: string): boolean {
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code >= 0x4E00 && code <= 0x9FFF) {
      return true;
    }
  }
  return false;
}

function stripSiteSuffix(text: string): string {
  let cut = -1;
  for (let i = 0; i < TITLE_SITE_SEPARATORS.length; i++) {
    const index = text.indexOf(TITLE_SITE_SEPARATORS[i]);
    if (index > 0 && (cut < 0 || index < cut)) {
      cut = index;
    }
  }
  return cut > 0 ? text.substring(0, cut).trim() : text;
}

class BlockScanner {
  private source: string = '';
  private blocks: ArticleBlock[] = [];
  private buffer: string = '';
  private stack: BlockContext[] = [BlockContext.of('body', ArticleBlockType.PARAGRAPH, 0)];

  constructor(source: string) {
    this.source = source;
  }

  scan(): ArticleBlock[] {
    const token = new RegExp('<[a-zA-Z/!?][^>]*>|[^<]+|<', 'g');
    let match = token.exec(this.source);
    while (match !== null) {
      const piece = match[0];
      if (piece.length > 1 && piece.charAt(0) === '<') {
        this.handleTag(piece);
      } else {
        this.buffer = this.buffer + piece;
      }
      match = token.exec(this.source);
    }
    this.flush();
    return this.blocks;
  }

  private current(): BlockContext {
    if (this.stack.length === 0) {
      return BlockContext.of('body', ArticleBlockType.PARAGRAPH, 0);
    }
    return this.stack[this.stack.length - 1];
  }

  private flush(): void {
    const context = this.current();
    const text = cleanBlockText(this.buffer, context.type === ArticleBlockType.CODE);
    if (text.length > 0) {
      this.blocks.push(ArticleBlock.of(context.type, context.level, text));
    }
    this.buffer = '';
  }

  private handleTag(token: string): void {
    if (token.length < 2) {
      return;
    }
    if (token.charAt(1) === '!') {
      return;
    }
    if (token.charAt(1) === '?') {
      return;
    }
    const tag = this.tagNameOf(token);
    if (tag.length === 0 || !this.isKnownTag(tag)) {
      this.buffer = this.buffer + token;
      return;
    }
    if (token.substring(0, 2) === '</') {
      this.handleClose(tag);
    } else {
      this.handleOpen(tag);
    }
  }

  private isKnownTag(tag: string): boolean {
    return KNOWN_TAGS.indexOf(tag) >= 0;
  }

  private tagNameOf(token: string): string {
    let start = token.charAt(1) === '/' ? 2 : 1;
    while (start < token.length &&
      (token.charAt(start) === ' ' || token.charAt(start) === '\t' ||
        token.charAt(start) === '\n' || token.charAt(start) === '\r')) {
      start = start + 1;
    }
    let end = start;
    while (end < token.length) {
      const ch = token.charAt(end);
      if (ch === ' ' || ch === '\t' || ch === '\n' || ch === '\r' || ch === '/' || ch === '>') {
        break;
      }
      end = end + 1;
    }
    return token.substring(start, end).toLowerCase();
  }

  private handleOpen(tag: string): void {
    if (this.current().type === ArticleBlockType.CODE) {
      if (tag === 'br') {
        this.buffer = this.buffer + '\n';
      }
      return;
    }
    if (tag === 'br') {
      this.buffer = this.buffer + LINE_BREAK_MARKER;
      return;
    }
    if (tag === 'hr') {
      this.flush();
      return;
    }
    if (tag === 'blockquote') {
      this.flush();
      this.stack.push(BlockContext.of('blockquote', ArticleBlockType.QUOTE, 0));
      return;
    }
    if (tag === 'pre') {
      this.flush();
      this.stack.push(BlockContext.of('pre', ArticleBlockType.CODE, 0));
      return;
    }
    if (tag === 'li') {
      this.flush();
      this.stack.push(BlockContext.of('li', ArticleBlockType.LIST_ITEM, 0));
      return;
    }
    const level = this.headingLevel(tag);
    if (level > 0) {
      this.flush();
      this.stack.push(BlockContext.of(tag, ArticleBlockType.HEADING, level));
      return;
    }
    if (tag === 'p') {
      const top = this.current();
      if (top.tag === 'blockquote' || top.tag === 'li' || top.tag === 'pre') {
        return;
      }
      this.flush();
      this.stack.push(BlockContext.of('p', ArticleBlockType.PARAGRAPH, 0));
      return;
    }
    if (this.isBoundary(tag)) {
      this.flush();
    }
  }

  private handleClose(tag: string): void {
    if (this.current().type === ArticleBlockType.CODE) {
      if (tag === 'pre') {
        this.flush();
        this.popContext();
      }
      return;
    }
    if (tag === 'blockquote') {
      if (this.current().tag === 'blockquote') {
        this.flush();
        this.popContext();
      } else {
        this.flush();
      }
      return;
    }
    if (tag === 'pre') {
      if (this.current().tag === 'pre') {
        this.flush();
        this.popContext();
      } else {
        this.flush();
      }
      return;
    }
    if (tag === 'li') {
      if (this.current().tag === 'li') {
        this.flush();
        this.popContext();
      } else {
        this.flush();
      }
      return;
    }
    const level = this.headingLevel(tag);
    if (level > 0) {
      if (this.current().tag === tag) {
        this.flush();
        this.popContext();
      } else {
        this.flush();
      }
      return;
    }
    if (tag === 'p') {
      if (this.current().tag === 'p') {
        this.flush();
        this.popContext();
      } else {
        this.flush();
      }
      return;
    }
    if (this.isBoundary(tag)) {
      this.flush();
    }
  }

  private popContext(): void {
    if (this.stack.length > 1) {
      this.stack.pop();
    }
  }

  private headingLevel(tag: string): number {
    if (tag === 'h1') {
      return 1;
    }
    if (tag === 'h2') {
      return 2;
    }
    if (tag === 'h3') {
      return 3;
    }
    if (tag === 'h4') {
      return 4;
    }
    if (tag === 'h5') {
      return 5;
    }
    if (tag === 'h6') {
      return 6;
    }
    return 0;
  }

  private isBoundary(tag: string): boolean {
    return tag === 'div' || tag === 'section' || tag === 'article' || tag === 'main' ||
      tag === 'ul' || tag === 'ol' || tag === 'table' || tag === 'thead' ||
      tag === 'tbody' || tag === 'tfoot' || tag === 'tr' || tag === 'td' ||
      tag === 'th' || tag === 'dt' || tag === 'dd' || tag === 'figcaption' ||
      tag === 'caption' || tag === 'address';
  }
}

export class ArticleExtractor {
  static extract(html: string, knownTitle: string = ''): ArticleDocument {
    if (html.trim().length === 0) {
      return new ArticleDocument();
    }
    const source = ArticleExtractor.removeNoise(html);
    // Junk must be gone before scoring: comments/sidebars would otherwise win
    // the body ratio and cause a small but real article to be treated as teaser.
    const body = ArticleExtractor.removeJunkBlocks(ArticleExtractor.bodyInner(source));
    const container = ArticleExtractor.selectContainer(body);
    let blocks = new BlockScanner(container).scan();
    blocks = ArticleExtractor.dropDuplicateTitle(blocks, knownTitle);
    if (blocks.length === 0) {
      const fallback = ArticleDocument.fromPlainText(plainTextOf(container));
      fallback.truncate(Limits.snapshotBytes);
      return fallback;
    }
    const document = ArticleDocument.of(blocks);
    document.truncate(Limits.snapshotBytes);
    return document;
  }

  private static removeNoise(html: string): string {
    let source = html;
    source = source.replace(new RegExp('<!--[\\s\\S]*?-->', 'g'), ' ');
    const tags: string[] = [
      'head', 'script', 'style', 'noscript', 'svg', 'iframe', 'template', 'canvas',
      'nav', 'aside', 'form', 'button', 'select', 'textarea'
    ];
    for (let i = 0; i < tags.length; i++) {
      const tag = tags[i];
      source = source.replace(
        new RegExp('<' + tag + '\\b[^>]*>[\\s\\S]*?<\\/' + tag + '\\s*>', 'gi'),
        ' '
      );
    }
    return ArticleExtractor.stripHeaderFooter(source);
  }

  private static stripHeaderFooter(source: string): string {
    const ranges = ArticleExtractor.contentRanges(source);
    if (ranges.length === 0) {
      return ArticleExtractor.stripTags(source, ['header', 'footer']);
    }
    let result = '';
    let cursor = 0;
    for (let i = 0; i < ranges.length; i++) {
      const range = ranges[i];
      if (range.start < cursor) {
        continue;
      }
      result = result + ArticleExtractor.stripTags(source.substring(cursor, range.start), ['header', 'footer']);
      result = result + source.substring(range.start, range.openEnd);
      result = result + ArticleExtractor.stripTags(source.substring(range.openEnd, range.closeStart), ['footer']);
      result = result + source.substring(range.closeStart, range.end);
      cursor = range.end;
    }
    result = result + ArticleExtractor.stripTags(source.substring(cursor), ['header', 'footer']);
    return result;
  }

  private static stripTags(source: string, names: string[]): string {
    let text = source;
    for (let i = 0; i < names.length; i++) {
      const name = names[i];
      text = text.replace(
        new RegExp('<' + name + '\\b[^>]*>[\\s\\S]*?<\\/' + name + '\\s*>', 'gi'),
        ' '
      );
    }
    return text;
  }

  private static contentRanges(source: string): ArticleRange[] {
    const collected: ArticleRange[] = [];
    ArticleExtractor.collectTagRanges(source, 'article', collected);
    ArticleExtractor.collectTagRanges(source, 'main', collected);
    collected.sort((a: ArticleRange, b: ArticleRange): number => a.start - b.start);
    const merged: ArticleRange[] = [];
    for (let i = 0; i < collected.length; i++) {
      const range = collected[i];
      if (merged.length === 0) {
        merged.push(ArticleRange.of(range.start, range.openEnd, range.closeStart, range.end));
        continue;
      }
      const last = merged[merged.length - 1];
      if (range.start <= last.end) {
        if (range.end > last.end) {
          last.end = range.end;
          last.closeStart = range.closeStart;
        }
        continue;
      }
      merged.push(ArticleRange.of(range.start, range.openEnd, range.closeStart, range.end));
    }
    return merged;
  }

  private static collectTagRanges(source: string, tagName: string, ranges: ArticleRange[]): void {
    const openReg = new RegExp('<' + tagName + '\\b[^>]*>', 'gi');
    let lastEnd = 0;
    let guard = 0;
    let match = openReg.exec(source);
    while (match !== null && guard < 50) {
      guard = guard + 1;
      const openEnd = match.index + match[0].length;
      const closeStart = ArticleExtractor.findMatchingClose(source, tagName, openEnd);
      if (closeStart >= 0) {
        const end = ArticleExtractor.closeTagEnd(source, closeStart);
        if (match.index >= lastEnd) {
          ranges.push(ArticleRange.of(match.index, openEnd, closeStart, end));
          lastEnd = end;
        }
      }
      openReg.lastIndex = openEnd;
      match = openReg.exec(source);
    }
  }

  private static selectContainer(source: string): string {
    const body = ArticleExtractor.bodyInner(source);
    const bodyScore = strippedTextLength(body);
    const candidates: ContainerCandidate[] = [];
    const article = ArticleExtractor.largestTag(source, 'article', true);
    if (article.length > 0) {
      candidates.push(ContainerCandidate.of(article, strippedTextLength(article), true));
    }
    const main = ArticleExtractor.largestTag(source, 'main');
    if (main.length > 0) {
      candidates.push(ContainerCandidate.of(main, strippedTextLength(main), true));
    }
    const content = ArticleExtractor.largestContentCandidate(source);
    if (content.length > 0) {
      candidates.push(ContainerCandidate.of(content, strippedTextLength(content), false));
    }
    let best = '';
    let bestScore = 0;
    let bestSemantic = false;
    for (let i = 0; i < candidates.length; i++) {
      const candidate = candidates[i];
      if (!ArticleExtractor.acceptCandidate(candidate.score, bodyScore)) {
        continue;
      }
      if (candidate.score > bestScore ||
        (candidate.score === bestScore && candidate.semantic && !bestSemantic)) {
        bestScore = candidate.score;
        best = candidate.html;
        bestSemantic = candidate.semantic;
      }
    }
    if (best.length > 0) {
      return best;
    }
    return ArticleExtractor.stripMinorTeaserArticles(body);
  }

  private static acceptCandidate(score: number, bodyScore: number): boolean {
    if (score < MIN_CONTAINER_SCORE) {
      return false;
    }
    if (bodyScore <= 0) {
      return true;
    }
    // A semantic container still has to cover half of the body. A smaller
    // <article> is usually a teaser card and would hide the real story.
    return score >= bodyScore * 0.5;
  }

  private static isJunkNamed(openTag: string): boolean {
    const attr = new RegExp('(class|id)\\s*=\\s*["\\\']([^"\\\']*)["\\\']', 'gi');
    let match = attr.exec(openTag);
    while (match !== null) {
      const names = match[2].toLowerCase().split(new RegExp('[\\s]+'));
      for (let i = 0; i < names.length; i++) {
        const name = names[i];
        if (name.length === 0) {
          continue;
        }
        if (JUNK_NAME_EXACT.indexOf(name) >= 0) {
          return true;
        }
        const pieces = name.split(new RegExp('[-_]+'));
        for (let j = 0; j < pieces.length; j++) {
          if (pieces[j].length > 0 && JUNK_NAME_PIECES.indexOf(pieces[j]) >= 0) {
            return true;
          }
        }
      }
      match = attr.exec(openTag);
    }
    return false;
  }

  // 0 = not a teaser, 1 = weak (card/summary), 2 = strong (teaser/recommend/...).
  // Both strengths are only removed when a semantic content container exists.
  private static teaserStrengthOf(openTag: string): number {
    const attr = new RegExp('(class|id)\\s*=\\s*["\\\']([^"\\\']*)["\\\']', 'gi');
    let strength = 0;
    let match = attr.exec(openTag);
    while (match !== null) {
      const names = match[2].toLowerCase().split(new RegExp('[\\s]+'));
      for (let i = 0; i < names.length; i++) {
        const pieces = names[i].split(new RegExp('[-_]+'));
        for (let j = 0; j < pieces.length; j++) {
          if (STRONG_TEASER_NAMES.indexOf(pieces[j]) >= 0) {
            return 2;
          }
          if (WEAK_TEASER_NAMES.indexOf(pieces[j]) >= 0) {
            strength = 1;
          }
        }
      }
      match = attr.exec(openTag);
    }
    return strength;
  }

  private static isTeaserNamed(openTag: string): boolean {
    return ArticleExtractor.teaserStrengthOf(openTag) > 0;
  }

  private static stripMinorTeaserArticles(source: string): string {
    const body = ArticleExtractor.bodyInner(source);
    const bodyScore = strippedTextLength(body);
    if (bodyScore <= 0) {
      return source;
    }
    const openReg = new RegExp('<article\\b[^>]*>', 'gi');
    const ranges: ElementRange[] = [];
    const scores: number[] = [];
    let teaserScore = 0;
    let guard = 0;
    let match = openReg.exec(source);
    while (match !== null && guard < 100) {
      guard = guard + 1;
      const strength = ArticleExtractor.teaserStrengthOf(match[0]);
      const openEnd = match.index + match[0].length;
      const closeStart = ArticleExtractor.findMatchingClose(source, 'article', openEnd);
      if (closeStart >= 0 && strength > 0) {
        const score = strippedTextLength(source.substring(openEnd, closeStart));
        if (score < bodyScore * 0.5) {
          ranges.push(ElementRange.of(match.index, ArticleExtractor.closeTagEnd(source, closeStart)));
          scores.push(score);
          teaserScore = teaserScore + score;
        }
      }
      openReg.lastIndex = openEnd;
      match = openReg.exec(source);
    }
    if (ranges.length === 0) {
      return source;
    }
    // Never delete teasers when doing so leaves too little non-teaser text.
    const outsideScore = bodyScore > teaserScore ? bodyScore - teaserScore : 0;
    if (outsideScore < MIN_CONTAINER_SCORE) {
      return source;
    }
    // Only another explicit non-teaser <article> justifies dropping a teaser.
    // <main> and content-named wrappers often just enclose the teaser together
    // with unnamed comments, so keeping the teaser is safer.
    const semantic = ArticleExtractor.largestTag(body, 'article', true).length > 0;
    const removable: ElementRange[] = [];
    for (let i = 0; i < ranges.length; i++) {
      const allowed = semantic;
      if (allowed && scores[i] <= outsideScore) {
        removable.push(ranges[i]);
      }
    }
    if (removable.length === 0) {
      return source;
    }
    removable.sort((a: ElementRange, b: ElementRange): number => a.start - b.start);
    let result = '';
    let cursor = 0;
    for (let i = 0; i < removable.length; i++) {
      if (removable[i].start < cursor) {
        continue;
      }
      result = result + source.substring(cursor, removable[i].start) + ' ';
      cursor = removable[i].end;
    }
    return result + source.substring(cursor);
  }

  private static isMetaNamed(openTag: string): boolean {
    return new RegExp(META_NAME_PATTERN, 'i').test(openTag);
  }

  private static largestTag(source: string, tagName: string, skipTeaser: boolean = false): string {
    const openReg = new RegExp('<' + tagName + '\\b[^>]*>', 'gi');
    let best = '';
    let bestScore = 0;
    let guard = 0;
    let match = openReg.exec(source);
    while (match !== null && guard < 200) {
      guard = guard + 1;
      const openEnd = match.index + match[0].length;
      const closeStart = ArticleExtractor.findMatchingClose(source, tagName, openEnd);
      const skipped = ArticleExtractor.isJunkNamed(match[0]) ||
        (skipTeaser && ArticleExtractor.isTeaserNamed(match[0]));
      if (closeStart >= 0 && !skipped) {
        const inner = source.substring(openEnd, closeStart);
        const score = strippedTextLength(inner);
        if (score > bestScore) {
          bestScore = score;
          best = inner;
        }
      }
      openReg.lastIndex = openEnd;
      match = openReg.exec(source);
    }
    return best;
  }

  private static largestContentCandidate(source: string): string {
    const openReg = new RegExp('<(div|section)\\b[^>]*>', 'gi');
    const attrPattern = new RegExp(
      '(class|id)\\s*=\\s*["\\\']([^"\\\']*(article|content|post|entry|markdown|rich_media|js_content)[^"\\\']*)["\\\']',
      'i'
    );
    let best = '';
    let bestScore = 0;
    let guard = 0;
    let match = openReg.exec(source);
    while (match !== null && guard < 120) {
      guard = guard + 1;
      const tagName = match[1].toLowerCase();
      const openTag = match[0];
      const openEnd = match.index + openTag.length;
      if (attrPattern.test(openTag) && !ArticleExtractor.isMetaNamed(openTag) &&
        !ArticleExtractor.isJunkNamed(openTag) && !ArticleExtractor.isTeaserNamed(openTag)) {
        const closeStart = ArticleExtractor.findMatchingClose(source, tagName, openEnd);
        if (closeStart >= 0) {
          const inner = source.substring(openEnd, closeStart);
          const score = strippedTextLength(inner);
          if (score > bestScore) {
            bestScore = score;
            best = inner;
          }
        }
      }
      openReg.lastIndex = openEnd;
      match = openReg.exec(source);
    }
    return best;
  }

  private static findMatchingClose(source: string, tagName: string, openEnd: number): number {
    const token = new RegExp('<' + tagName + '\\b[^>]*>|<\\/' + tagName + '\\s*>', 'gi');
    token.lastIndex = openEnd;
    let depth = 1;
    let match = token.exec(source);
    while (match !== null) {
      if (match[0].substring(0, 2) === '</') {
        depth = depth - 1;
      } else {
        depth = depth + 1;
      }
      if (depth === 0) {
        return match.index;
      }
      match = token.exec(source);
    }
    return -1;
  }

  private static closeTagEnd(source: string, closeStart: number): number {
    const gt = source.indexOf('>', closeStart);
    return gt >= 0 ? gt + 1 : closeStart;
  }

  private static removeJunkBlocks(container: string): string {
    const openReg = new RegExp('<(div|section|article|aside|nav|header|footer|ul|ol|details)\\b[^>]*>', 'gi');
    const ranges: ElementRange[] = [];
    let guard = 0;
    let match = openReg.exec(container);
    while (match !== null && guard < 200) {
      guard = guard + 1;
      const tagName = match[1].toLowerCase();
      const openEnd = match.index + match[0].length;
      if (ArticleExtractor.isJunkNamed(match[0])) {
        const closeStart = ArticleExtractor.findMatchingClose(container, tagName, openEnd);
        if (closeStart >= 0) {
          ranges.push(ElementRange.of(match.index, ArticleExtractor.closeTagEnd(container, closeStart)));
        }
      }
      openReg.lastIndex = openEnd;
      match = openReg.exec(container);
    }
    ranges.sort((a: ElementRange, b: ElementRange): number => a.start - b.start);
    const merged: ElementRange[] = [];
    for (let i = 0; i < ranges.length; i++) {
      const range = ranges[i];
      if (merged.length === 0) {
        merged.push(ElementRange.of(range.start, range.end));
        continue;
      }
      const last = merged[merged.length - 1];
      if (range.start <= last.end) {
        if (range.end > last.end) {
          last.end = range.end;
        }
      } else {
        merged.push(ElementRange.of(range.start, range.end));
      }
    }
    let result = '';
    let cursor = 0;
    for (let i = 0; i < merged.length; i++) {
      result = result + container.substring(cursor, merged[i].start) + ' ';
      cursor = merged[i].end;
    }
    result = result + container.substring(cursor);
    return result;
  }

  private static bodyInner(source: string): string {
    const lower = source.toLowerCase();
    const open = lower.indexOf('<body');
    if (open < 0) {
      return source;
    }
    const openEnd = source.indexOf('>', open);
    if (openEnd < 0) {
      return source;
    }
    const close = lower.lastIndexOf('</body');
    if (close < 0) {
      return source.substring(openEnd + 1);
    }
    return source.substring(openEnd + 1, close);
  }

  private static dropDuplicateTitle(blocks: ArticleBlock[], knownTitle: string): ArticleBlock[] {
    if (blocks.length < 2 || knownTitle.length === 0) {
      return blocks;
    }
    const pageTitle = normalizeTitle(stripSiteSuffix(knownTitle));
    if (pageTitle.length === 0) {
      return blocks;
    }
    const limit = Math.min(blocks.length, 5);
    for (let i = 0; i < limit; i++) {
      const block = blocks[i];
      if (block.type !== ArticleBlockType.HEADING && block.type !== ArticleBlockType.PARAGRAPH) {
        break;
      }
      if (ArticleExtractor.titleMatches(block.text, pageTitle)) {
        const remaining = blocks.slice(0);
        remaining.splice(i, 1);
        return remaining;
      }
      // A short date/author line may sit in front of the repeated heading.
      if (!ArticleExtractor.looksLikeMetaLine(block.text)) {
        break;
      }
    }
    return blocks;
  }

  private static titleMatches(blockText: string, pageTitle: string): boolean {
    const direct = normalizeTitle(stripSiteSuffix(blockText));
    if (direct.length === 0) {
      return false;
    }
    if (direct === pageTitle || normalizeTitle(blockText) === pageTitle) {
      return true;
    }
    if (direct.indexOf(pageTitle) === 0 && pageTitle.length >= 2) {
      const tail = direct.substring(pageTitle.length);
      if (tail.length > 0 && tail.length <= 24) {
        const next = tail.charAt(0);
        if (next === ':' || next === '：' || next === '-' || next === '—' ||
          next === '–' || next === '|' || next === '·' || next === '_') {
          return true;
        }
      }
    }
    if (pageTitle.indexOf(direct) === 0) {
      if (direct.length >= 6) {
        return true;
      }
      if (hasCjk(direct) && direct.length >= 2 && pageTitle.length - direct.length <= 24) {
        return true;
      }
    }
    return false;
  }

  private static looksLikeMetaLine(text: string): boolean {
    const trimmed = text.trim();
    if (trimmed.length === 0 || trimmed.length > 40) {
      return false;
    }
    if (new RegExp('[。！？.!?]').test(trimmed)) {
      return false;
    }
    if (new RegExp('[0-9]').test(trimmed)) {
      return true;
    }
    const words: string[] = ['作者', '编辑', '来源', '发布', '更新', '时间', '阅读', 'by ', 'By ', '@', '·', '|'];
    for (let i = 0; i < words.length; i++) {
      if (trimmed.indexOf(words[i]) >= 0) {
        return true;
      }
    }
    return false;
  }
}
