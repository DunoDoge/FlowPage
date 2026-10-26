import { describe, it, expect } from '@ohos/hypium';
import { ArticleBlock, ArticleBlockType, ArticleDocument } from '../../../main/ets/model/Article';
import {
  searchBlocks,
  decodeBlockHits
} from '../../../main/ets/core/parser/ReaderSearchCore';
import {
  ReaderSearchIndex,
  ReaderSearchService
} from '../../../main/ets/core/service/ReaderSearchService';

function docOf(texts: string[]): ArticleDocument {
  const blocks: ArticleBlock[] = [];
  for (let i = 0; i < texts.length; i++) {
    blocks.push(ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, texts[i]));
  }
  return ArticleDocument.of(blocks);
}

function syncScan(document: ArticleDocument, needle: string): number[] {
  const hits: number[] = [];
  for (let i = 0; i < document.blocks.length; i++) {
    if (document.blocks[i].text.toLowerCase().indexOf(needle) >= 0) {
      hits.push(i);
    }
  }
  return hits;
}

export default function readerSearchTest() {
  describe('ReaderSearchTest', () => {
    it('findsAllBlocksContainingNeedleCaseInsensitively', 0, () => {
      const document = docOf(['第一段 Apple 内容', '第二段没有目标词', '第三段 apple 再现', '']);
      const index = ReaderSearchService.buildIndex(document);
      const encoded = searchBlocks(index.haystack, index.starts, 'apple');
      expect(encoded).assertEqual('0,2');
      const hits = decodeBlockHits(encoded);
      const expected = syncScan(document, 'apple');
      expect(hits.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(hits[i]).assertEqual(expected[i]);
      }
    });

    it('matchesNeedleAtBlockBoundaryButNotAcross', 0, () => {
      const index = ReaderSearchService.buildIndex(docOf(['abc', 'def', 'ab']));
      // 'cdef' spans the separator and must not hit either block
      expect(searchBlocks(index.haystack, index.starts, 'cdef')).assertEqual('');
      // 'abc' ends exactly at block 0's end: hit
      expect(searchBlocks(index.haystack, index.starts, 'abc')).assertEqual('0');
      // needle longer than any block content: no hit
      expect(searchBlocks(index.haystack, index.starts, 'abcdef')).assertEqual('');
    });

    it('rejectsNeedleContainingSeparator', 0, () => {
      const index = ReaderSearchService.buildIndex(docOf(['aa', 'bb']));
      expect(searchBlocks(index.haystack, index.starts, 'a\nb')).assertEqual('');
    });

    it('returnsEmptyOnEmptyInputs', 0, () => {
      expect(searchBlocks('', [], 'x')).assertEqual('');
      const index = ReaderSearchService.buildIndex(docOf(['内容']));
      expect(searchBlocks(index.haystack, index.starts, '')).assertEqual('');
      expect(searchBlocks(index.haystack, index.starts, '   ')).assertEqual('');
    });

    it('buildIndexOffsetsPointAtLoweredBlockTexts', 0, () => {
      const texts = ['ABC', 'de', 'F'];
      const index = ReaderSearchService.buildIndex(docOf(texts));
      expect(index.starts.length).assertEqual(3);
      expect(index.starts[0]).assertEqual(0);
      expect(index.starts[1]).assertEqual(4);
      expect(index.starts[2]).assertEqual(7);
      expect(index.haystack).assertEqual('abc\nde\nf');
    });

    it('searchSyncEqualsPerBlockScan', 0, () => {
      const texts: string[] = [];
      for (let i = 0; i < 200; i++) {
        texts.push(`第 ${i} 段正文，包含 Keyword${i % 3 === 0 ? 'X' : ''} 的内容。`);
      }
      const document = docOf(texts);
      const index = ReaderSearchService.buildIndex(document);
      const viaSync = ReaderSearchService.searchSync(index, 'keywordx');
      const expected = syncScan(document, 'keywordx');
      expect(viaSync.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(viaSync[i]).assertEqual(expected[i]);
      }
    });

    it('decodeBlockHitsParsesAndSkipsInvalidParts', 0, () => {
      const hits = decodeBlockHits('3,17,2048');
      expect(hits.length).assertEqual(3);
      expect(hits[0]).assertEqual(3);
      expect(hits[2]).assertEqual(2048);
      expect(decodeBlockHits('').length).assertEqual(0);
      expect(decodeBlockHits('x,-1,5').length).assertEqual(1);
    });

    it('serviceSearchRunsOffThreadAndMatches', 0, async () => {
      const texts: string[] = [];
      for (let i = 0; i < 500; i++) {
        texts.push(`block ${i} with Needle inside`);
      }
      const document = docOf(texts);
      const index = ReaderSearchService.buildIndex(document);
      const hits = await ReaderSearchService.search(index, 'needle');
      const expected = syncScan(document, 'needle');
      expect(hits.length).assertEqual(expected.length);
      for (let i = 0; i < expected.length; i++) {
        expect(hits[i]).assertEqual(expected[i]);
      }
    });

    it('serviceSearchTrimsAndLowercasesQuery', 0, async () => {
      const document = docOf(['Only Case Insensitive']);
      const index: ReaderSearchIndex = ReaderSearchService.buildIndex(document);
      const hits = await ReaderSearchService.search(index, '  only CASE ');
      expect(hits.length).assertEqual(1);
      expect(hits[0]).assertEqual(0);
    });

    it('serviceSearchReturnsEmptyForBlankQuery', 0, async () => {
      const index = ReaderSearchService.buildIndex(docOf(['内容']));
      const hits = await ReaderSearchService.search(index, '   ');
      expect(hits.length).assertEqual(0);
    });

    it('serviceSearchHandlesEmptyDocument', 0, async () => {
      const index = ReaderSearchService.buildIndex(new ArticleDocument());
      const hits = await ReaderSearchService.search(index, '任何词');
      expect(hits.length).assertEqual(0);
    });
  });
}
