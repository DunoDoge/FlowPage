import { describe, it, expect } from '@ohos/hypium';
import {
  CARD_FIELD_SEPARATOR,
  cardLineOf,
  cardTitleOf,
  parseCardLine,
  parseCardLines
} from '../main/ets/common/CardFormat';
import { HighlightSegment, highlightSegments } from '../main/ets/common/Highlight';
import { splitIntoChunks } from '../main/ets/common/TextUtil';
import { ArticleBlock, ArticleBlockType, ArticleDocument } from '../main/ets/model/Article';
import { ArticleCodec } from '../main/ets/core/service/ArticleCodec';
import { ArticleExtractor } from '../main/ets/core/parser/ArticleExtractor';
import { readerProgressRatio } from '../main/ets/common/ReaderProgress';
import { Limits } from '../main/ets/common/Constants';

function joinedSegments(segments: HighlightSegment[]): string {
  let joined = '';
  for (let i = 0; i < segments.length; i++) {
    joined = joined + segments[i].text;
  }
  return joined;
}

function repeatedText(chunk: string, times: number): string {
  let text = '';
  for (let i = 0; i < times; i++) {
    text = text + chunk;
  }
  return text;
}

export default function localUnitTest() {
  describe('LocalUnitTest', () => {
    it('encodesCardLineWithSeparatorSafeTitle', 0, () => {
      const line = cardLineOf('标\u0001题\n第二行', 'example.com', 'id-1');
      expect(line.indexOf(CARD_FIELD_SEPARATOR)).assertLarger(0);
      expect(line.indexOf('\u0001')).assertEqual(-1);
      expect(line.indexOf('\n')).assertEqual(-1);
      const parsed = parseCardLine(line);
      expect(parsed === undefined).assertFalse();
      if (parsed !== undefined) {
        expect(parsed.title).assertEqual('标 题 第二行');
        expect(parsed.domain).assertEqual('example.com');
        expect(parsed.id).assertEqual('id-1');
      }
      expect(cardTitleOf('a\r\nb')).assertEqual('a  b');
    });

    it('parsesMultipleCardLinesAndSkipsBrokenOnes', 0, () => {
      const raw = `${cardLineOf('甲', 'a.com', '1')}\nbroken\n${cardLineOf('乙', 'b.com', '2')}`;
      const items = parseCardLines(raw);
      expect(items.length).assertEqual(2);
      expect(items[0].id).assertEqual('1');
      expect(items[1].title).assertEqual('乙');
      expect(parseCardLines('').length).assertEqual(0);
      expect(parseCardLine('only-one-field') === undefined).assertTrue();
      const percentTitle = parseCardLine(cardLineOf('甲%01乙', 'a.com', '3'));
      expect(percentTitle === undefined).assertFalse();
      if (percentTitle !== undefined) {
        expect(percentTitle.title).assertEqual('甲%01乙');
      }
    });

    it('highlightsKeywordsCaseInsensitively', 0, () => {
      const first = highlightSegments('HarmonyOS harm', 'HARM');
      expect(joinedSegments(first)).assertEqual('HarmonyOS harm');
      let matched = 0;
      for (let i = 0; i < first.length; i++) {
        if (first[i].matched) {
          matched = matched + 1;
        }
      }
      expect(matched).assertEqual(2);
      expect(highlightSegments('', 'x').length).assertEqual(0);
      expect(highlightSegments('abc', '  ').length).assertEqual(1);
    });

    it('splitsTextIntoChunksWithoutDroppingContent', 0, () => {
      const chunks = splitIntoChunks('第一段\n\n第二段', 100);
      expect(chunks.length).assertEqual(1);
      expect(chunks[0].indexOf('第一段')).assertEqual(0);
      expect(chunks[0].indexOf('第二段')).assertLarger(0);
      const long = splitIntoChunks('aaaaaaaaaaaaaaaaaaaaaaaaa', 10);
      expect(long.length).assertEqual(3);
      expect(long[0].length).assertEqual(10);
      expect(long[2].length).assertEqual(5);
    });

    it('roundTripsStructuredArticleCodec', 0, () => {
      const document = new ArticleDocument();
      document.blocks = [
        ArticleBlock.of(ArticleBlockType.HEADING, 2, '小标题'),
        ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, '第一段 & 第二段'),
        ArticleBlock.of(ArticleBlockType.QUOTE, 0, '一句引用'),
        ArticleBlock.of(ArticleBlockType.LIST_ITEM, 0, '条目一'),
        ArticleBlock.of(ArticleBlockType.CODE, 0, 'let a = 1;\t// tab\nlet b = 2;\\path')
      ];
      const encoded = ArticleCodec.encode(document);
      const decoded = ArticleCodec.decode(encoded);
      expect(decoded.blocks.length).assertEqual(5);
      expect(decoded.blocks[0].type).assertEqual(ArticleBlockType.HEADING);
      expect(decoded.blocks[0].level).assertEqual(2);
      expect(decoded.blocks[2].type).assertEqual(ArticleBlockType.QUOTE);
      expect(decoded.blocks[4].text).assertEqual('let a = 1;\t// tab\nlet b = 2;\\path');
      const legacy = ArticleCodec.decode('第一段\n\n第二段');
      expect(legacy.blocks.length).assertEqual(2);
      expect(legacy.blocks[1].text).assertEqual('第二段');
    });

    it('extractsArticleBlocksAndDropsChrome', 0, () => {
      const html = '<html><head><title>标题</title></head><body>' +
        '<nav>导航</nav><article><h1>分布式事务详解</h1>' +
        '<details class="baseline-indicator high"><summary>Baseline</summary>' +
        '<div class="pill">Widely available</div></details>' +
        '<p>第一段 &amp; &#39;引号&#39;</p>' +
        '<blockquote>一句引用</blockquote>' +
        '<ul><li>条目一</li><li>条目二</li></ul>' +
        '<pre><code>let a = 1;\nlet b = 2;</code></pre>' +
        '<footer>页脚</footer></article></body></html>';
      const document = ArticleExtractor.extract(html, '分布式事务详解 - 站点');
      expect(document.blocks.length).assertEqual(5);
      expect(document.blocks[0].type).assertEqual(ArticleBlockType.PARAGRAPH);
      expect(document.blocks[0].text).assertEqual('第一段 & \'引号\'');
      expect(document.blocks[1].type).assertEqual(ArticleBlockType.QUOTE);
      expect(document.blocks[2].type).assertEqual(ArticleBlockType.LIST_ITEM);
      expect(document.blocks[4].type).assertEqual(ArticleBlockType.CODE);
      const plain = document.plainText();
      expect(plain.indexOf('导航')).assertEqual(-1);
      expect(plain.indexOf('页脚')).assertEqual(-1);
      expect(plain.indexOf('Baseline')).assertEqual(-1);
      expect(plain.indexOf('Widely available')).assertEqual(-1);
      expect(document.blocks[4].text.indexOf('\n')).assertLarger(0);
    });

    it('fallsBackToContentContainerAndPlainText', 0, () => {
      const html = '<html><body><div class="post-content"><p>正文段落</p>' +
        '<div class="share">分享按钮</div></div></body></html>';
      const document = ArticleExtractor.extract(html);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].text).assertEqual('正文段落');
      const inline = ArticleExtractor.extract('<p>没有容器的正文</p>');
      expect(inline.blocks.length).assertEqual(1);
      expect(inline.blocks[0].text).assertEqual('没有容器的正文');
      const empty = ArticleExtractor.extract('');
      expect(empty.blocks.length).assertEqual(0);
    });

    it('keepsArticleTextAfterNestedJunkBlocks', 0, () => {
      const first = '<article><p>前段正文</p><div class="related">' +
        '<div class="share-tools">x</div></div><p>后段正文</p></article>';
      const firstDocument = ArticleExtractor.extract(first);
      expect(firstDocument.plainText().indexOf('前段正文')).assertLargerOrEqual(0);
      expect(firstDocument.plainText().indexOf('后段正文')).assertLargerOrEqual(0);
      expect(firstDocument.plainText().indexOf('share-tools')).assertEqual(-1);

      const second = '<article><div class="comments"><div class="share">share text</div></div>' +
        '<p>被吞掉的正文段落</p></article>';
      const secondDocument = ArticleExtractor.extract(second);
      expect(secondDocument.plainText().indexOf('被吞掉的正文段落')).assertLargerOrEqual(0);
      expect(secondDocument.plainText().indexOf('share text')).assertEqual(-1);
    });

    it('doesNotLetTinyArticleOrContentCandidateHijackPage', 0, () => {
      const longBody = repeatedText('真正的长正文第一段。', 40);
      const teaser = `<article class="teaser">相关推荐</article><main><p>${longBody}</p><p>第二段。</p></main>`;
      const teaserDocument = ArticleExtractor.extract(teaser);
      expect(teaserDocument.plainText().indexOf('相关推荐')).assertEqual(-1);
      expect(teaserDocument.plainText().indexOf('真正的长正文第一段')).assertLargerOrEqual(0);

      const smallCandidate = '<div class="post-title">文章标题</div>' +
        '<div class="story-body"><p>真正的正文第一段。</p><p>第二段。</p></div>';
      const candidateDocument = ArticleExtractor.extract(smallCandidate, '文章标题');
      expect(candidateDocument.blocks.length).assertLarger(0);
      expect(candidateDocument.blocks[0].text.indexOf('真正的正文第一段')).assertLargerOrEqual(0);
      expect(candidateDocument.plainText().indexOf('文章标题')).assertEqual(-1);
    });

    it('keepsRealStoryWhenTeaserArticleCoversMinorityOfBody', 0, () => {
      const teaser = repeatedText('推荐卡片内容。', 65);
      const story = repeatedText('真正的正文内容。', 200);
      const html = `<article class="teaser">${teaser}</article>` +
        `<div class="prose"><p>${story}</p></div>`;
      const document = ArticleExtractor.extract(html);
      // Keeping a stray teaser is acceptable; losing the real story is not.
      expect(document.plainText().indexOf('真正的正文内容')).assertLargerOrEqual(0);
      expect(document.charCount()).assertLargerOrEqual(story.length);
    });

    it('keepsMainHeaderLeadOnPagesWithoutArticle', 0, () => {
      const html = '<main><header><h1>标题</h1><p>导语段落也应该保留。</p></header>' +
        '<p>正文。</p></main>';
      const document = ArticleExtractor.extract(html, '标题');
      expect(document.plainText().indexOf('导语段落也应该保留。')).assertLargerOrEqual(0);
      expect(document.plainText().indexOf('正文。')).assertLargerOrEqual(0);
      expect(document.blocks.length).assertEqual(2);
    });

    it('preservesBreaksLiteralAngleBracketsAndNamedEntities', 0, () => {
      const breaks = ArticleExtractor.extract('<p>第一行<br>第二行</p>');
      expect(breaks.blocks[0].text).assertEqual('第一行\n第二行');

      const literal = ArticleExtractor.extract('<p>5 < 10 且 x > 3</p>');
      expect(literal.blocks[0].text).assertEqual('5 < 10 且 x > 3');

      const entities = ArticleExtractor.extract('<p>A&mdash;B&hellip;&rsquo;&amp;</p>');
      expect(entities.blocks[0].text).assertEqual('A\u2014B\u2026\u2019&');
    });

    it('keepsPreContentInOneCodeBlock', 0, () => {
      const html = '<pre>line1\n<div>line2</div>\nline3</pre>';
      const document = ArticleExtractor.extract(html);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].type).assertEqual(ArticleBlockType.CODE);
      expect(document.blocks[0].text).assertEqual('line1\nline2\nline3');
    });

    it('truncatesArticleAtSnapshotLimit', 0, () => {
      const document = new ArticleDocument();
      document.blocks = [
        ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, repeatedText('正文', 120000))
      ];
      document.truncate(Limits.snapshotBytes);
      expect(document.charCount()).assertEqual(Limits.snapshotBytes);
      const empty = ArticleExtractor.extract('<div></div>');
      expect(empty.blocks.length).assertEqual(0);
      expect(ArticleCodec.decode('').blocks.length).assertEqual(0);
    });

    it('computesReaderProgressFromScrollableContent', 0, () => {
      expect(readerProgressRatio(0, 2000, 800)).assertEqual(0);
      expect(readerProgressRatio(600, 2000, 800)).assertEqual(0.5);
      expect(readerProgressRatio(1200, 2000, 800)).assertEqual(1);
      expect(readerProgressRatio(2000, 2000, 800)).assertEqual(1);
      expect(readerProgressRatio(0, 500, 800)).assertEqual(1);
      expect(readerProgressRatio(100, 0, 800)).assertEqual(0);
      expect(readerProgressRatio(100, 2000, 0)).assertEqual(0);
    });
  });
}
