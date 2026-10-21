import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { SnapshotStore } from '../../../main/ets/core/service/SnapshotStore';
import { BookmarkSource } from '../../../main/ets/common/Constants';
import { fileIo as fs } from '@kit.CoreFileKit';

export default function snapshotTest() {
  describe('SnapshotTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_snapshot_test.db');
      if (context !== undefined) {
        await FlowRepository.get().init(context);
      }
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('clearAllRemovesSnapshotsAndConflicts', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const first = Bookmark.create('https://example.com/clear-a', '清空甲', BookmarkSource.MANUAL);
      const pathOne = SnapshotStore.save(context, first.id, '正文甲');
      first.snapshotPath = pathOne;
      await dao.insert(first);
      const second = Bookmark.create('https://example.com/clear-b', '清空乙', BookmarkSource.MANUAL);
      const pathTwo = SnapshotStore.save(context, second.id, '正文乙');
      second.snapshotPath = pathTwo;
      await dao.insert(second);
      await dao.insertConflict(first.id, '{"title":"甲"}', '{"title":"甲2"}', 'lww-remote-wins');
      expect(await dao.countConflicts()).assertEqual(1);

      await FlowRepository.get().clearAll();

      expect((await dao.listAll(true)).length).assertEqual(0);
      expect(await dao.countConflicts()).assertEqual(0);
      expect(SnapshotStore.count(context)).assertEqual(0);
      expect(fs.accessSync(pathOne)).assertFalse();
      expect(fs.accessSync(pathTwo)).assertFalse();
    });

    it('purgeExpiredRemovesSnapshotFile', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/expired-file', '过期', BookmarkSource.MANUAL);
      bookmark.deleted = true;
      bookmark.updatedAt = Date.now() - 31 * 86400000;
      const path = SnapshotStore.save(context, bookmark.id, '过期正文');
      bookmark.snapshotPath = path;
      await dao.insert(bookmark);
      expect(fs.accessSync(path)).assertTrue();

      const removed = await FlowRepository.get().purgeExpired();

      expect(removed).assertLargerOrEqual(1);
      expect(fs.accessSync(path)).assertFalse();
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
      const tombstone = await dao.findTombstone(bookmark.id);
      expect(tombstone === undefined).assertFalse();
    });

    it('purgeRemovesSnapshotFile', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/purge-file', '彻底删', BookmarkSource.MANUAL);
      const path = SnapshotStore.save(context, bookmark.id, '正文');
      bookmark.snapshotPath = path;
      await dao.insert(bookmark);

      await FlowRepository.get().purge(bookmark.id);

      expect(fs.accessSync(path)).assertFalse();
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
    });

    it('purgeFromRemoteRemovesOrphanSnapshot', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/orphan-file', '孤立', BookmarkSource.MANUAL);
      const path = SnapshotStore.save(context, bookmark.id, '孤立正文');
      bookmark.snapshotPath = path;
      await dao.insert(bookmark);
      await dao.purgeLocal(bookmark.id);
      expect(fs.accessSync(path)).assertTrue();

      await FlowRepository.get().purgeFromRemote(bookmark.id);

      expect(fs.accessSync(path)).assertFalse();
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
    });
  });
}
