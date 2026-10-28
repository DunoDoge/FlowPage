import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { SyncRecord } from '../../../main/ets/core/sync/SyncRecord';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource } from '../../../main/ets/common/Constants';

export default function conflictTest() {
  describe('ConflictTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_conflict_test.db');
      if (context !== undefined) {
        await FlowRepository.get().init(context);
      }
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('countsAndListsConflicts', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/conflict-list', '冲突', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const remote = SyncRecord.fromBookmark(bookmark);
      remote.title = '远端版本';
      remote.updatedAt = bookmark.updatedAt + 1000;
      await dao.insertConflict(bookmark.id, SyncRecord.fromBookmark(bookmark).toJson(), remote.toJson(), 'lww-remote-wins');
      expect(await FlowRepository.get().countConflicts()).assertEqual(1);
      const records = await FlowRepository.get().listConflicts();
      expect(records.length).assertEqual(1);
      if (records.length > 0) {
        expect(records[0].bookmarkId).assertEqual(bookmark.id);
        expect(records[0].reason).assertEqual('lww-remote-wins');
        expect(records[0].localJson.length > 0).assertTrue();
        expect(records[0].remoteJson.length > 0).assertTrue();
      }
    });

    it('restoresLocalVersionAndDeletesConflict', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/conflict-local', '原版', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const local = SyncRecord.fromBookmark(bookmark);
      local.title = '本地版本';
      const remote = SyncRecord.fromBookmark(bookmark);
      remote.title = '远端版本';
      remote.updatedAt = bookmark.updatedAt + 2000;
      await dao.insertConflict(bookmark.id, local.toJson(), remote.toJson(), 'lww-remote-wins');
      const records = await FlowRepository.get().listConflicts();
      expect(records.length).assertEqual(1);
      const applied = await FlowRepository.get().resolveConflict(records[0].id, true);
      expect(applied).assertTrue();
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.title).assertEqual('本地版本');
        expect(after.dirty).assertTrue();
        expect(after.rev).assertEqual(bookmark.rev + 1);
      }
      expect(await FlowRepository.get().countConflicts()).assertEqual(0);
    });

    it('adoptsRemoteVersionWhenChosen', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/conflict-remote', '原版', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const local = SyncRecord.fromBookmark(bookmark);
      local.title = '本地版本';
      const remote = SyncRecord.fromBookmark(bookmark);
      remote.title = '远端版本';
      remote.updatedAt = bookmark.updatedAt + 3000;
      await dao.insertConflict(bookmark.id, local.toJson(), remote.toJson(), 'lww-remote-wins');
      const records = await FlowRepository.get().listConflicts();
      expect(records.length).assertEqual(1);
      const applied = await FlowRepository.get().resolveConflict(records[0].id, false);
      expect(applied).assertTrue();
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.title).assertEqual('远端版本');
        expect(after.dirty).assertTrue();
      }
      expect(await FlowRepository.get().countConflicts()).assertEqual(0);
    });

    it('resolveKeepsLocalFolderAndSource', 0, async () => {
      const dao = new BookmarkDao();
      const folder = await FlowRepository.get().createFolder('', '稍后读');
      expect(folder === undefined).assertFalse();
      const bookmark = Bookmark.create('https://example.com/conflict-folder', '原版', BookmarkSource.IMPORT);
      if (folder !== undefined) {
        bookmark.folderId = folder.id;
      }
      await dao.insert(bookmark);
      const local = SyncRecord.fromBookmark(bookmark);
      local.title = '本地版本';
      const remote = SyncRecord.fromBookmark(bookmark);
      remote.title = '远端版本';
      remote.updatedAt = bookmark.updatedAt + 3000;
      await dao.insertConflict(bookmark.id, local.toJson(), remote.toJson(), 'lww-remote-wins');
      const records = await FlowRepository.get().listConflicts();
      expect(records.length).assertEqual(1);
      const applied = await FlowRepository.get().resolveConflict(records[0].id, false);
      expect(applied).assertTrue();
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined && folder !== undefined) {
        expect(after.title).assertEqual('远端版本');
        expect(after.folderId).assertEqual(folder.id);
        expect(after.source).assertEqual(BookmarkSource.IMPORT);
      }
    });
  });
}
