import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { FolderDao } from '../../../main/ets/core/db/FolderDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { BookmarkQuery, BookmarkSort } from '../../../main/ets/model/BookmarkQuery';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { AppState } from '../../../main/ets/common/AppState';
import { FolderDragSession } from '../../../main/ets/common/FolderDragSession';
import { BookmarkSource, StreamFilter } from '../../../main/ets/common/Constants';

// Functional tests for the home folder-tree design (openspec add-folder-tree):
// drag-session and row-selection carriers (D11/D14), the "drag never writes
// ordering fields" contract (D6/D14), single-record folder rename/move (D1),
// the root drop zone, and direct-filter stacking with tag/status.
export default function folderHomeTest() {
  describe('FolderHomeTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_folder_home_test.db');
      await FlowRepository.get().init(context);
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('dragSessionCarriesSelectionAndResets', 0, () => {
      const session = FolderDragSession.shared;
      session.end();
      expect(session.active).assertFalse();

      // A drag from an unselected row carries only that row.
      session.begin(['b1'], [], 'b1');
      expect(session.active).assertTrue();
      expect(session.count()).assertEqual(1);
      expect(session.bookmarkIds.length).assertEqual(1);
      expect(session.originRowId).assertEqual('b1');
      session.end();

      // A drag from a selected row carries the whole mixed group.
      session.begin(['b1', 'b2'], ['f1'], 'b2');
      expect(session.active).assertTrue();
      expect(session.count()).assertEqual(3);
      session.end();
      expect(session.active).assertFalse();
      expect(session.bookmarkIds.length).assertEqual(0);
      expect(session.folderIds.length).assertEqual(0);
      expect(session.originRowId).assertEqual('');

      // An empty payload never activates the session (cancelled drag).
      session.begin([], [], '');
      expect(session.active).assertFalse();
    });

    it('rowSelectionMixesTypesAndPrunes', 0, () => {
      const state = AppState.shared;
      state.clearRowSelection();
      expect(state.selectionMode).assertFalse();

      // Mixed selection across the two columns keeps types apart.
      state.toggleBookmarkSelected('b1');
      state.toggleBookmarkSelected('b2');
      state.toggleFolderSelected('f1');
      expect(state.selectionMode).assertTrue();
      expect(state.rowSelectionCount()).assertEqual(3);
      expect(state.isBookmarkSelected('b1')).assertTrue();
      expect(state.isBookmarkSelected('f1')).assertFalse();
      expect(state.isFolderSelected('f1')).assertTrue();

      // Toggling again removes just that id and re-evaluates the mode.
      state.toggleBookmarkSelected('b2');
      expect(state.rowSelectionCount()).assertEqual(2);
      state.toggleBookmarkSelected('b1');
      state.toggleFolderSelected('f1');
      expect(state.selectionMode).assertFalse();
      expect(state.rowSelectionCount()).assertEqual(0);

      // Refresh pruning is per type: live bookmarks prune bookmarks only.
      state.toggleBookmarkSelected('b1');
      state.toggleBookmarkSelected('b-gone');
      state.toggleFolderSelected('f1');
      state.pruneBookmarkSelection(['b1']);
      expect(state.isBookmarkSelected('b-gone')).assertFalse();
      expect(state.isBookmarkSelected('b1')).assertTrue();
      expect(state.isFolderSelected('f1')).assertTrue();
      state.pruneFolderSelection(['f-other']);
      expect(state.isFolderSelected('f1')).assertFalse();
      expect(state.selectionMode).assertTrue();

      // Leaving the mode clears both sets at once.
      state.clearRowSelection();
      expect(state.selectedBookmarkIds.length).assertEqual(0);
      expect(state.selectedFolderIds.length).assertEqual(0);
      expect(state.selectionMode).assertFalse();
    });

    it('dragBatchMoveKeepsOrderingFields', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const first = await repo.createFolder('', '甲');
      const second = await repo.createFolder('', '乙');
      expect(first === undefined).assertFalse();
      expect(second === undefined).assertFalse();
      if (first === undefined || second === undefined) {
        return;
      }
      const early = Bookmark.create('https://example.com/early', '早', BookmarkSource.MANUAL);
      early.createdAt = 5000;
      await dao.insert(early);
      const late = Bookmark.create('https://example.com/late', '晚', BookmarkSource.MANUAL);
      late.createdAt = 9000;
      late.folderId = second.id;
      await dao.insert(late);

      const positionFirstBefore = first.position;
      const positionSecondBefore = second.position;

      // Drag path: one bookmark plus one folder dropped onto folder 甲.
      const outcome = await repo.batchMove([early.id], [second.id], first.id);
      expect(outcome.done).assertEqual(2);
      expect(outcome.skipped).assertEqual(0);

      const earlyAfter = await dao.findById(early.id);
      expect(earlyAfter === undefined).assertFalse();
      if (earlyAfter !== undefined) {
        expect(earlyAfter.folderId).assertEqual(first.id);
        // createdAt is the browser ADD_DATE carrier: a move must never touch it.
        expect(earlyAfter.createdAt).assertEqual(5000);
      }
      const secondAfter = await folderDao.findById(second.id);
      expect(secondAfter === undefined).assertFalse();
      if (secondAfter !== undefined) {
        expect(secondAfter.parentId).assertEqual(first.id);
        expect(secondAfter.position).assertEqual(positionSecondBefore);
      }
      const firstAfter = await folderDao.findById(first.id);
      expect(firstAfter === undefined).assertFalse();
      if (firstAfter !== undefined) {
        expect(firstAfter.position).assertEqual(positionFirstBefore);
      }

      // Members inside the target folder still come out in createdAt order.
      const booksQuery = new BookmarkQuery();
      booksQuery.folderId = first.id;
      booksQuery.sort = BookmarkSort.CREATED_ASC;
      const books = await dao.queryPage(booksQuery, 0, 50);
      expect(books.length).assertEqual(1);
      if (books.length === 1) {
        expect(books[0].id).assertEqual(early.id);
      }
    });

    it('moveFolderLeavesMemberRecordsUntouched', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const dev = await repo.createFolder('', '开发');
      const archive = await repo.createFolder('', '归档');
      expect(dev === undefined).assertFalse();
      expect(archive === undefined).assertFalse();
      if (dev === undefined || archive === undefined) {
        return;
      }
      const member = Bookmark.create('https://example.com/member', '成员书签', BookmarkSource.MANUAL);
      member.folderId = dev.id;
      await dao.insert(member);
      const memberBefore = await dao.findById(member.id);
      expect(memberBefore === undefined).assertFalse();
      if (memberBefore === undefined) {
        return;
      }

      const moved = await repo.moveFolder(dev.id, archive.id);
      expect(moved).assertTrue();

      // Only the folder record changes: the member keeps its row untouched.
      const memberAfter = await dao.findById(member.id);
      expect(memberAfter === undefined).assertFalse();
      if (memberAfter !== undefined) {
        expect(memberAfter.folderId).assertEqual(dev.id);
        expect(memberAfter.rev).assertEqual(memberBefore.rev);
        expect(memberAfter.updatedAt).assertEqual(memberBefore.updatedAt);
      }
      const devAfter = await new FolderDao().findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.parentId).assertEqual(archive.id);
        expect(devAfter.dirty).assertTrue();
      }
      const devQuery = new BookmarkQuery();
      devQuery.folderId = dev.id;
      const devBooks = await dao.queryPage(devQuery, 0, 50);
      expect(devBooks.length).assertEqual(1);
      if (devBooks.length === 1) {
        expect(devBooks[0].id).assertEqual(member.id);
      }
    });

    it('renameFolderLeavesMembersUntouched', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const member = Bookmark.create('https://example.com/stable', '不动书签', BookmarkSource.MANUAL);
      member.folderId = dev.id;
      await dao.insert(member);
      const memberBefore = await dao.findById(member.id);
      expect(memberBefore === undefined).assertFalse();
      if (memberBefore === undefined) {
        return;
      }

      const renamed = await repo.renameFolder(dev.id, '研发');
      expect(renamed).assertTrue();

      const memberAfter = await dao.findById(member.id);
      expect(memberAfter === undefined).assertFalse();
      if (memberAfter !== undefined) {
        expect(memberAfter.rev).assertEqual(memberBefore.rev);
        expect(memberAfter.updatedAt).assertEqual(memberBefore.updatedAt);
        expect(memberAfter.folderId).assertEqual(dev.id);
      }
      const devAfter = await new FolderDao().findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.name).assertEqual('研发');
      }
    });

    it('dropToRootMovesBookmarkOut', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const front = await repo.createFolder('', '前端');
      expect(front === undefined).assertFalse();
      if (front === undefined) {
        return;
      }
      const member = Bookmark.create('https://example.com/escape', '根投放书签', BookmarkSource.MANUAL);
      member.folderId = front.id;
      await dao.insert(member);
      expect(await repo.countFolderBookmarks(front.id)).assertEqual(1);

      // The root drop zone resolves to the empty target id.
      const outcome = await repo.batchMove([member.id], [], '');
      expect(outcome.done).assertEqual(1);
      expect(outcome.skipped).assertEqual(0);

      const memberAfter = await dao.findById(member.id);
      expect(memberAfter === undefined).assertFalse();
      if (memberAfter !== undefined) {
        expect(memberAfter.folderId).assertEqual('');
      }
      expect(await repo.countFolderBookmarks(front.id)).assertEqual(0);
    });

    it('folderFilterStacksWithTagAndStatus', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }

      const batch: Bookmark[] = [];
      const taggedArchived = Bookmark.create('https://example.com/ta', '标签归档', BookmarkSource.MANUAL);
      taggedArchived.folderId = dev.id;
      taggedArchived.tags = ['技术'];
      taggedArchived.archived = true;
      taggedArchived.rebuildSearch();
      batch.push(taggedArchived);
      const taggedActive = Bookmark.create('https://example.com/tv', '标签活跃', BookmarkSource.MANUAL);
      taggedActive.folderId = dev.id;
      taggedActive.tags = ['技术'];
      taggedActive.rebuildSearch();
      batch.push(taggedActive);
      const plainArchived = Bookmark.create('https://example.com/pa', '无标签归档', BookmarkSource.MANUAL);
      plainArchived.folderId = dev.id;
      plainArchived.archived = true;
      plainArchived.rebuildSearch();
      batch.push(plainArchived);
      const outsideTagged = Bookmark.create('https://example.com/ox', '文件夹外', BookmarkSource.MANUAL);
      outsideTagged.tags = ['技术'];
      outsideTagged.rebuildSearch();
      batch.push(outsideTagged);
      await dao.insertBatch(batch);

      // Folder + tag under the default ALL view: the archived row is hidden,
      // the folder boundary holds and the tag narrows inside it.
      const folderTag = new BookmarkQuery();
      folderTag.folderId = dev.id;
      folderTag.tag = '技术';
      const folderTagRows = await dao.queryPage(folderTag, 0, 50);
      expect(folderTagRows.length).assertEqual(1);
      if (folderTagRows.length === 1) {
        expect(folderTagRows[0].id).assertEqual(taggedActive.id);
      }

      // Folder + tag + archived status: only the one row satisfies all three.
      const stacked = new BookmarkQuery();
      stacked.folderId = dev.id;
      stacked.tag = '技术';
      stacked.filter = StreamFilter.ARCHIVED;
      const rows = await dao.queryPage(stacked, 0, 50);
      expect(rows.length).assertEqual(1);
      if (rows.length === 1) {
        expect(rows[0].id).assertEqual(taggedArchived.id);
      }

      // Folder + keyword keeps the direct-membership boundary.
      const keywordQuery = new BookmarkQuery();
      keywordQuery.folderId = dev.id;
      keywordQuery.keyword = '标签';
      const keywordRows = await dao.queryPage(keywordQuery, 0, 50);
      expect(keywordRows.length).assertEqual(1);
    });
  });
}
