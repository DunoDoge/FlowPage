import { describe, it, expect } from '@ohos/hypium';
import { ArticleBlock, ArticleBlockType, ArticleDocument, ArticleLink } from '../../../main/ets/model/Article';
import { ArticleSignature } from '../../../main/ets/common/ArticleSignature';
import { ArticleExtractor } from '../../../main/ets/core/parser/ArticleExtractor';
import { ArticleCodec } from '../../../main/ets/core/service/ArticleCodec';
import { ReaderSegment, readerSegments } from '../../../main/ets/common/ReaderSegments';
import { resolveHttpUrl } from '../../../main/ets/common/UrlUtil';
import { decodeWebHtml } from '../../../main/ets/common/WebHtmlCodec';
import { readerBlockProgress, readerProgressRatio } from '../../../main/ets/common/ReaderProgress';
import {
  classifyMetadataWrite,
  MetadataApplyResult
} from '../../../main/ets/model/MetadataResult';

function repeatedText(chunk: string, times: number): string {
  let text = '';
  for (let i = 0; i < times; i++) {
    text = text + chunk;
  }
  return text;
}

function blockTextOf(document: ArticleDocument): string {
  let text = '';
  for (let i = 0; i < document.blocks.length; i++) {
    text = text + document.blocks[i].text;
  }
  return text;
}

function countExactBlocks(document: ArticleDocument, text: string): number {
  let count = 0;
  for (let i = 0; i < document.blocks.length; i++) {
    if (document.blocks[i].text === text) {
      count = count + 1;
    }
  }
  return count;
}

function joinedReaderSegments(segments: ReaderSegment[]): string {
  let text = '';
  for (let i = 0; i < segments.length; i++) {
    text = text + segments[i].text;
  }
  return text;
}

export default function readerTest() {
  describe('ReaderTest', () => {
    it('doesNotLetLongMetaBlockHijackStoryBody', 0, () => {
      const meta = repeatedText('元数据', 150);
      const story = repeatedText('真正的正文内容。', 200);
      const html = '<html><body><div class="post-meta">' + meta +
        '</div><div class="story-body"><p>' + story + '</p></div></body></html>';
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      expect(text.indexOf('真正的正文内容')).assertLargerOrEqual(0);
      expect(text.indexOf('元数据')).assertEqual(-1);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].text.indexOf('真正的正文内容')).assertEqual(0);
    });

    it('keepsArticleHeaderLeadWithoutDuplicatingTitle', 0, () => {
      const html = '<article><header><h1>标题</h1><p>导语段落也应该保留。</p></header>' +
        '<p>正文。</p><footer>页脚</footer></article>';
      const document = ArticleExtractor.extract(html, '标题');
      expect(document.blocks.length).assertEqual(2);
      expect(document.blocks[0].text).assertEqual('导语段落也应该保留。');
      expect(document.blocks[1].text).assertEqual('正文。');
      expect(countExactBlocks(document, '标题')).assertEqual(0);
      expect(blockTextOf(document).indexOf('页脚')).assertEqual(-1);
    });

    it('treatsUnknownAngleBracketsAsText', 0, () => {
      const document = ArticleExtractor.extract('<p>比较 <T> 与 x<y 的大小，且 5 &lt; 10</p>');
      const text = document.blocks[0].text;
      expect(text.indexOf('<T>')).assertLargerOrEqual(0);
      expect(text.indexOf('x<y')).assertLargerOrEqual(0);
      expect(text.indexOf('5 < 10')).assertLargerOrEqual(0);
    });

    it('keepsArticleTextAfterNestedJunkBlocks', 0, () => {
      const first = '<article><p>前段正文</p><div class="related">' +
        '<div class="share-tools">x</div></div><p>后段正文</p></article>';
      const firstDocument = ArticleExtractor.extract(first);
      expect(blockTextOf(firstDocument).indexOf('前段正文')).assertLargerOrEqual(0);
      expect(blockTextOf(firstDocument).indexOf('后段正文')).assertLargerOrEqual(0);
      expect(blockTextOf(firstDocument).indexOf('share-tools')).assertEqual(-1);
    });

    it('doesNotLetTinyArticleOrContentCandidateHijackPage', 0, () => {
      const longBody = repeatedText('真正的长正文第一段。', 40);
      const teaser = '<article class="teaser">相关推荐</article><main><p>' +
        longBody + '</p><p>第二段。</p></main>';
      const teaserDocument = ArticleExtractor.extract(teaser);
      expect(blockTextOf(teaserDocument).indexOf('相关推荐')).assertEqual(-1);
      expect(blockTextOf(teaserDocument).indexOf('真正的长正文第一段')).assertLargerOrEqual(0);

      const smallCandidate = '<div class="post-title">文章标题</div>' +
        '<div class="story-body"><p>真正的正文第一段。</p><p>第二段。</p></div>';
      const candidateDocument = ArticleExtractor.extract(smallCandidate, '文章标题');
      expect(candidateDocument.blocks.length).assertLarger(0);
      expect(candidateDocument.blocks[0].text.indexOf('真正的正文第一段')).assertLargerOrEqual(0);
      expect(blockTextOf(candidateDocument).indexOf('文章标题')).assertEqual(-1);
    });

    it('keepsRealStoryWhenTeaserArticleCoversMinorityOfBody', 0, () => {
      const teaser = repeatedText('推荐卡片内容。', 65);
      const story = repeatedText('真正的正文内容。', 200);
      const html = '<article class="teaser">' + teaser + '</article>' +
        '<div class="prose"><p>' + story + '</p></div>';
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      // Keeping a stray teaser is acceptable; losing the real story is not.
      expect(text.indexOf('真正的正文内容')).assertLargerOrEqual(0);
      expect(document.charCount()).assertLargerOrEqual(story.length);
    });

    it('keepsCardBodyWhenCommentsAreJunk', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const comments = repeatedText('评论噪声。', 200);
      const html = `<article class="card">${card}</article><div class="comments">${comments}</div>`;
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      expect(text.indexOf('唯一正文内容')).assertLargerOrEqual(0);
      expect(text.indexOf('评论噪声')).assertEqual(-1);
      expect(document.charCount()).assertLargerOrEqual(card.length);
    });

    it('keepsTeaserLikeArticlesWithoutACompetingBody', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const comments = repeatedText('评论噪声。', 200);
      const names: string[] = ['card', 'teaser', 'summary', 'post-card'];
      for (let i = 0; i < names.length; i++) {
        const html = `<article class="${names[i]}">${card}</article>` +
          `<div class="comments">${comments}</div>`;
        const document = ArticleExtractor.extract(html);
        const text = blockTextOf(document);
        expect(text.indexOf('唯一正文内容')).assertLargerOrEqual(0);
        expect(text.indexOf('评论噪声')).assertEqual(-1);
      }
    });

    it('keepsSoleTeaserBodyWhenUnnamedDivIsComments', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const comments = repeatedText('评论噪声。', 200);
      const html = `<article class="teaser">${card}</article><div>${comments}</div>`;
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      expect(text.indexOf('唯一正文内容')).assertLargerOrEqual(0);
      expect(text === comments).assertFalse();
      expect(document.charCount()).assertLargerOrEqual(card.length);
    });

    it('keepsOnlyCardWhenCommentParagraphIsUnnamed', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const comments = repeatedText('评论噪声。', 200);
      const html = `<article class="card">${card}</article><p>${comments}</p>`;
      const document = ArticleExtractor.extract(html);
      expect(blockTextOf(document).indexOf('唯一正文内容')).assertLargerOrEqual(0);
      expect(document.charCount()).assertLargerOrEqual(card.length);
    });

    it('keepsOnlyCardWithoutNoise', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const document = ArticleExtractor.extract(`<article class="card">${card}</article>`);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].text).assertEqual(card);
    });

    it('keepsMainWhenCommentsArticleIsJunk', 0, () => {
      const comments = repeatedText('评论噪声。', 200);
      const story = repeatedText('真正正文内容。', 50);
      const html = `<article class="comments">${comments}</article><main><p>${story}</p></main>`;
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      expect(text.indexOf('真正正文内容')).assertLargerOrEqual(0);
      expect(text.indexOf('评论噪声')).assertEqual(-1);
      expect(document.charCount()).assertLargerOrEqual(story.length);
    });

    it('keepsTeaserBodyInsideMainWithUnnamedComments', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const comments = repeatedText('评论噪声。', 200);
      const html = `<main><article class="teaser">${card}</article><div>${comments}</div></main>`;
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      expect(text.indexOf('唯一正文内容')).assertLargerOrEqual(0);
      expect(text === comments).assertFalse();
      expect(document.charCount()).assertLargerOrEqual(card.length);
    });

    it('keepsStoryWhenNavigationNamedContainerCoversPage', 0, () => {
      const navigation = repeatedText('导航噪声。', 280);
      const otherNavigation = repeatedText('导航噪声。', 200);
      const story = repeatedText('真正正文。', 70);
      const names: string[] = ['post-navigation', 'content-navigation', 'article-list'];
      for (let i = 0; i < names.length; i++) {
        const noise = names[i] === 'article-list' ? otherNavigation : navigation;
        const html = `<div class="${names[i]}">${noise}</div>` +
          `<div class="story">${story}</div>`;
        const document = ArticleExtractor.extract(html);
        const text = blockTextOf(document);
        expect(text.indexOf('真正正文')).assertLargerOrEqual(0);
        expect(text.indexOf('导航噪声')).assertEqual(-1);
      }
    });

    it('doesNotTreatContentWordsAsJunk', 0, () => {
      const html = '<div class="downloads">下载内容</div>' +
        '<div class="uploads">上传内容</div>' +
        '<div class="threads">帖子内容</div>' +
        '<div class="unavailable">暂不可用内容</div>' +
        '<div class="commentary">评论文章内容</div>';
      const document = ArticleExtractor.extract(html);
      const text = blockTextOf(document);
      expect(text.indexOf('下载内容')).assertLargerOrEqual(0);
      expect(text.indexOf('上传内容')).assertLargerOrEqual(0);
      expect(text.indexOf('帖子内容')).assertLargerOrEqual(0);
      expect(text.indexOf('暂不可用内容')).assertLargerOrEqual(0);
      expect(text.indexOf('评论文章内容')).assertLargerOrEqual(0);
    });

    it('dropsShortCjkTitleWithSiteSuffix', 0, () => {
      const html = '<article><h1>标题</h1><p>正文。</p></article>';
      const document = ArticleExtractor.extract(html, '标题 - 站点');
      expect(countExactBlocks(document, '标题')).assertEqual(0);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].text).assertEqual('正文。');
    });

    it('dropsTitleAfterLeadingMetaLine', 0, () => {
      const html = '<article><p>2026-10-22</p><h1>标题</h1><p>正文。</p></article>';
      const document = ArticleExtractor.extract(html, '标题 | 站点');
      expect(countExactBlocks(document, '标题')).assertEqual(0);
      expect(blockTextOf(document).indexOf('2026-10-22')).assertLargerOrEqual(0);
      expect(blockTextOf(document).indexOf('正文。')).assertLargerOrEqual(0);
    });

    it('extractsCardBodyBeforeOverwritingOldSnapshot', 0, () => {
      const card = repeatedText('唯一正文内容。', 30);
      const comments = repeatedText('评论噪声。', 200);
      const html = `<article class="card">${card}</article><div class="comments">${comments}</div>`;
      const document = ArticleExtractor.extract(html);
      const outcome = classifyMetadataWrite(true, true, true, document.blocks.length > 0);
      expect(outcome).assertEqual(MetadataApplyResult.WROTE_SNAPSHOT);
      expect(blockTextOf(document).indexOf('唯一正文内容')).assertLargerOrEqual(0);
      expect(blockTextOf(document).indexOf('评论噪声')).assertEqual(-1);
    });

    it('keepsMainHeaderLeadOnPagesWithoutArticle', 0, () => {
      const html = '<main><header><h1>标题</h1><p>导语段落也应该保留。</p></header>' +
        '<p>正文。</p></main>';
      const document = ArticleExtractor.extract(html, '标题');
      const text = blockTextOf(document);
      expect(text.indexOf('导语段落也应该保留。')).assertLargerOrEqual(0);
      expect(text.indexOf('正文。')).assertLargerOrEqual(0);
      expect(countExactBlocks(document, '标题')).assertEqual(0);
    });

    it('preservesBreaksEntitiesAndPreBlocks', 0, () => {
      const breaks = ArticleExtractor.extract('<p>第一行<br>第二行</p>');
      expect(breaks.blocks[0].text).assertEqual('第一行\n第二行');
      const entities = ArticleExtractor.extract('<p>A&mdash;B&hellip;&rsquo;&amp;</p>');
      expect(entities.blocks[0].text).assertEqual('A\u2014B\u2026\u2019&');
      const code = ArticleExtractor.extract('<pre>line1\n<div>line2</div>\nline3</pre>');
      expect(code.blocks.length).assertEqual(1);
      expect(code.blocks[0].type).assertEqual(ArticleBlockType.CODE);
      expect(code.blocks[0].text).assertEqual('line1\nline2\nline3');
    });

    it('detectsArticleSignatureChanges', 0, () => {
      const first = new ArticleDocument();
      first.blocks = [
        ArticleBlock.of(ArticleBlockType.HEADING, 1, '标题'),
        ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, '正文')
      ];
      const same = new ArticleDocument();
      same.blocks = [
        ArticleBlock.of(ArticleBlockType.HEADING, 1, '标题'),
        ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, '正文')
      ];
      const changed = new ArticleDocument();
      changed.blocks = [
        ArticleBlock.of(ArticleBlockType.HEADING, 1, '标题'),
        ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, '正文改过')
      ];
      expect(ArticleSignature.of(first)).assertEqual(ArticleSignature.of(same));
      expect(ArticleSignature.differs(first, same)).assertFalse();
      expect(ArticleSignature.differs(first, changed)).assertTrue();
    });

    it('classifiesMetadataApplyResults', 0, () => {
      expect(classifyMetadataWrite(false, true, true, true)).assertEqual(MetadataApplyResult.FAILED);
      expect(classifyMetadataWrite(true, true, false, true)).assertEqual(MetadataApplyResult.WROTE_SNAPSHOT);
      expect(classifyMetadataWrite(true, true, true, false)).assertEqual(MetadataApplyResult.KEPT_OLD);
      expect(classifyMetadataWrite(true, true, false, false)).assertEqual(MetadataApplyResult.EMPTY);
      expect(classifyMetadataWrite(true, false, true, false)).assertEqual(MetadataApplyResult.KEPT_OLD);
      expect(classifyMetadataWrite(true, false, false, false)).assertEqual(MetadataApplyResult.EMPTY);
    });

    it('computesReaderProgress', 0, () => {
      expect(readerProgressRatio(0, 2000, 800)).assertEqual(0);
      expect(readerProgressRatio(600, 2000, 800)).assertEqual(0.5);
      expect(readerProgressRatio(0, 500, 800)).assertEqual(1);
      expect(readerBlockProgress(0, 10)).assertEqual(0);
      expect(readerBlockProgress(5, 11)).assertEqual(0.5);
      expect(readerBlockProgress(10, 11)).assertEqual(0.99);
      expect(readerBlockProgress(3, 1)).assertEqual(0);
    });

    it('capturesAbsoluteLinksAndOffsets', 0, () => {
      const html = '<article><p>看<a href="https://example.com/a">这里</a>。</p></article>';
      const document = ArticleExtractor.extract(html);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].text).assertEqual('看这里。');
      expect(document.blocks[0].links.length).assertEqual(1);
      expect(document.blocks[0].links[0].start).assertEqual(1);
      expect(document.blocks[0].links[0].end).assertEqual(3);
      expect(document.blocks[0].links[0].url).assertEqual('https://example.com/a');
    });

    it('resolvesRelativeLinksAgainstBaseUrl', 0, () => {
      const html = '<article><p>去<a href="/docs?x=1&amp;y=2">文档</a></p></article>';
      const document = ArticleExtractor.extract(html, '', 'https://example.com/dir/page');
      expect(document.blocks[0].links.length).assertEqual(1);
      expect(document.blocks[0].links[0].url).assertEqual('https://example.com/docs?x=1&y=2');
    });

    it('dropsUnsafeAndFragmentLinks', 0, () => {
      const html = '<p><a href="javascript:alert(1)">a</a>' +
        '<a href="mailto:x@y.com">b</a><a href="#top">c</a><a href="/rel">d</a></p>';
      const document = ArticleExtractor.extract(html);
      expect(document.blocks[0].text).assertEqual('abcd');
      expect(document.blocks[0].links.length).assertEqual(0);
    });

    it('keepsCodeBlocksLinkFree', 0, () => {
      const document = ArticleExtractor.extract('<pre><a href="https://example.com">code</a></pre>');
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].type).assertEqual(ArticleBlockType.CODE);
      expect(document.blocks[0].text).assertEqual('code');
      expect(document.blocks[0].links.length).assertEqual(0);
    });

    it('spansLinksAcrossBreaksAndEntities', 0, () => {
      const html = '<p><a href="https://example.com/x">第一行<br>第二行 &amp; 结束</a></p>';
      const document = ArticleExtractor.extract(html);
      const text = document.blocks[0].text;
      expect(text).assertEqual('第一行\n第二行 & 结束');
      expect(document.blocks[0].links.length).assertEqual(1);
      expect(document.blocks[0].links[0].start).assertEqual(0);
      expect(document.blocks[0].links[0].end).assertEqual(text.length);
    });

    it('doesNotLeakLinkMarkersIntoText', 0, () => {
      const document = ArticleExtractor.extract('<p>前<a href="https://example.com">中</a>后</p>');
      const text = document.blocks[0].text;
      expect(text).assertEqual('前中后');
      expect(text.indexOf('\uE010')).assertEqual(-1);
      expect(text.indexOf('\uE011')).assertEqual(-1);
      expect(text.indexOf('\uE012')).assertEqual(-1);
    });

    it('keepsLinksInHeadingsAndLists', 0, () => {
      const html = '<article><h2><a href="https://example.com">标题</a></h2>' +
        '<ul><li><a href="https://example.com/2">项</a></li></ul></article>';
      const document = ArticleExtractor.extract(html);
      expect(document.blocks[0].type).assertEqual(ArticleBlockType.HEADING);
      expect(document.blocks[0].links.length).assertEqual(1);
      expect(document.blocks[1].type).assertEqual(ArticleBlockType.LIST_ITEM);
      expect(document.blocks[1].links.length).assertEqual(1);
    });

    it('roundTripsLinksThroughSnapshotCodec', 0, () => {
      const document = new ArticleDocument();
      const block = ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, '看这里。');
      block.links = [ArticleLink.of(1, 3, 'https://example.com/a?x=1&y=2')];
      document.blocks = [block];
      const encoded = ArticleCodec.encode(document);
      expect(encoded.indexOf('FLOWPAGE-ARTICLE-2')).assertEqual(0);
      const decoded = ArticleCodec.decode(encoded);
      expect(decoded.blocks.length).assertEqual(1);
      expect(decoded.blocks[0].text).assertEqual('看这里。');
      expect(decoded.blocks[0].links.length).assertEqual(1);
      expect(decoded.blocks[0].links[0].start).assertEqual(1);
      expect(decoded.blocks[0].links[0].end).assertEqual(3);
      expect(decoded.blocks[0].links[0].url).assertEqual('https://example.com/a?x=1&y=2');
    });

    it('decodesV1SnapshotWithoutLinks', 0, () => {
      const decoded = ArticleCodec.decode('FLOWPAGE-ARTICLE-1\np\t旧正文');
      expect(decoded.blocks.length).assertEqual(1);
      expect(decoded.blocks[0].text).assertEqual('旧正文');
      expect(decoded.blocks[0].links.length).assertEqual(0);
    });

    it('clampsLinksWhenTruncating', 0, () => {
      const document = new ArticleDocument();
      const block = ArticleBlock.of(ArticleBlockType.PARAGRAPH, 0, 'abcdefghij');
      block.links = [
        ArticleLink.of(2, 6, 'https://a.example'),
        ArticleLink.of(8, 10, 'https://b.example')
      ];
      document.blocks = [block];
      document.truncate(7);
      expect(document.blocks.length).assertEqual(1);
      expect(document.blocks[0].text).assertEqual('abcdefg');
      expect(document.blocks[0].links.length).assertEqual(1);
      expect(document.blocks[0].links[0].end).assertEqual(6);
    });

    it('splitsLinksAndSearchMatches', 0, () => {
      const segments = readerSegments(
        '看这里和那里',
        [ArticleLink.of(1, 3, 'https://example.com/a')],
        '里和'
      );
      expect(joinedReaderSegments(segments)).assertEqual('看这里和那里');
      let matchedLink = false;
      for (let i = 0; i < segments.length; i++) {
        if (segments[i].url.length > 0 && segments[i].matched) {
          matchedLink = true;
        }
      }
      expect(matchedLink).assertTrue();
    });

    it('decodesEscapedHtmlFromWebView', 0, () => {
      const escaped = '\\u003Carticle\\u003E\\u003Ch1\\u003E标题\\u003C/h1\\u003E' +
        '\\u003Cp\\u003E正文\\u003Ca href=\\"https://example.com/a\\"\\u003E链接\\u003C/a\\u003E\\u003C/p\\u003E' +
        '\\u003C/article\\u003E';
      const html = decodeWebHtml(escaped);
      expect(html.indexOf('\\u003C')).assertEqual(-1);
      expect(html.indexOf('<article>')).assertEqual(0);
      const document = ArticleExtractor.extract(html, '标题', 'https://example.com/start');
      expect(document.blocks.length > 0).assertTrue();
      let joined = '';
      for (let i = 0; i < document.blocks.length; i++) {
        joined = `${joined}${document.blocks[i].text}`;
      }
      expect(joined.indexOf('<')).assertEqual(-1);
      expect(joined.indexOf('正文') >= 0).assertTrue();
      expect(joined.indexOf('链接') >= 0).assertTrue();
      expect(decodeWebHtml('<p>无转义 \\ 文本</p>')).assertEqual('<p>无转义 \\ 文本</p>');
      expect(decodeWebHtml('\\u003Cp\\u003Ea\\nb\\u003C/p\\u003E')).assertEqual('<p>a\\nb</p>');
      expect(decodeWebHtml('\\u003Cp\\u003E\\u12zz\\u003C/p\\u003E')).assertEqual('<p>\\u12zz</p>');
      expect(decodeWebHtml('<p>say \\"hi\\"</p>')).assertEqual('<p>say \\"hi\\"</p>');
    });

    it('resolvesHttpUrlsSafely', 0, () => {
      expect(resolveHttpUrl('https://example.com/a/b', '../c')).assertEqual('https://example.com/c');
      expect(resolveHttpUrl('https://example.com', 'javascript:void(0)')).assertEqual('');
      expect(resolveHttpUrl('https://example.com', '#top')).assertEqual('');
      expect(resolveHttpUrl('', '/relative')).assertEqual('');
    });
  });
}
