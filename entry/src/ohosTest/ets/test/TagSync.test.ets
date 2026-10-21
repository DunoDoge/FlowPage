import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { BookmarkQuery } from '../../../main/ets/model/BookmarkQuery';
import { SyncRecord } from '../../../main/ets/core/sync/SyncRecord';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource } from '../../../main/ets/common/Constants';

export default function tagSyncTest() {
  describe('TagSyncTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_tag_test.db');
      if (context !== undefined) {
        await FlowRepository.get().init(context);
      }
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('renameTagTouchesBookmarksForSync', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/rename-tag', '改名', BookmarkSource.MANUAL);
      bookmark.tags = ['旧名'];
      bookmark.rebuildSearch();
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"e1"', bookmark.rev, bookmark.updatedAt);
      const before = await dao.findById(bookmark.id);
      expect(before === undefined).assertFalse();
      if (before === undefined) {
        return;
      }
      expect(before.dirty).assertFalse();
      const tags = await dao.listTags();
      let tagId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '旧名') {
          tagId = tags[i].id;
        }
      }
      expect(tagId.length > 0).assertTrue();
      await dao.renameTag(tagId, '新名');
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.dirty).assertTrue();
        expect(after.rev).assertEqual(before.rev + 1);
        expect(after.tags.length).assertEqual(1);
        expect(after.tags[0]).assertEqual('新名');
        const record = SyncRecord.fromBookmark(after);
        expect(record.tags[0]).assertEqual('新名');
      }
    });

    it('mergeTagsTouchesOnlySourceSide', 0, async () => {
      const dao = new BookmarkDao();
      const first = Bookmark.create('https://example.com/merge-a', '甲', BookmarkSource.MANUAL);
      first.tags = ['甲组'];
      first.rebuildSearch();
      await dao.insert(first);
      const second = Bookmark.create('https://example.com/merge-b', '乙', BookmarkSource.MANUAL);
      second.tags = ['乙组'];
      second.rebuildSearch();
      await dao.insert(second);
      await dao.setRemoteEtagIfUnchanged(first.id, '"a"', first.rev, first.updatedAt);
      await dao.setRemoteEtagIfUnchanged(second.id, '"b"', second.rev, second.updatedAt);
      const beforeFirst = await dao.findById(first.id);
      const beforeSecond = await dao.findById(second.id);
      expect(beforeFirst === undefined).assertFalse();
      expect(beforeSecond === undefined).assertFalse();
      if (beforeFirst === undefined || beforeSecond === undefined) {
        return;
      }
      const tags = await dao.listTags();
      let sourceId = '';
      let targetId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '甲组') {
          sourceId = tags[i].id;
        }
        if (tags[i].name === '乙组') {
          targetId = tags[i].id;
        }
      }
      await dao.mergeTags(sourceId, targetId);
      const afterFirst = await dao.findById(first.id);
      const afterSecond = await dao.findById(second.id);
      expect(afterFirst === undefined).assertFalse();
      expect(afterSecond === undefined).assertFalse();
      if (afterFirst !== undefined) {
        expect(afterFirst.tags[0]).assertEqual('乙组');
        expect(afterFirst.dirty).assertTrue();
        expect(afterFirst.rev).assertLarger(beforeFirst.rev);
      }
      if (afterSecond !== undefined) {
        expect(afterSecond.tags[0]).assertEqual('乙组');
        expect(afterSecond.dirty).assertFalse();
        expect(afterSecond.rev).assertEqual(beforeSecond.rev);
        expect(afterSecond.updatedAt).assertEqual(beforeSecond.updatedAt);
      }
      const remaining = await dao.listTags();
      let hasSource = false;
      for (let i = 0; i < remaining.length; i++) {
        if (remaining[i].name === '甲组') {
          hasSource = true;
        }
      }
      expect(hasSource).assertFalse();
    });

    it('renameTagRebuildsSearchText', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/search-rename', '无标签标题', BookmarkSource.MANUAL);
      bookmark.tags = ['旧标签'];
      bookmark.rebuildSearch();
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"sr1"', bookmark.rev, bookmark.updatedAt);
      const tags = await dao.listTags();
      let tagId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '旧标签') {
          tagId = tags[i].id;
        }
      }
      await dao.renameTag(tagId, '新标签');
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.searchText.indexOf('新标签') >= 0).assertTrue();
        expect(after.searchText.indexOf('旧标签') >= 0).assertFalse();
      }
      const query = new BookmarkQuery();
      query.keyword = '新标签';
      const found = await dao.queryPage(query, 0, 10);
      expect(found.length).assertEqual(1);
      const stale = new BookmarkQuery();
      stale.keyword = '旧标签';
      const missing = await dao.queryPage(stale, 0, 10);
      expect(missing.length).assertEqual(0);
    });

    it('renameToExistingNameRebuildsSearchTextWithoutTouchingTargetOnly', 0, async () => {
      const dao = new BookmarkDao();
      const targetOnly = Bookmark.create('https://example.com/collision-target', '只含目标', BookmarkSource.MANUAL);
      targetOnly.tags = ['目标组'];
      targetOnly.rebuildSearch();
      await dao.insert(targetOnly);
      await dao.setRemoteEtagIfUnchanged(targetOnly.id, '"ct1"', targetOnly.rev, targetOnly.updatedAt);
      const sourceOnly = Bookmark.create('https://example.com/collision-source', '只含源', BookmarkSource.MANUAL);
      sourceOnly.tags = ['源组'];
      sourceOnly.rebuildSearch();
      await dao.insert(sourceOnly);
      const beforeTarget = await dao.findById(targetOnly.id);
      expect(beforeTarget === undefined).assertFalse();
      if (beforeTarget === undefined) {
        return;
      }
      const tags = await dao.listTags();
      let sourceId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '源组') {
          sourceId = tags[i].id;
        }
      }
      const merged = await dao.renameTag(sourceId, '目标组');
      expect(merged).assertTrue();
      const afterTarget = await dao.findById(targetOnly.id);
      const afterSource = await dao.findById(sourceOnly.id);
      expect(afterTarget === undefined).assertFalse();
      expect(afterSource === undefined).assertFalse();
      if (afterTarget !== undefined) {
        expect(afterTarget.dirty).assertFalse();
        expect(afterTarget.rev).assertEqual(beforeTarget.rev);
        expect(afterTarget.searchText.indexOf('目标组') >= 0).assertTrue();
      }
      if (afterSource !== undefined) {
        expect(afterSource.dirty).assertTrue();
        expect(afterSource.tags[0]).assertEqual('目标组');
        expect(afterSource.searchText.indexOf('目标组') >= 0).assertTrue();
        expect(afterSource.searchText.indexOf('源组') >= 0).assertFalse();
      }
    });

    it('deleteTagRebuildsSearchText', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/search-delete', '无标签标题', BookmarkSource.MANUAL);
      bookmark.tags = ['保留组', '删掉组'];
      bookmark.rebuildSearch();
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"sd1"', bookmark.rev, bookmark.updatedAt);
      const tags = await dao.listTags();
      let tagId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '删掉组') {
          tagId = tags[i].id;
        }
      }
      await dao.deleteTag(tagId);
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.searchText.indexOf('保留组') >= 0).assertTrue();
        expect(after.searchText.indexOf('删掉组') >= 0).assertFalse();
        expect(after.dirty).assertTrue();
      }
    });

    it('deleteTagKeepsBookmarksAndMarksDirty', 0, async () => {
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/delete-tag', '删标签', BookmarkSource.MANUAL);
      bookmark.tags = ['待删'];
      bookmark.rebuildSearch();
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"e2"', bookmark.rev, bookmark.updatedAt);
      const before = await dao.findById(bookmark.id);
      expect(before === undefined).assertFalse();
      if (before === undefined) {
        return;
      }
      const tags = await dao.listTags();
      let tagId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '待删') {
          tagId = tags[i].id;
        }
      }
      await dao.deleteTag(tagId);
      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.tags.length).assertEqual(0);
        expect(after.dirty).assertTrue();
        expect(after.rev).assertEqual(before.rev + 1);
      }
    });

    it('renameToExistingNameMergesInsteadOfCrashing', 0, async () => {
      const dao = new BookmarkDao();
      const first = Bookmark.create('https://example.com/collision-a', '碰撞甲', BookmarkSource.MANUAL);
      first.tags = ['同名'];
      first.rebuildSearch();
      await dao.insert(first);
      const second = Bookmark.create('https://example.com/collision-b', '碰撞乙', BookmarkSource.MANUAL);
      second.tags = ['目标'];
      second.rebuildSearch();
      await dao.insert(second);
      const tags = await dao.listTags();
      let sourceId = '';
      let targetId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '目标') {
          sourceId = tags[i].id;
        }
        if (tags[i].name === '同名') {
          targetId = tags[i].id;
        }
      }
      const merged = await dao.renameTag(sourceId, '同名');
      expect(merged).assertTrue();
      const after = await dao.findById(second.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.tags.length).assertEqual(1);
        expect(after.tags[0]).assertEqual('同名');
        expect(after.dirty).assertTrue();
      }
      const remaining = await dao.listTags();
      let sameNameCount = 0;
      for (let i = 0; i < remaining.length; i++) {
        if (remaining[i].name === '同名') {
          sameNameCount = sameNameCount + 1;
        }
      }
      expect(sameNameCount).assertEqual(1);
      expect(targetId.length > 0).assertTrue();
    });

    it('listTagsExcludesTrashedBookmarks', 0, async () => {
      const dao = new BookmarkDao();
      const live = Bookmark.create('https://example.com/tag-live', '还在', BookmarkSource.MANUAL);
      live.tags = ['保留'];
      live.rebuildSearch();
      await dao.insert(live);
      const trashed = Bookmark.create('https://example.com/tag-trash', '已删', BookmarkSource.MANUAL);
      trashed.tags = ['只存在回收站', '保留'];
      trashed.rebuildSearch();
      await dao.insert(trashed);
      await dao.softDelete(trashed.id);
      const tags = await dao.listTags();
      let liveCount = -1;
      let trashOnlyFound = false;
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '保留') {
          liveCount = tags[i].count;
        }
        if (tags[i].name === '只存在回收站') {
          trashOnlyFound = true;
        }
      }
      expect(liveCount).assertEqual(1);
      expect(trashOnlyFound).assertFalse();
    });
  });
}
