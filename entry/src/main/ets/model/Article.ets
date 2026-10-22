export enum ArticleBlockType {
  PARAGRAPH = 0,
  HEADING = 1,
  QUOTE = 2,
  LIST_ITEM = 3,
  CODE = 4
}

export class ArticleBlock {
  type: number = ArticleBlockType.PARAGRAPH;
  level: number = 0;
  text: string = '';

  static of(type: number, level: number, text: string): ArticleBlock {
    const block = new ArticleBlock();
    block.type = type;
    block.level = level;
    block.text = text;
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
        kept.push(ArticleBlock.of(block.type, block.level, tail));
      }
      break;
    }
    this.blocks = kept;
  }
}
