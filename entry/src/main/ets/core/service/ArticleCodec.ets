import { ArticleBlock, ArticleBlockType, ArticleDocument } from '../../model/Article';

const HEADER: string = 'FLOWPAGE-ARTICLE-1';

export class ArticleCodec {
  static encode(document: ArticleDocument): string {
    const lines: string[] = [HEADER];
    for (let i = 0; i < document.blocks.length; i++) {
      const block = document.blocks[i];
      if (block.text.length === 0) {
        continue;
      }
      lines.push(`${ArticleCodec.typeCode(block)}\t${ArticleCodec.escape(block.text)}`);
    }
    return lines.join('\n');
  }

  static decode(text: string): ArticleDocument {
    if (text.length === 0) {
      return new ArticleDocument();
    }
    const normalized = text.split('\r\n').join('\n').split('\r').join('\n');
    const lines = normalized.split('\n');
    if (lines[0] !== HEADER) {
      return ArticleDocument.fromPlainText(normalized);
    }
    const blocks: ArticleBlock[] = [];
    for (let i = 1; i < lines.length; i++) {
      const line = lines[i];
      if (line.length === 0) {
        continue;
      }
      const tab = line.indexOf('\t');
      if (tab <= 0) {
        continue;
      }
      const code = line.substring(0, tab);
      const content = ArticleCodec.unescape(line.substring(tab + 1));
      if (content.length === 0) {
        continue;
      }
      blocks.push(ArticleCodec.blockOf(code, content));
    }
    const document = new ArticleDocument();
    document.blocks = blocks;
    return document;
  }

  private static typeCode(block: ArticleBlock): string {
    if (block.type === ArticleBlockType.HEADING) {
      const level = block.level < 1 ? 1 : (block.level > 6 ? 6 : block.level);
      return `h${level}`;
    }
    if (block.type === ArticleBlockType.QUOTE) {
      return 'q';
    }
    if (block.type === ArticleBlockType.LIST_ITEM) {
      return 'li';
    }
    if (block.type === ArticleBlockType.CODE) {
      return 'c';
    }
    return 'p';
  }

  private static blockOf(code: string, text: string): ArticleBlock {
    if (code.length === 2 && code.charAt(0) === 'h') {
      const level = parseInt(code.substring(1), 10);
      if (!isNaN(level) && level >= 1 && level <= 6) {
        return ArticleBlock.of(ArticleBlockType.HEADING, level, text);
      }
    }
    if (code === 'q') {
      return ArticleBlock.of(ArticleBlockType.QUOTE, 0, text);
    }
    if (code === 'li') {
      return ArticleBlock.of(ArticleBlockType.LIST_ITEM, 0, text);
    }
    if (code === 'c') {
      return ArticleBlock.of(ArticleBlockType.CODE, 0, text);
    }
    return ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, text);
  }

  private static escape(text: string): string {
    let escaped = '';
    for (let i = 0; i < text.length; i++) {
      const ch = text.charAt(i);
      if (ch === '\\') {
        escaped = `${escaped}\\\\`;
      } else if (ch === '\n') {
        escaped = `${escaped}\\n`;
      } else if (ch === '\r') {
        continue;
      } else if (ch === '\t') {
        escaped = `${escaped}\\t`;
      } else {
        escaped = `${escaped}${ch}`;
      }
    }
    return escaped;
  }

  private static unescape(text: string): string {
    let plain = '';
    let index = 0;
    while (index < text.length) {
      const ch = text.charAt(index);
      if (ch === '\\' && index + 1 < text.length) {
        const next = text.charAt(index + 1);
        if (next === 'n') {
          plain = `${plain}\n`;
          index = index + 2;
          continue;
        }
        if (next === 't') {
          plain = `${plain}\t`;
          index = index + 2;
          continue;
        }
        if (next === '\\') {
          plain = `${plain}\\`;
          index = index + 2;
          continue;
        }
      }
      plain = `${plain}${ch}`;
      index = index + 1;
    }
    return plain;
  }
}
