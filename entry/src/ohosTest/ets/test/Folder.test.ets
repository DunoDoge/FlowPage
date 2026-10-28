import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { FolderDao, buildFolderTree } from '../../../main/ets/core/db/FolderDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { Folder, FolderNode } from '../../../main/ets/model/Folder';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkQuery } from '../../../main/ets/model/BookmarkQuery';
import { BookmarkSource } from '../../../main/ets/common/Constants';
import { AppState } from '../../../main/ets/common/AppState';
import { SyncRecord } from '../../../main/ets/core/sync/SyncRecord';
import { FolderSyncRecord } from '../../../main/ets/core/sync/FolderSyncRecord';

function makeFolder(id: string, parentId: string, name: string, updatedAt: number): Folder {
  const folder = new Folder();
  folder.id = id;
  folder.parentId = parentId;
  folder.name = name;
  folder.updatedAt = updatedAt;
  return folder;
}

export default function folderTest() {
  describe('FolderTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_folder_test.db');
      await FlowRepository.get().init(context);
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('buildsEmptyTree', 0, () => {
      const roots = buildFolderTree([], new Map<string, number>());
      expect(roots.length).assertEqual(0);
    });

    it('buildsDeepTreeWithCounts', 0, () => {
      const folders: Folder[] = [
        makeFolder('a', '', '书签栏', 1),
        makeFolder('b', 'a', '开发', 2),
        makeFolder('c', 'b', '前端', 3)
      ];
      const counts = new Map<string, number>();
      counts.set('b', 2);
      counts.set('c', 5);
      const roots = buildFolderTree(folders, counts);
      expect(roots.length).assertEqual(1);
      expect(roots[0].folder.id).assertEqual('a');
      expect(roots[0].directCount).assertEqual(0);
      expect(roots[0].totalCount).assertEqual(7);
      expect(roots[0].children.length).assertEqual(1);
      const child = roots[0].children[0];
      expect(child.folder.id).assertEqual('b');
      expect(child.totalCount).assertEqual(7);
      expect(child.path).assertEqual('书签栏/开发');
    });

    it('hidesDanglingSubtrees', 0, () => {
      const folders: Folder[] = [
        makeFolder('a', '', '根级', 1),
        makeFolder('x', 'missing', '悬空', 2)
      ];
      const roots = buildFolderTree(folders, new Map<string, number>());
      expect(roots.length).assertEqual(1);
      expect(roots[0].folder.id).assertEqual('a');
    });

    it('breaksCycleAtNewestEdge', 0, () => {
      // x -> y -> x cycle; y was updated later, so y re-attaches to root and x stays under y.
      const folders: Folder[] = [
        makeFolder('x', 'y', 'X', 100),
        makeFolder('y', 'x', 'Y', 200)
      ];
      const roots = buildFolderTree(folders, new Map<string, number>());
      expect(roots.length).assertEqual(1);
      expect(roots[0].folder.id).assertEqual('y');
      expect(roots[0].children.length).assertEqual(1);
      expect(roots[0].children[0].folder.id).assertEqual('x');
    });

    it('ignoresDeletedFolders', 0, () => {
      const live = makeFolder('a', '', '活的', 1);
      const dead = makeFolder('b', '', '死的', 2);
      dead.deleted = true;
      const roots = buildFolderTree([live, dead], new Map<string, number>());
      expect(roots.length).assertEqual(1);
      expect(roots[0].folder.id).assertEqual('a');
    });

    it('rejectsSameNameSiblings', 0, async () => {
      const repo = FlowRepository.get();
      const first = await repo.createFolder('', '开发');
      expect(first === undefined).assertFalse();
      const second = await repo.createFolder('', '开发');
      expect(second === undefined).assertTrue();
      const renamed = await repo.renameFolder('not-exist', '别的');
      expect(renamed).assertFalse();
    });

    it('renameRejectsSiblingNameClash', 0, async () => {
      const repo = FlowRepository.get();
      const one = await repo.createFolder('', '一');
      const two = await repo.createFolder('', '二');
      expect(one === undefined).assertFalse();
      expect(two === undefined).assertFalse();
      if (one === undefined || two === undefined) {
        return;
      }
      const renamed = await repo.renameFolder(two.id, '一');
      expect(renamed).assertFalse();
      const renamedOk = await repo.renameFolder(two.id, '二点零');
      expect(renamedOk).assertTrue();
    });

    it('allowsSameNameAfterSoftDelete', 0, async () => {
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', '临时');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      await repo.deleteFolderCascade(folder.id);
      const again = await repo.createFolder('', '临时');
      expect(again === undefined).assertFalse();
    });

    it('moveRejectsOwnDescendant', 0, async () => {
      const repo = FlowRepository.get();
      const top = await repo.createFolder('', '顶层');
      expect(top === undefined).assertFalse();
      if (top === undefined) {
        return;
      }
      const nested = await repo.createFolder(top.id, '嵌套');
      expect(nested === undefined).assertFalse();
      if (nested === undefined) {
        return;
      }
      const intoSelf = await repo.moveFolder(top.id, top.id);
      expect(intoSelf).assertFalse();
      const intoChild = await repo.moveFolder(top.id, nested.id);
      expect(intoChild).assertFalse();
      const ok = await repo.moveFolder(nested.id, '');
      expect(ok).assertTrue();
    });

    it('moveRejectsSiblingNameClashInTarget', 0, async () => {
      const repo = FlowRepository.get();
      const folderDao = new FolderDao();
      const one = await repo.createFolder('', '一');
      const two = await repo.createFolder('', '二');
      expect(one === undefined).assertFalse();
      expect(two === undefined).assertFalse();
      if (one === undefined || two === undefined) {
        return;
      }
      const settled = await repo.createFolder(two.id, '重复');
      const moving = await repo.createFolder(one.id, '重复');
      expect(settled === undefined).assertFalse();
      expect(moving === undefined).assertFalse();
      if (settled === undefined || moving === undefined) {
        return;
      }
      // The partial unique index would reject the row; move must decline
      // instead of throwing mid-batch.
      const moved = await repo.moveFolder(moving.id, two.id);
      expect(moved).assertFalse();
      const movingAfter = await folderDao.findById(moving.id);
      expect(movingAfter === undefined).assertFalse();
      if (movingAfter !== undefined) {
        expect(movingAfter.parentId).assertEqual(one.id);
      }
      const ok = await repo.moveFolder(moving.id, '');
      expect(ok).assertTrue();
    });

    it('cascadeSoftDeleteFoldersAndBookmarks', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const top = await repo.createFolder('', '顶层');
      expect(top === undefined).assertFalse();
      if (top === undefined) {
        return;
      }
      const nested = await repo.createFolder(top.id, '嵌套');
      expect(nested === undefined).assertFalse();

      const inTop = Bookmark.create('https://example.com/in-top', '顶层书签', BookmarkSource.MANUAL);
      inTop.folderId = top.id;
      await dao.insert(inTop);
      const inNested = Bookmark.create('https://example.com/in-nested', '嵌套书签', BookmarkSource.MANUAL);
      if (nested !== undefined) {
        inNested.folderId = nested.id;
      }
      await dao.insert(inNested);
      const outside = Bookmark.create('https://example.com/outside', '无关书签', BookmarkSource.MANUAL);
      await dao.insert(outside);

      const affected = await repo.deleteFolderCascade(top.id);
      expect(affected).assertEqual(2);

      const topAfter = await new FolderDao().findById(top.id);
      expect(topAfter === undefined).assertFalse();
      if (topAfter !== undefined) {
        expect(topAfter.deleted).assertTrue();
      }
      const inTopAfter = await dao.findById(inTop.id);
      expect(inTopAfter === undefined).assertFalse();
      if (inTopAfter !== undefined) {
        expect(inTopAfter.deleted).assertTrue();
      }
      const outsideAfter = await dao.findById(outside.id);
      expect(outsideAfter === undefined).assertFalse();
      if (outsideAfter !== undefined) {
        expect(outsideAfter.deleted).assertFalse();
      }
      const tree = await repo.folderTree();
      expect(tree.length).assertEqual(0);
    });

    it('queriesByDirectFolderMembership', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      const front = await repo.createFolder(dev !== undefined ? dev.id : '', '前端');
      expect(front === undefined).assertFalse();
      if (dev === undefined || front === undefined) {
        return;
      }
      const inFront = Bookmark.create('https://example.com/front', '前端书签', BookmarkSource.MANUAL);
      inFront.folderId = front.id;
      await dao.insert(inFront);
      const inDev = Bookmark.create('https://example.com/dev', '开发书签', BookmarkSource.MANUAL);
      inDev.folderId = dev.id;
      await dao.insert(inDev);
      const atRoot = Bookmark.create('https://example.com/root', '根书签', BookmarkSource.MANUAL);
      await dao.insert(atRoot);

      const query = new BookmarkQuery();
      query.folderId = dev.id;
      const rows = await dao.queryPage(query, 0, 50);
      expect(rows.length).assertEqual(1);
      if (rows.length === 1) {
        expect(rows[0].id).assertEqual(inDev.id);
      }
      // Descendant bookmarks stay out of the parent's direct filter and are
      // reached through their own folder row.
      const frontQuery = new BookmarkQuery();
      frontQuery.folderId = front.id;
      const frontRows = await dao.queryPage(frontQuery, 0, 50);
      expect(frontRows.length).assertEqual(1);
      if (frontRows.length === 1) {
        expect(frontRows[0].id).assertEqual(inFront.id);
      }
      // Stacking with keyword search keeps the direct-folder semantics.
      const stacked = new BookmarkQuery();
      stacked.folderId = dev.id;
      stacked.keyword = '开发';
      expect((await dao.queryPage(stacked, 0, 50)).length).assertEqual(1);
      const stackedMiss = new BookmarkQuery();
      stackedMiss.folderId = dev.id;
      stackedMiss.keyword = '前端';
      expect((await dao.queryPage(stackedMiss, 0, 50)).length).assertEqual(0);
    });

    it('findOrCreateReusesCache', 0, async () => {
      const folderDao = new FolderDao();
      const cache = new Map<string, string>();
      const first = await folderDao.findOrCreate('', '收藏', cache);
      const second = await folderDao.findOrCreate('', '收藏', cache);
      expect(first).assertEqual(second);
      const all = await folderDao.listAll(false);
      expect(all.length).assertEqual(1);
    });

    it('batchMoveMixedSelectionSkipsOwnSubtree', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const top = await repo.createFolder('', '顶层');
      const mid = await repo.createFolder('', '中间');
      expect(top === undefined).assertFalse();
      expect(mid === undefined).assertFalse();
      if (top === undefined || mid === undefined) {
        return;
      }
      const child = await repo.createFolder(top.id, '子级');
      expect(child === undefined).assertFalse();
      if (child === undefined) {
        return;
      }
      const moving = Bookmark.create('https://example.com/move-me', '移动书签', BookmarkSource.MANUAL);
      await dao.insert(moving);
      const staying = Bookmark.create('https://example.com/stay', '原地书签', BookmarkSource.MANUAL);
      staying.folderId = mid.id;
      await dao.insert(staying);

      // top cannot move below its own child; the bookmark still moves.
      const outcome = await repo.batchMove([moving.id], [top.id], child.id);
      expect(outcome.done).assertEqual(1);
      expect(outcome.skipped).assertEqual(1);

      const movedAfter = await dao.findById(moving.id);
      expect(movedAfter === undefined).assertFalse();
      if (movedAfter !== undefined) {
        expect(movedAfter.folderId).assertEqual(child.id);
        expect(movedAfter.dirty).assertTrue();
      }
      const topAfter = await new FolderDao().findById(top.id);
      expect(topAfter === undefined).assertFalse();
      if (topAfter !== undefined) {
        expect(topAfter.parentId).assertEqual('');
      }
      const stayingAfter = await dao.findById(staying.id);
      expect(stayingAfter === undefined).assertFalse();
      if (stayingAfter !== undefined) {
        expect(stayingAfter.folderId).assertEqual(mid.id);
      }
    });

    it('batchMoveOutOneLevelSkipsRoot', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const top = await repo.createFolder('', '顶层');
      expect(top === undefined).assertFalse();
      if (top === undefined) {
        return;
      }
      const nested = await repo.createFolder(top.id, '嵌套');
      expect(nested === undefined).assertFalse();
      if (nested === undefined) {
        return;
      }
      const lib = await repo.createFolder(nested.id, '组件库');
      expect(lib === undefined).assertFalse();
      if (lib === undefined) {
        return;
      }
      const inNested = Bookmark.create('https://example.com/in-nested', '嵌套书签', BookmarkSource.MANUAL);
      inNested.folderId = nested.id;
      await dao.insert(inNested);
      const atRoot = Bookmark.create('https://example.com/at-root', '根书签', BookmarkSource.MANUAL);
      await dao.insert(atRoot);

      const outcome = await repo.batchMoveOut([inNested.id, atRoot.id], [lib.id, top.id]);
      expect(outcome.done).assertEqual(2);
      expect(outcome.skipped).assertEqual(2);

      const inNestedAfter = await dao.findById(inNested.id);
      expect(inNestedAfter === undefined).assertFalse();
      if (inNestedAfter !== undefined) {
        expect(inNestedAfter.folderId).assertEqual(top.id);
      }
      const atRootAfter = await dao.findById(atRoot.id);
      expect(atRootAfter === undefined).assertFalse();
      if (atRootAfter !== undefined) {
        expect(atRootAfter.folderId).assertEqual('');
      }
      const libAfter = await new FolderDao().findById(lib.id);
      expect(libAfter === undefined).assertFalse();
      if (libAfter !== undefined) {
        expect(libAfter.parentId).assertEqual(top.id);
      }
    });

    it('setBookmarkFolderMovesBetweenTreePositions', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const front = await repo.createFolder(dev.id, '前端');
      const back = await repo.createFolder(dev.id, '后端');
      expect(front === undefined).assertFalse();
      expect(back === undefined).assertFalse();
      if (front === undefined || back === undefined) {
        return;
      }
      const bookmark = Bookmark.create('https://example.com/switch', '换位书签', BookmarkSource.MANUAL);
      bookmark.folderId = front.id;
      await dao.insert(bookmark);

      await repo.setBookmarkFolder(bookmark.id, back.id);

      const frontBooks = await repo.bookmarksInFolder(front.id);
      expect(frontBooks.length).assertEqual(0);
      const backBooks = await repo.bookmarksInFolder(back.id);
      expect(backBooks.length).assertEqual(1);
      if (backBooks.length === 1) {
        expect(backBooks[0].id).assertEqual(bookmark.id);
        expect(backBooks[0].dirty).assertTrue();
      }
      const frontQuery = new BookmarkQuery();
      frontQuery.folderId = front.id;
      expect((await dao.queryPage(frontQuery, 0, 50)).length).assertEqual(0);
      const backQuery = new BookmarkQuery();
      backQuery.folderId = back.id;
      expect((await dao.queryPage(backQuery, 0, 50)).length).assertEqual(1);

      await repo.setBookmarkFolder(bookmark.id, '');
      const rootBooks = await repo.bookmarksInFolder('');
      let sawAtRoot = false;
      for (let i = 0; i < rootBooks.length; i++) {
        if (rootBooks[i].id === bookmark.id) {
          sawAtRoot = true;
        }
      }
      expect(sawAtRoot).assertTrue();
    });

    it('bookmarksInFolderReturnsDirectOnlySortedByCreatedAt', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const top = await repo.createFolder('', '顶层');
      const nested = await repo.createFolder('', '同级');
      expect(top === undefined).assertFalse();
      expect(nested === undefined).assertFalse();
      if (top === undefined || nested === undefined) {
        return;
      }
      const child = await repo.createFolder(top.id, '子级');
      expect(child === undefined).assertFalse();
      if (child === undefined) {
        return;
      }

      const late = Bookmark.create('https://example.com/late', '晚到', BookmarkSource.MANUAL);
      late.folderId = top.id;
      late.createdAt = 3000;
      await dao.insert(late);
      const early = Bookmark.create('https://example.com/early', '早到', BookmarkSource.MANUAL);
      early.folderId = top.id;
      early.createdAt = 1000;
      await dao.insert(early);
      const inChild = Bookmark.create('https://example.com/child', '子级书签', BookmarkSource.MANUAL);
      if (child !== undefined) {
        inChild.folderId = child.id;
      }
      await dao.insert(inChild);
      const atRoot = Bookmark.create('https://example.com/root', '根书签', BookmarkSource.MANUAL);
      await dao.insert(atRoot);

      const books = await repo.bookmarksInFolder(top.id);
      expect(books.length).assertEqual(2);
      if (books.length === 2) {
        expect(books[0].id).assertEqual(early.id);
        expect(books[1].id).assertEqual(late.id);
      }
      const total = await repo.countFolderBookmarks(top.id);
      expect(total).assertEqual(3);
    });

    it('createsFolderWithSlashNameLiterally', 0, async () => {
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', 'AI/ML');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      const tree = await repo.folderTree();
      expect(tree.length).assertEqual(1);
      expect(tree[0].folder.name).assertEqual('AI/ML');
      expect(tree[0].children.length).assertEqual(0);
    });

    it('exportJsonCarriesFolderStructure', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const front = await repo.createFolder(dev.id, '前端');
      expect(front === undefined).assertFalse();
      if (front === undefined) {
        return;
      }
      const inFront = Bookmark.create('https://example.com/json', 'JSON 书签', BookmarkSource.MANUAL);
      inFront.folderId = front.id;
      await dao.insert(inFront);

      const json = await repo.exportJson();
      expect(json.indexOf('"folders"') >= 0).assertTrue();
      expect(json.indexOf('"name": "开发"') >= 0).assertTrue();
      expect(json.indexOf('"name": "前端"') >= 0).assertTrue();
      expect(json.indexOf(`"parentId": "${dev.id}"`) >= 0).assertTrue();
      expect(json.indexOf(`"folderId": "${front.id}"`) >= 0).assertTrue();
      expect(json.indexOf('"url": "https://example.com/json"') >= 0).assertTrue();
      expect(json.indexOf('"title": "JSON 书签"') >= 0).assertTrue();
    });

    it('batchDeleteMixedSelectionTrashesAll', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const top = await repo.createFolder('', '顶层');
      expect(top === undefined).assertFalse();
      if (top === undefined) {
        return;
      }
      const nested = await repo.createFolder(top.id, '嵌套');
      expect(nested === undefined).assertFalse();
      if (nested === undefined) {
        return;
      }
      const inNested = Bookmark.create('https://example.com/in-nested', '嵌套书签', BookmarkSource.MANUAL);
      inNested.folderId = nested.id;
      await dao.insert(inNested);
      const inTop = Bookmark.create('https://example.com/in-top', '顶层书签', BookmarkSource.MANUAL);
      inTop.folderId = top.id;
      await dao.insert(inTop);
      const loose = Bookmark.create('https://example.com/loose', '散书签', BookmarkSource.MANUAL);
      await dao.insert(loose);
      const outside = Bookmark.create('https://example.com/outside', '无关书签', BookmarkSource.MANUAL);
      await dao.insert(outside);

      // loose selection overlapping the subtree is deduped in the impact.
      const impact = await repo.batchDeleteImpact([loose.id, inTop.id], [top.id]);
      expect(impact.folders).assertEqual(1);
      expect(impact.subtreeBooks).assertEqual(2);
      expect(impact.looseBooks).assertEqual(1);

      const tickBefore = AppState.shared.refreshTick;
      const outcome = await repo.batchDelete([loose.id, inTop.id], [top.id]);
      expect(outcome.done).assertEqual(3);
      expect(outcome.skipped).assertEqual(0);
      expect(AppState.shared.refreshTick - tickBefore).assertEqual(1);

      const folderDao = new FolderDao();
      const topAfter = await folderDao.findById(top.id);
      expect(topAfter === undefined).assertFalse();
      if (topAfter !== undefined) {
        expect(topAfter.deleted).assertTrue();
        expect(topAfter.dirty).assertTrue();
      }
      const nestedAfter = await folderDao.findById(nested.id);
      expect(nestedAfter === undefined).assertFalse();
      if (nestedAfter !== undefined) {
        expect(nestedAfter.deleted).assertTrue();
      }
      const inNestedAfter = await dao.findById(inNested.id);
      expect(inNestedAfter === undefined).assertFalse();
      if (inNestedAfter !== undefined) {
        expect(inNestedAfter.deleted).assertTrue();
        expect(inNestedAfter.dirty).assertTrue();
      }
      const inTopAfter = await dao.findById(inTop.id);
      expect(inTopAfter === undefined).assertFalse();
      if (inTopAfter !== undefined) {
        expect(inTopAfter.deleted).assertTrue();
      }
      const looseAfter = await dao.findById(loose.id);
      expect(looseAfter === undefined).assertFalse();
      if (looseAfter !== undefined) {
        expect(looseAfter.deleted).assertTrue();
      }
      const outsideAfter = await dao.findById(outside.id);
      expect(outsideAfter === undefined).assertFalse();
      if (outsideAfter !== undefined) {
        expect(outsideAfter.deleted).assertFalse();
      }
      const tree = await repo.folderTree();
      expect(tree.length).assertEqual(0);
    });

    it('batchDeleteOverlapAndNestedFolderBumpRevOnce', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const top = await repo.createFolder('', '顶层');
      expect(top === undefined).assertFalse();
      if (top === undefined) {
        return;
      }
      const nested = await repo.createFolder(top.id, '嵌套');
      expect(nested === undefined).assertFalse();
      if (nested === undefined) {
        return;
      }
      // Selected both as a loose bookmark and via its folder's subtree.
      const overlap = Bookmark.create('https://example.com/overlap', '重叠书签', BookmarkSource.MANUAL);
      overlap.folderId = nested.id;
      await dao.insert(overlap);
      const overlapBefore = await dao.findById(overlap.id);
      const nestedBefore = await folderDao.findById(nested.id);
      const topBefore = await folderDao.findById(top.id);
      expect(overlapBefore === undefined).assertFalse();
      expect(nestedBefore === undefined).assertFalse();
      expect(topBefore === undefined).assertFalse();
      if (overlapBefore === undefined || nestedBefore === undefined || topBefore === undefined) {
        return;
      }

      // The overlapping book is counted once, with the subtree; both folders
      // are reported (both do end up trashed) and the nested subtree is not
      // double-counted.
      const impact = await repo.batchDeleteImpact([overlap.id], [top.id, nested.id]);
      expect(impact.folders).assertEqual(2);
      expect(impact.subtreeBooks).assertEqual(1);
      expect(impact.looseBooks).assertEqual(0);

      const outcome = await repo.batchDelete([overlap.id], [top.id, nested.id]);
      // One bookmark + the top cascade; nested is already trashed by top.
      expect(outcome.done).assertEqual(2);
      expect(outcome.skipped).assertEqual(1);

      // softDeleteMany handles the book first; the cascade's deleted = 0
      // guard must skip it, so rev moves exactly one step.
      const overlapAfter = await dao.findById(overlap.id);
      expect(overlapAfter === undefined).assertFalse();
      if (overlapAfter !== undefined) {
        expect(overlapAfter.rev).assertEqual(overlapBefore.rev + 1);
        expect(overlapAfter.deleted).assertTrue();
        expect(overlapAfter.dirty).assertTrue();
      }
      // nested is bumped only by top's cascade; its own pass was skipped.
      const nestedAfter = await folderDao.findById(nested.id);
      expect(nestedAfter === undefined).assertFalse();
      if (nestedAfter !== undefined) {
        expect(nestedAfter.rev).assertEqual(nestedBefore.rev + 1);
        expect(nestedAfter.deleted).assertTrue();
      }
      const topAfter = await folderDao.findById(top.id);
      expect(topAfter === undefined).assertFalse();
      if (topAfter !== undefined) {
        expect(topAfter.rev).assertEqual(topBefore.rev + 1);
        expect(topAfter.deleted).assertTrue();
      }
      expect((await repo.folderTree()).length).assertEqual(0);
    });

    it('restoreBookmarkRevivesFolderChain', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const front = await repo.createFolder(dev.id, '前端');
      expect(front === undefined).assertFalse();
      if (front === undefined) {
        return;
      }
      const kept = Bookmark.create('https://example.com/kept', '保留书签', BookmarkSource.MANUAL);
      kept.folderId = front.id;
      await dao.insert(kept);
      const stillTrash = Bookmark.create('https://example.com/stayed', '留在回收站', BookmarkSource.MANUAL);
      stillTrash.folderId = front.id;
      await dao.insert(stillTrash);

      await repo.deleteFolderCascade(dev.id);
      expect((await repo.folderTree()).length).assertEqual(0);

      // The reported bug: restore brought the bookmark back but its folder
      // chain stayed soft-deleted, so the attribution was unreachable.
      await repo.restore(kept.id);

      const keptAfter = await dao.findById(kept.id);
      expect(keptAfter === undefined).assertFalse();
      if (keptAfter !== undefined) {
        expect(keptAfter.deleted).assertFalse();
        expect(keptAfter.folderId).assertEqual(front.id);
      }
      const devAfter = await folderDao.findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.deleted).assertFalse();
        expect(devAfter.dirty).assertTrue();
      }
      const frontAfter = await folderDao.findById(front.id);
      expect(frontAfter === undefined).assertFalse();
      if (frontAfter !== undefined) {
        expect(frontAfter.deleted).assertFalse();
        expect(frontAfter.dirty).assertTrue();
      }
      const stillTrashAfter = await dao.findById(stillTrash.id);
      expect(stillTrashAfter === undefined).assertFalse();
      if (stillTrashAfter !== undefined) {
        expect(stillTrashAfter.deleted).assertTrue();
      }
      const tree = await repo.folderTree();
      expect(tree.length).assertEqual(1);
      if (tree.length === 1) {
        expect(tree[0].folder.id).assertEqual(dev.id);
        expect(tree[0].children.length).assertEqual(1);
        if (tree[0].children.length === 1) {
          expect(tree[0].children[0].folder.id).assertEqual(front.id);
          expect(tree[0].children[0].directCount).assertEqual(1);
        }
      }
    });

    it('restoreManyRevivesSharedAncestorOnce', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const front = await repo.createFolder(dev.id, '前端');
      expect(front === undefined).assertFalse();
      if (front === undefined) {
        return;
      }
      const inDev = Bookmark.create('https://example.com/in-dev', '直属书签', BookmarkSource.MANUAL);
      inDev.folderId = dev.id;
      await dao.insert(inDev);
      const inFront = Bookmark.create('https://example.com/in-front', '嵌套书签', BookmarkSource.MANUAL);
      inFront.folderId = front.id;
      await dao.insert(inFront);

      await repo.deleteFolderCascade(dev.id);
      // rev after create = 1, after cascade delete = 2; a single revive must
      // land at 3 — a second revive of the shared ancestor would bump to 4.
      await repo.restoreMany([inDev.id, inFront.id]);

      const devAfter = await folderDao.findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.rev).assertEqual(3);
        expect(devAfter.deleted).assertFalse();
      }
      const frontAfter = await folderDao.findById(front.id);
      expect(frontAfter === undefined).assertFalse();
      if (frontAfter !== undefined) {
        expect(frontAfter.rev).assertEqual(3);
        expect(frontAfter.deleted).assertFalse();
      }
    });

    it('restoreRenamesWhenSiblingTookTheName', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const member = Bookmark.create('https://example.com/member', '成员书签', BookmarkSource.MANUAL);
      member.folderId = dev.id;
      await dao.insert(member);

      await repo.deleteFolderCascade(dev.id);
      // The partial unique index frees the name while the folder is trashed;
      // a new live sibling may claim it before the restore happens.
      const squatter = await repo.createFolder('', '开发');
      expect(squatter === undefined).assertFalse();

      await repo.restore(member.id);

      const devAfter = await folderDao.findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.deleted).assertFalse();
        expect(devAfter.name).assertEqual('开发 (2)');
      }
      const memberAfter = await dao.findById(member.id);
      expect(memberAfter === undefined).assertFalse();
      if (memberAfter !== undefined) {
        expect(memberAfter.deleted).assertFalse();
        expect(memberAfter.folderId).assertEqual(dev.id);
      }
      const inRevived = await repo.bookmarksInFolder(dev.id);
      expect(inRevived.length).assertEqual(1);
      const tree = await repo.folderTree();
      expect(tree.length).assertEqual(2);
    });

    it('restoreToleratesPurgedFolderRow', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/ghost-owner', '悬空书签', BookmarkSource.MANUAL);
      bookmark.folderId = 'ghost-folder';
      await dao.insert(bookmark);

      await repo.delete(bookmark.id);
      // Folder row gone (purged / never synced in): restore must not throw,
      // the bookmark stays live and keeps the dangling reference (D9).
      await repo.restore(bookmark.id);

      const after = await dao.findById(bookmark.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.deleted).assertFalse();
        expect(after.folderId).assertEqual('ghost-folder');
      }
    });

    it('restoreBookmarkInLiveFolderLeavesFoldersUntouched', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const member = Bookmark.create('https://example.com/plain', '普通书签', BookmarkSource.MANUAL);
      member.folderId = dev.id;
      await dao.insert(member);

      await repo.delete(member.id);
      const revBefore = await folderDao.findById(dev.id);
      expect(revBefore === undefined).assertFalse();
      if (revBefore === undefined) {
        return;
      }
      await repo.restore(member.id);

      const devAfter = await folderDao.findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.rev).assertEqual(revBefore.rev);
        expect(devAfter.deleted).assertFalse();
      }
      const memberAfter = await dao.findById(member.id);
      expect(memberAfter === undefined).assertFalse();
      if (memberAfter !== undefined) {
        expect(memberAfter.deleted).assertFalse();
      }
    });

    it('remoteRestoreRecordRevivesFolderChain', 0, async () => {
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const dev = await repo.createFolder('', '开发');
      expect(dev === undefined).assertFalse();
      if (dev === undefined) {
        return;
      }
      const front = await repo.createFolder(dev.id, '前端');
      expect(front === undefined).assertFalse();
      if (front === undefined) {
        return;
      }
      const member = Bookmark.create('https://example.com/remote-restore', '远端恢复', BookmarkSource.MANUAL);
      member.folderId = front.id;
      await dao.insert(member);

      await repo.deleteFolderCascade(dev.id);

      // Peer restores the member: its newer live record lands after a local
      // cascade delete and must drag the folder chain out of the trash too.
      const record = SyncRecord.fromBookmark(member);
      record.updatedAt = Date.now() + 5000;
      const applied = await repo.upsertFromRemote(record, '"rr1"');
      expect(applied).assertTrue();

      const memberAfter = await dao.findById(member.id);
      expect(memberAfter === undefined).assertFalse();
      if (memberAfter !== undefined) {
        expect(memberAfter.deleted).assertFalse();
        expect(memberAfter.folderId).assertEqual(front.id);
      }
      const devAfter = await folderDao.findById(dev.id);
      expect(devAfter === undefined).assertFalse();
      if (devAfter !== undefined) {
        expect(devAfter.deleted).assertFalse();
      }
      const frontAfter = await folderDao.findById(front.id);
      expect(frontAfter === undefined).assertFalse();
      if (frontAfter !== undefined) {
        expect(frontAfter.deleted).assertFalse();
      }
      const tree = await repo.folderTree();
      expect(tree.length).assertEqual(1);
      if (tree.length === 1) {
        expect(tree[0].children.length).assertEqual(1);
      }
    });

    it('remoteFolderLandingDedupesSameNameSibling', 0, async () => {
      const repo = FlowRepository.get();
      const folderDao = new FolderDao();
      const mine = await repo.createFolder('', '开发');
      expect(mine === undefined).assertFalse();
      if (mine === undefined) {
        return;
      }
      // A peer created its own same-name sibling with a different id; the
      // landing must dedupe instead of tripping the partial unique index
      // (and failing) on every sync run.
      const remote = new FolderSyncRecord();
      remote.id = 'remote-same-name';
      remote.parentId = '';
      remote.name = '开发';
      remote.updatedAt = Date.now();
      const applied = await repo.upsertFolderFromRemote(remote, '"etag1"');
      expect(applied).assertTrue();
      const landed = await folderDao.findById('remote-same-name');
      expect(landed === undefined).assertFalse();
      if (landed !== undefined) {
        expect(landed.name).assertEqual('开发 (2)');
        expect(landed.deleted).assertFalse();
      }
      const mineAfter = await folderDao.findById(mine.id);
      expect(mineAfter === undefined).assertFalse();
      if (mineAfter !== undefined) {
        expect(mineAfter.name).assertEqual('开发');
      }
      // A remote rename onto a live sibling's name dedupes the same way.
      const rename = new FolderSyncRecord();
      rename.id = mine.id;
      rename.parentId = '';
      rename.name = '开发 (2)';
      rename.createdAt = mineAfter !== undefined ? mineAfter.createdAt : 0;
      rename.updatedAt = Date.now() + 1000;
      const appliedRename = await repo.upsertFolderFromRemote(rename, '"etag2"');
      expect(appliedRename).assertTrue();
      const mineRenamed = await folderDao.findById(mine.id);
      expect(mineRenamed === undefined).assertFalse();
      if (mineRenamed !== undefined) {
        expect(mineRenamed.name).assertEqual('开发 (2) (2)');
      }
    });
  });
}
