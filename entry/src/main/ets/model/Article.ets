export enum ArticleBlockType {
  PARAGRAPH = 0,
  HEADING = 1,
  QUOTE = 2,
  LIST_ITEM = 3,
  CODE = 4
}

export class ArticleLink {
  start: number = 0;
  end: number = 0;
  url: string = '';

  static of(start: number, end: number, url: string): ArticleLink {
    const link = new ArticleLink();
    link.start = start;
    link.end = end;
    link.url = url;
    return link;
  }
}

export class ArticleBlock {
  type: number = ArticleBlockType.PARAGRAPH;
  level: number = 0;
  text: string = '';
  links: ArticleLink[] = [];

  static of(type: number, level: number, text: string, links: ArticleLink[] = []): ArticleBlock {
    const block = new ArticleBlock();
    block.type = type;
    block.level = level;
    block.text = text;
    block.links = links;
    return block;
  }
}

export class ReaderTocEntry {
  index: number = 0;
  level: number = 0;
  text: string = '';

  static of(index: number, level: number, text: string): ReaderTocEntry {
    const entry = new ReaderTocEntry();
    entry.index = index;
    entry.level = level;
    entry.text = text;
    return entry;
  }
}

export class ArticleDocument {
  blocks: ArticleBlock[] = [];

  static of(blocks: ArticleBlock[]): ArticleDocument {
    const document = new ArticleDocument();
    document.blocks = blocks;
    return document;
  }

  static fromPlainText(text: string): ArticleDocument {
    const document = new ArticleDocument();
    if (text.length === 0) {
      return document;
    }
    const normalized = text.split('\r\n').join('\n').split('\r').join('\n');
    const lines = normalized.split('\n');
    let buffer = '';
    for (let i = 0; i < lines.length; i++) {
      const line = lines[i].trim();
      if (line.length === 0) {
        if (buffer.length > 0) {
          document.blocks.push(ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, buffer));
          buffer = '';
        }
        continue;
      }
      buffer = buffer.length === 0 ? line : `${buffer} ${line}`;
    }
    if (buffer.length > 0) {
      document.blocks.push(ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, buffer));
    }
    return document;
  }

  plainText(): string {
    let text = '';
    for (let i = 0; i < this.blocks.length; i++) {
      const block = this.blocks[i];
      if (block.text.length === 0) {
        continue;
      }
      text = text.length === 0 ? block.text : `${text}\n\n${block.text}`;
    }
    return text;
  }

  charCount(): number {
    let total = 0;
    for (let i = 0; i < this.blocks.length; i++) {
      total = total + this.blocks[i].text.length;
    }
    return total;
  }

  truncate(maxChars: number): void {
    if (maxChars <= 0 || this.charCount() <= maxChars) {
      return;
    }
    const kept: ArticleBlock[] = [];
    let total = 0;
    for (let i = 0; i < this.blocks.length; i++) {
      const block = this.blocks[i];
      const remaining = maxChars - total;
      if (remaining <= 0) {
        break;
      }
      if (block.text.length <= remaining) {
        kept.push(block);
        total = total + block.text.length;
        continue;
      }
      const tail = block.text.substring(0, remaining).trim();
      if (tail.length > 0) {
        const keptBlock = ArticleBlock.of(block.type, block.level, tail);
        keptBlock.links = ArticleDocument.clampLinks(block.links, tail.length);
        kept.push(keptBlock);
      }
      break;
    }
    this.blocks = kept;
  }

  private static clampLinks(links: ArticleLink[], maxLength: number): ArticleLink[] {
    const kept: ArticleLink[] = [];
    for (let i = 0; i < links.length; i++) {
      const link = links[i];
      if (link.start >= maxLength) {
        break;
      }
      const end = Math.min(link.end, maxLength);
      if (end > link.start) {
        kept.push(ArticleLink.of(link.start, end, link.url));
      }
    }
    return kept;
  }
}
