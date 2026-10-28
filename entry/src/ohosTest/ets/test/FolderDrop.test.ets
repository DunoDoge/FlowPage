import { describe, it, expect } from '@ohos/hypium';
import { Folder } from '../../../main/ets/model/Folder';
import { BookmarkPlacement, planFolderDrop } from '../../../main/ets/common/FolderDropRules';

function makeFolder(id: string, parentId: string, name: string): Folder {
  const folder = new Folder();
  folder.id = id;
  folder.parentId = parentId;
  folder.name = name;
  return folder;
}

export default function folderDropTest() {
  describe('FolderDropTest', () => {
    it('dropsFolderIntoItselfIsSkipped', 0, () => {
      const folders: Folder[] = [makeFolder('a', '', 'A')];
      const plan = planFolderDrop([], folders, ['a'], 'a');
      expect(plan.folderIds.length).assertEqual(0);
      expect(plan.skipped).assertEqual(1);
      expect(plan.noop).assertFalse();
    });

    it('dropsFolderIntoDescendantIsSkipped', 0, () => {
      const folders: Folder[] = [
        makeFolder('a', '', 'A'),
        makeFolder('b', 'a', 'B'),
        makeFolder('c', 'b', 'C')
      ];
      const plan = planFolderDrop([], folders, ['a'], 'c');
      expect(plan.folderIds.length).assertEqual(0);
      expect(plan.skipped).assertEqual(1);
    });

    it('dropsFolderIntoSameParentIsNoop', 0, () => {
      const folders: Folder[] = [
        makeFolder('a', '', 'A'),
        makeFolder('b', '', 'B')
      ];
      const plan = planFolderDrop([], folders, ['b'], '');
      expect(plan.folderIds.length).assertEqual(0);
      expect(plan.skipped).assertEqual(0);
      expect(plan.noop).assertTrue();
    });

    it('mixedSelectionMovesBothTypesAndSkipsNoop', 0, () => {
      const folders: Folder[] = [
        makeFolder('a', '', 'A'),
        makeFolder('b', '', 'B'),
        makeFolder('c', 'b', 'C')
      ];
      const bookmarks: BookmarkPlacement[] = [
        new BookmarkPlacement('p', 'b'),
        new BookmarkPlacement('q', 'a')
      ];
      const plan = planFolderDrop(bookmarks, folders, ['c'], 'a');
      expect(plan.bookmarkIds.length).assertEqual(1);
      expect(plan.bookmarkIds[0]).assertEqual('p');
      expect(plan.folderIds.length).assertEqual(1);
      expect(plan.folderIds[0]).assertEqual('c');
      expect(plan.skipped).assertEqual(0);
      expect(plan.noop).assertFalse();
    });

    it('allSkippedPlanHasNoMoves', 0, () => {
      const folders: Folder[] = [makeFolder('a', '', 'A')];
      const plan = planFolderDrop(
        [new BookmarkPlacement('p', 'a')],
        folders,
        ['a'],
        'missing'
      );
      expect(plan.bookmarkIds.length).assertEqual(0);
      expect(plan.folderIds.length).assertEqual(0);
      expect(plan.skipped).assertEqual(2);
      expect(plan.noop).assertFalse();
    });

    it('bookmarkAlreadyInTargetIsNoop', 0, () => {
      const folders: Folder[] = [makeFolder('a', '', 'A')];
      const plan = planFolderDrop(
        [new BookmarkPlacement('p', 'a')],
        folders,
        [],
        'a'
      );
      expect(plan.bookmarkIds.length).assertEqual(0);
      expect(plan.skipped).assertEqual(0);
      expect(plan.noop).assertTrue();
    });
  });
}
