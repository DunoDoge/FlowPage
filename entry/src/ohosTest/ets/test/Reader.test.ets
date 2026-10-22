import { describe, it, expect } from '@ohos/hypium';
import { ArticleBlock, ArticleBlockType, ArticleDocument } from '../../../main/ets/model/Article';
import { ArticleSignature } from '../../../main/ets/common/ArticleSignature';
import { ArticleExtractor } from '../../../main/ets/core/parser/ArticleExtractor';
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
  });
}
