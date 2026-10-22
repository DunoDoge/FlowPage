import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource, ReadState } from '../../../main/ets/common/Constants';
import { HighlightSegment, highlightSegments } from '../../../main/ets/common/Highlight';
import { splitIntoChunks } from '../../../main/ets/common/TextUtil';
import { deepLinkTextOf, shareContentOf } from '../../../main/ets/common/ShareUtil';
import { CARD_FIELD_SEPARATOR, cardLineOf, cardTitleOf, parseCardLine, parseCardLines } from '../../../main/ets/common/CardFormat';
import {
  CARD_KEY_CANDIDATES,
  CARD_KEY_TODAY_TITLE,
  CARD_PREFERENCES_NAME,
  CardSnapshot
} from '../../../main/ets/core/service/CardSnapshot';
import { normalizeUrl } from '../../../main/ets/common/UrlUtil';

function joinedSegments(segments: HighlightSegment[]): string {
  let joined = '';
  for (let i = 0; i < segments.length; i++) {
    joined = joined + segments[i].text;
  }
  return joined;
}

function matchedCount(segments: HighlightSegment[]): number {
  let count = 0;
  for (let i = 0; i < segments.length; i++) {
    if (segments[i].matched) {
      count = count + 1;
    }
  }
  return count;
}

export default function repositoryTest() {
  describe('RepositoryTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_repo_test.db');
      if (context !== undefined) {
        await FlowRepository.get().init(context);
      }
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('rejectsNonHttpSchemes', 0, () => {
      expect(normalizeUrl('mailto:someone@example.com')).assertEqual('');
      expect(normalizeUrl('javascript:alert(1)')).assertEqual('');
      expect(normalizeUrl('data:text/html,hi')).assertEqual('');
      expect(normalizeUrl('tel:10086')).assertEqual('');
      expect(normalizeUrl('localhost:8080/a')).assertEqual('https://localhost:8080/a');
    });

    it('highlightsKeywordSegments', 0, () => {
      const segments = highlightSegments('Hello hello', 'hello');
      expect(segments.length).assertEqual(3);
      let matched = 0;
      for (let i = 0; i < segments.length; i++) {
        if (segments[i].matched) {
          matched = matched + 1;
        }
      }
      expect(matched).assertEqual(2);
      const plain = highlightSegments('没有命中', 'abc');
      expect(plain.length).assertEqual(1);
      expect(plain[0].matched).assertFalse();
    });

    it('highlightsWholeStringAndEmptyKeyword', 0, () => {
      const whole = highlightSegments('流笺', '流笺');
      expect(whole.length).assertEqual(1);
      expect(whole[0].matched).assertTrue();
      expect(whole[0].text).assertEqual('流笺');

      const blank = highlightSegments('完整标题', '   ');
      expect(blank.length).assertEqual(1);
      expect(blank[0].matched).assertFalse();
      expect(blank[0].text).assertEqual('完整标题');

      const emptyText = highlightSegments('', 'x');
      expect(emptyText.length).assertEqual(0);
    });

    it('highlightsMultipleAndCaseInsensitiveSegments', 0, () => {
      const segments = highlightSegments('Alpha beta ALPHA', 'alpha');
      expect(segments.length).assertEqual(3);
      expect(segments[0].text).assertEqual('Alpha');
      expect(segments[0].matched).assertTrue();
      expect(segments[1].text).assertEqual(' beta ');
      expect(segments[1].matched).assertFalse();
      expect(segments[2].text).assertEqual('ALPHA');
      expect(segments[2].matched).assertTrue();
      expect(joinedSegments(segments)).assertEqual('Alpha beta ALPHA');
    });

    it('highlightsChineseAndRegexLiteralKeywords', 0, () => {
      const chinese = highlightSegments('把链接收进来，链接不会丢', '链接');
      expect(matchedCount(chinese)).assertEqual(2);
      expect(joinedSegments(chinese)).assertEqual('把链接收进来，链接不会丢');

      const literal = highlightSegments('a+b (c) [d]?', '+');
      expect(matchedCount(literal)).assertEqual(1);
      expect(literal[1].text).assertEqual('+');
      expect(joinedSegments(literal)).assertEqual('a+b (c) [d]?');

      const dot = highlightSegments('a.b', '.');
      expect(matchedCount(dot)).assertEqual(1);
    });

    it('highlightsPreserveOriginalTextAcrossKeywords', 0, () => {
      const texts: string[] = ['FlowPage Highlight Demo', '中文标题：链接收藏', 'a+b (c) [d]', 'MiXeD CaSe'];
      const keywords: string[] = ['', 'highlight', '链接', '+', 'mixed', 'zzz'];
      for (let i = 0; i < texts.length; i++) {
        for (let j = 0; j < keywords.length; j++) {
          expect(joinedSegments(highlightSegments(texts[i], keywords[j]))).assertEqual(texts[i]);
        }
      }
    });

    it('splitsLongTextIntoChunks', 0, () => {
      const chunks = splitIntoChunks('abcdef', 4);
      expect(chunks.length).assertEqual(2);
      expect(chunks[0]).assertEqual('abcd');
      expect(chunks[1]).assertEqual('ef');
      const paragraphs = splitIntoChunks('a\nb\nc', 2);
      expect(paragraphs.length).assertEqual(3);
    });

    it('sharesOriginalUrlAndDeepLinkSeparately', 0, () => {
      const bookmark = Bookmark.create('https://example.com/share', '分享', BookmarkSource.MANUAL);
      expect(shareContentOf(bookmark)).assertEqual('https://example.com/share');
      const deepLink = deepLinkTextOf(bookmark);
      expect(deepLink.indexOf('flowpage://bookmark/')).assertLargerOrEqual(0);
      expect(deepLink.indexOf(bookmark.id)).assertLargerOrEqual(0);
    });

    it('encodesCardLinesWithSeparatorSafeTitle', 0, () => {
      const title = '标题|带竖线\n第二行\r第三行';
      expect(cardTitleOf(title).indexOf('|') >= 0).assertTrue();
      expect(cardTitleOf(title).indexOf('\n')).assertEqual(-1);
      expect(cardTitleOf(title).indexOf('\r')).assertEqual(-1);
      expect(cardTitleOf('控\u0001制')).assertEqual('控 制');
      const line = cardLineOf(title, 'example.com', 'card-id-1');
      expect(line.indexOf(CARD_FIELD_SEPARATOR)).assertLarger(0);
      expect(line.indexOf('\u0001')).assertEqual(-1);
      expect(line.indexOf('\n')).assertEqual(-1);
      expect(line.indexOf('%0A')).assertEqual(-1);
      const parsed = parseCardLine(line);
      expect(parsed === undefined).assertFalse();
      if (parsed !== undefined) {
        expect(parsed.id).assertEqual('card-id-1');
        expect(parsed.domain).assertEqual('example.com');
        expect(parsed.title.indexOf('标题')).assertEqual(0);
        expect(parsed.title.indexOf('第二行') >= 0).assertTrue();
      }
      expect(parseCardLine('legacy|format|line') === undefined).assertTrue();
      const roundTrip = parseCardLines(cardLineOf('甲%01乙', 'a.com', '1'));
      expect(roundTrip.length).assertEqual(1);
      expect(roundTrip[0].title).assertEqual('甲%01乙');
    });

    it('cardSnapshotRoundTripsThroughPreferences', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const store = preferences.getPreferencesSync(context, { name: CARD_PREFERENCES_NAME });
      const line = cardLineOf('标题\u0001\n第二行', 'example.com', 'card-id-pref');
      store.putSync(CARD_KEY_TODAY_TITLE, cardTitleOf('标题\u0001\n第二行'));
      store.putSync(CARD_KEY_CANDIDATES, line);
      await store.flush();
      const values = CardSnapshot.readValues(context);
      expect(values.todayTitle.indexOf('\u0001')).assertEqual(-1);
      const items = parseCardLines(values.candidates);
      expect(items.length).assertEqual(1);
      expect(items[0].id).assertEqual('card-id-pref');
      expect(items[0].domain).assertEqual('example.com');
      expect(items[0].title.indexOf('第二行') >= 0).assertTrue();
    });

    it('saveEditsWritesOnceWithSingleRevBump', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/edit-once', '旧标题', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const before = await dao.findById(bookmark.id);
      expect(before === undefined).assertFalse();
      if (before === undefined) {
        return;
      }
      await FlowRepository.get().saveEdits(bookmark.id, '新标题', '新备注', '新摘录', ['标签一']);
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.title).assertEqual('新标题');
        expect(after.note).assertEqual('新备注');
        expect(after.excerpt).assertEqual('新摘录');
        expect(after.tags.length).assertEqual(1);
        expect(after.tags[0]).assertEqual('标签一');
        expect(after.rev).assertEqual(before.rev + 1);
        expect(after.updatedAt).assertLargerOrEqual(before.updatedAt);
        expect(after.searchText.indexOf('新标题') >= 0).assertTrue();
      }
    });

    it('summarizesActiveAndArchivedSeparately', 0, async () => {
      const dao = new BookmarkDao();
      const unread = Bookmark.create('https://example.com/sum-unread', '未读', BookmarkSource.MANUAL);
      await dao.insert(unread);
      const starred = Bookmark.create('https://example.com/sum-starred', '星标', BookmarkSource.MANUAL);
      starred.readState = ReadState.READ;
      starred.starred = true;
      await dao.insert(starred);
      const archived = Bookmark.create('https://example.com/sum-archived', '归档', BookmarkSource.MANUAL);
      archived.archived = true;
      await dao.insert(archived);
      const trashed = Bookmark.create('https://example.com/sum-trash', '回收', BookmarkSource.MANUAL);
      trashed.deleted = true;
      await dao.insert(trashed);
      const summary = await FlowRepository.get().summary();
      expect(summary.total).assertEqual(2);
      expect(summary.unread).assertEqual(1);
      expect(summary.starred).assertEqual(1);
      expect(summary.archived).assertEqual(1);
      expect(summary.trash).assertEqual(1);
    });

    it('rollsBackDuplicateBatch', 0, async () => {
      const dao = new BookmarkDao();
      const first = Bookmark.create('https://example.com/batch-dup', '批次一', BookmarkSource.MANUAL);
      const second = Bookmark.create('https://example.com/batch-dup', '批次二', BookmarkSource.MANUAL);
      const batch: Bookmark[] = [];
      batch.push(first);
      batch.push(second);
      let failed = false;
      try {
        await dao.insertBatch(batch);
      } catch (error) {
        failed = true;
      }
      expect(failed).assertTrue();
      expect((await dao.listAll(true)).length).assertEqual(0);
    });

    it('movesThroughReadingStates', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/reading', '阅读', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await FlowRepository.get().setRead(bookmark.id, ReadState.READING);
      let loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.readState).assertEqual(ReadState.READING);
        expect(loaded.readAt).assertEqual(0);
      }
      await FlowRepository.get().setRead(bookmark.id, ReadState.READ);
      loaded = await dao.findById(bookmark.id);
      if (loaded !== undefined) {
        expect(loaded.readState).assertEqual(ReadState.READ);
        expect(loaded.readAt > 0).assertTrue();
      }
      await FlowRepository.get().setRead(bookmark.id, ReadState.UNREAD);
      loaded = await dao.findById(bookmark.id);
      if (loaded !== undefined) {
        expect(loaded.readState).assertEqual(ReadState.UNREAD);
        expect(loaded.readAt).assertEqual(0);
      }
    });

    it('appliesBatchMutationsInOnePass', 0, async () => {
      const dao = new BookmarkDao();
      const first = Bookmark.create('https://example.com/batch-a', '批次甲', BookmarkSource.MANUAL);
      const second = Bookmark.create('https://example.com/batch-b', '批次乙', BookmarkSource.MANUAL);
      const third = Bookmark.create('https://example.com/batch-c', '批次丙', BookmarkSource.MANUAL);
      const batch: Bookmark[] = [first, second, third];
      await dao.insertBatch(batch);
      const before = await dao.findById(first.id);
      expect(before === undefined).assertFalse();
      const ids: string[] = [first.id, second.id];

      await FlowRepository.get().setStarredMany(ids, true);
      await FlowRepository.get().setArchivedMany(ids, true);
      await FlowRepository.get().setReadMany(ids, ReadState.READ);
      let loaded = await dao.findById(first.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined && before !== undefined) {
        expect(loaded.starred).assertTrue();
        expect(loaded.archived).assertTrue();
        expect(loaded.readState).assertEqual(ReadState.READ);
        expect(loaded.readAt > 0).assertTrue();
        expect(loaded.rev).assertEqual(before.rev + 3);
      }
      const untouched = await dao.findById(third.id);
      expect(untouched === undefined).assertFalse();
      if (untouched !== undefined) {
        expect(untouched.starred).assertFalse();
        expect(untouched.archived).assertFalse();
      }

      await FlowRepository.get().setReadMany([first.id], ReadState.UNREAD);
      loaded = await dao.findById(first.id);
      if (loaded !== undefined) {
        expect(loaded.readState).assertEqual(ReadState.UNREAD);
        expect(loaded.readAt).assertEqual(0);
      }

      await FlowRepository.get().deleteMany(ids);
      let all = await dao.listAll(true);
      expect(all.length).assertEqual(3);
      for (let i = 0; i < all.length; i++) {
        if (all[i].id === first.id || all[i].id === second.id) {
          expect(all[i].deleted).assertTrue();
        } else {
          expect(all[i].deleted).assertFalse();
        }
      }

      await FlowRepository.get().restoreMany(ids);
      all = await dao.listAll(true);
      for (let i = 0; i < all.length; i++) {
        expect(all[i].deleted).assertFalse();
      }

      await FlowRepository.get().purgeMany(ids);
      const remaining = await dao.listAll(true);
      expect(remaining.length).assertEqual(1);
      expect(remaining[0].id).assertEqual(third.id);
      expect((await dao.listTombstones()).length).assertEqual(2);
    });

    it('appendExcerptPreservesExistingWhitespaceAndTouchesSearch', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create(
        'https://example.com/excerpt-keep',
        '摘录追加',
        BookmarkSource.MANUAL
      );
      bookmark.excerpt = '  原有摘录  ';
      bookmark.rebuildSearch();
      await dao.insert(bookmark);
      const before = await dao.findById(bookmark.id);
      expect(before === undefined).assertFalse();

      const next = await FlowRepository.get().appendExcerpt(bookmark.id, '新增摘录');
      expect(next).assertEqual('  原有摘录  \n\n新增摘录');

      const loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined && before !== undefined) {
        expect(loaded.excerpt).assertEqual('  原有摘录  \n\n新增摘录');
        expect(loaded.searchText.indexOf('原有摘录')).assertLargerOrEqual(0);
        expect(loaded.searchText.indexOf('新增摘录')).assertLargerOrEqual(0);
        expect(loaded.dirty).assertTrue();
        expect(loaded.rev).assertEqual(before.rev + 1);
      }
    });

    it('persistsAutoSnapshotSetting', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const store = preferences.getPreferencesSync(context, { name: 'flowpage_settings' });
      store.putSync('auto_snapshot', false);
      await store.flush();
      expect(FlowRepository.get().autoSnapshotEnabled()).assertFalse();
      store.putSync('auto_snapshot', true);
      await store.flush();
      expect(FlowRepository.get().autoSnapshotEnabled()).assertTrue();
    });
  });
}
