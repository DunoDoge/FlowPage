import { ArticleDocument } from '../model/Article';

export class ArticleSignature {
  static of(document: ArticleDocument): string {
    let hash = 17;
    for (let i = 0; i < document.blocks.length; i++) {
      const block = document.blocks[i];
      hash = (hash * 31 + block.type + block.level * 7) % 2147483647;
      for (let j = 0; j < block.text.length; j++) {
        hash = (hash * 31 + block.text.charCodeAt(j)) % 2147483647;
      }
    }
    return `${document.blocks.length}:${hash}`;
  }

  static differs(previous: ArticleDocument, next: ArticleDocument): boolean {
    return ArticleSignature.of(previous) !== ArticleSignature.of(next);
  }
}
