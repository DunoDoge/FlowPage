import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { SyncRecord } from '../../../main/ets/core/sync/SyncRecord';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource } from '../../../main/ets/common/Constants';
import { isSameUrl, normalizeUrl } from '../../../main/ets/common/UrlUtil';

export default function syncStoreTest() {
  describe('SyncStoreTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_test.db');
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('normalizesUrlsForDeduplication', 0, () => {
      expect(normalizeUrl('Example.com/a?b=2&a=1&utm_source=x')).assertEqual('https://example.com/a?a=1&b=2');
      expect(normalizeUrl('https://example.com/a?spm=1')).assertEqual('https://example.com/a');
      expect(normalizeUrl('ftp://example.com/a')).assertEqual('');
      expect(isSameUrl('example.com/a', 'https://example.com/a')).assertTrue();
      expect(isSameUrl('https://example.com/a', 'https://example.com/b')).assertFalse();
    });

    it('purgeCreatesTombstoneAndRemovesBookmark', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/tombstone', '墓碑', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await dao.purge(bookmark.id);
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
      const tombstone = await dao.findTombstone(bookmark.id);
      expect(tombstone === undefined).assertFalse();
      if (tombstone !== undefined) {
        expect(tombstone.remoteId).assertEqual(bookmark.id);
        expect(tombstone.remoteName()).assertEqual(bookmark.id);
        expect(tombstone.attempts).assertEqual(0);
      }
    });

    it('purgeExpiredAlsoCreatesTombstone', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/expired', '过期', BookmarkSource.MANUAL);
      bookmark.deleted = true;
      bookmark.updatedAt = Date.now() - 31 * 86400000;
      await dao.insert(bookmark);
      const removed = await dao.purgeExpired(30);
      expect(removed).assertLargerOrEqual(1);
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
      const tombstone = await dao.findTombstone(bookmark.id);
      expect(tombstone === undefined).assertFalse();
    });

    it('tombstoneKeepsRemoteDataFromComingBack', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/resurrect', '复活', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await dao.purge(bookmark.id);
      const record = new SyncRecord();
      record.id = bookmark.id;
      record.url = bookmark.url;
      record.title = '远端旧数据';
      record.createdAt = bookmark.createdAt;
      record.updatedAt = bookmark.updatedAt + 1000;
      record.rev = bookmark.rev + 1;
      const applied = await FlowRepository.get().upsertFromRemote(record, '"remote"');
      expect(applied).assertFalse();
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
    });

    it('keepsDirtyWhenBookmarkChangedDuringUpload', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/race', '竞态', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const expectedRev = bookmark.rev;
      const expectedUpdatedAt = bookmark.updatedAt;
      expect(await dao.setRemoteEtagIfUnchanged(
        bookmark.id,
        '"e1"',
        expectedRev,
        expectedUpdatedAt
      )).assertTrue();
      await dao.setTitle(bookmark.id, '同步期间改标题');
      expect(await dao.setRemoteEtagIfUnchanged(
        bookmark.id,
        '"stale"',
        expectedRev,
        expectedUpdatedAt
      )).assertFalse();
      const loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.dirty).assertTrue();
        expect(loaded.remoteEtag).assertEqual('"e1"');
        expect(loaded.title).assertEqual('同步期间改标题');
      }
    });

    it('recordsConflictWhenRemoteOverwritesDirtyLocal', 0, async () => {
      const dao = new BookmarkDao();
      const local = Bookmark.create('https://example.com/conflict', '本地版本', BookmarkSource.MANUAL);
      local.dirty = true;
      await dao.insert(local);
      const record = new SyncRecord();
      record.id = local.id;
      record.url = local.url;
      record.title = '远端版本';
      record.createdAt = local.createdAt;
      record.updatedAt = local.updatedAt + 5000;
      record.rev = local.rev + 2;
      const applied = await FlowRepository.get().upsertFromRemote(record, '"r1"');
      expect(applied).assertTrue();
      expect(await dao.countConflicts()).assertEqual(1);
      const loaded = await dao.findById(local.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.title).assertEqual('远端版本');
        expect(loaded.dirty).assertFalse();
        expect(loaded.remoteEtag).assertEqual('"r1"');
      }
    });

    it('capturesTheSameUrlOnlyOnce', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      await FlowRepository.get().init(context);
      const repo = FlowRepository.get();
      const first = await repo.saveUrl(
        'https://example.com/dedupe?utm_source=newsletter',
        '第一笺',
        [],
        '',
        BookmarkSource.MANUAL
      );
      const second = await repo.saveUrl(
        'example.com/dedupe',
        '第二笺',
        [],
        '',
        BookmarkSource.MANUAL
      );
      expect(first.created).assertTrue();
      expect(second.created).assertFalse();
      expect(first.bookmark.id).assertEqual(second.bookmark.id);
      expect((await new BookmarkDao().listAll(false)).length).assertEqual(1);
    });
  });
}
