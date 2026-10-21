import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { relationalStore } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { BookmarkQuery, BookmarkSort } from '../../../main/ets/model/BookmarkQuery';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource, StreamFilter } from '../../../main/ets/common/Constants';

function seedBuckets(count: number, keyword: string): relationalStore.ValuesBucket[] {
  const buckets: relationalStore.ValuesBucket[] = [];
  const now = Date.now();
  for (let i = 0; i < count; i++) {
    const bucket: relationalStore.ValuesBucket = {
      'id': `bench-${i}`,
      'url': `https://bench${i}.example.com/page`,
      'url_key': `https://bench${i}.example.com/page`,
      'domain': `bench${i}.example.com`,
      'title': i === 0 ? `${keyword} 命中` : `基准条目 ${i}`,
      'search_text': i === 0 ? `${keyword} 命中` : `基准条目 ${i}`,
      'created_at': now + i,
      'updated_at': now + i
    };
    buckets.push(bucket);
  }
  return buckets;
}

async function insertBuckets(buckets: relationalStore.ValuesBucket[]): Promise<void> {
  const store = Database.getStore();
  const chunk = 500;
  for (let start = 0; start < buckets.length; start = start + chunk) {
    const end = start + chunk < buckets.length ? start + chunk : buckets.length;
    await store.batchInsert('bookmark', buckets.slice(start, end));
  }
}

export default function queryTest() {
  describe('QueryTest', () => {
    let context: common.Context | undefined = undefined;
    const dao = new BookmarkDao();

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_query_test.db');
      if (context !== undefined) {
        await FlowRepository.get().init(context);
      }
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('pagesThroughResults', 0, async () => {
      const batch: Bookmark[] = [];
      for (let i = 0; i < 120; i++) {
        const bookmark = Bookmark.create(`https://page${i}.example.com/a`, `分页 ${i}`, BookmarkSource.MANUAL);
        batch.push(bookmark);
      }
      await dao.insertBatch(batch);
      const query = new BookmarkQuery();
      query.filter = StreamFilter.ALL;
      const first = await FlowRepository.get().queryPage(query, 0, 50);
      expect(first.items.length).assertEqual(50);
      expect(first.hasMore).assertTrue();
      const second = await FlowRepository.get().queryPage(query, 50, 50);
      expect(second.items.length).assertEqual(50);
      expect(second.hasMore).assertTrue();
      const third = await FlowRepository.get().queryPage(query, 100, 50);
      expect(third.items.length).assertEqual(20);
      expect(third.hasMore).assertFalse();
    });

    it('filtersByKeywordAndTag', 0, async () => {
      const batch: Bookmark[] = [];
      for (let i = 0; i < 120; i++) {
        const bookmark = Bookmark.create(`https://filter${i}.example.com/a`, i === 3 ? 'needle 标题' : `条目 ${i}`, BookmarkSource.MANUAL);
        if (i % 2 === 0) {
          bookmark.tags = ['技术'];
        }
        bookmark.rebuildSearch();
        batch.push(bookmark);
      }
      await dao.insertBatch(batch);
      const keywordQuery = new BookmarkQuery();
      keywordQuery.keyword = 'needle';
      const found = await FlowRepository.get().queryPage(keywordQuery, 0, 50);
      expect(found.items.length).assertEqual(1);
      if (found.items.length === 1) {
        expect(found.items[0].title.indexOf('needle') >= 0).assertTrue();
      }
      const tagQuery = new BookmarkQuery();
      tagQuery.tag = '技术';
      const firstPage = await FlowRepository.get().queryPage(tagQuery, 0, 50);
      expect(firstPage.items.length).assertEqual(50);
      expect(firstPage.hasMore).assertTrue();
      const secondPage = await FlowRepository.get().queryPage(tagQuery, 50, 50);
      expect(secondPage.items.length).assertEqual(10);
      expect(secondPage.hasMore).assertFalse();
    });

    it('sortsByDomain', 0, async () => {
      const older = Bookmark.create('https://a.com/page', '域名甲', BookmarkSource.MANUAL);
      older.createdAt = Date.now() - 10000;
      const newer = Bookmark.create('https://b.com/page', '域名乙', BookmarkSource.MANUAL);
      newer.createdAt = Date.now();
      const batch: Bookmark[] = [];
      batch.push(older);
      batch.push(newer);
      await dao.insertBatch(batch);
      const query = new BookmarkQuery();
      query.sort = BookmarkSort.DOMAIN_ASC;
      const sorted = await FlowRepository.get().queryPage(query, 0, 10);
      expect(sorted.items.length).assertEqual(2);
      if (sorted.items.length === 2) {
        expect(sorted.items[0].url.indexOf('a.com') >= 0).assertTrue();
        expect(sorted.items[1].url.indexOf('b.com') >= 0).assertTrue();
      }
    });

    it('escapesLikeWildcards', 0, async () => {
      const batch: Bookmark[] = [];
      const underscore = Bookmark.create('https://like.example.com/a_b', 'a_b 字面', BookmarkSource.MANUAL);
      batch.push(underscore);
      const other = Bookmark.create('https://like.example.com/axb', 'axb 其他', BookmarkSource.MANUAL);
      batch.push(other);
      const percent = Bookmark.create('https://like.example.com/100', '100% 进度', BookmarkSource.MANUAL);
      batch.push(percent);
      const plain = Bookmark.create('https://like.example.com/1000', '1000 条', BookmarkSource.MANUAL);
      batch.push(plain);
      await dao.insertBatch(batch);

      const underscoreQuery = new BookmarkQuery();
      underscoreQuery.keyword = 'a_b';
      const underscoreRows = await FlowRepository.get().queryPage(underscoreQuery, 0, 10);
      expect(underscoreRows.items.length).assertEqual(1);
      if (underscoreRows.items.length === 1) {
        expect(underscoreRows.items[0].url.indexOf('a_b') >= 0).assertTrue();
      }

      const percentQuery = new BookmarkQuery();
      percentQuery.keyword = '100%';
      const percentRows = await FlowRepository.get().queryPage(percentQuery, 0, 10);
      expect(percentRows.items.length).assertEqual(1);
      if (percentRows.items.length === 1) {
        expect(percentRows.items[0].url.indexOf('/100') >= 0).assertTrue();
      }
    });

    it('recordsColdQueryBaseline', 0, async () => {
      await insertBuckets(seedBuckets(10000, 'cold10k'));
      const query = new BookmarkQuery();
      query.keyword = 'cold10k';
      const started = Date.now();
      const rows = await FlowRepository.get().queryPage(query, 0, 50);
      const elapsed = Date.now() - started;
      hilog.info(0x0000, 'flowpage', 'bench cold query 10000 rows elapsed=%{public}dms', elapsed);
      expect(rows.items.length).assertEqual(1);
    });

    it('searchesOneThousandWithinBudget', 0, async () => {
      await insertBuckets(seedBuckets(1000, 'needle1k'));
      const query = new BookmarkQuery();
      query.keyword = 'needle1k';
      await FlowRepository.get().queryPage(query, 0, 50);
      const started = Date.now();
      const rows = await FlowRepository.get().queryPage(query, 0, 50);
      const elapsed = Date.now() - started;
      hilog.info(0x0000, 'flowpage', 'bench query 1000 rows elapsed=%{public}dms', elapsed);
      expect(rows.items.length).assertEqual(1);
      expect(elapsed < 100).assertTrue();
    });

    it('searchesTenThousandWithinBudget', 0, async () => {
      await insertBuckets(seedBuckets(10000, 'needle10k'));
      const query = new BookmarkQuery();
      query.keyword = 'needle10k';
      await FlowRepository.get().queryPage(query, 0, 50);
      const started = Date.now();
      const rows = await FlowRepository.get().queryPage(query, 0, 50);
      const elapsed = Date.now() - started;
      hilog.info(0x0000, 'flowpage', 'bench query 10000 rows elapsed=%{public}dms', elapsed);
      expect(rows.items.length).assertEqual(1);
      expect(elapsed < 200).assertTrue();
    });
  });
}
