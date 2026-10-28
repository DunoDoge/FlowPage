import { Folder } from '../model/Folder';

// Pure drop planning: decides which dragged rows may move, which are no-ops
// because they already sit in the target, and which are rejected (folder into
// itself or a descendant, vanished rows, dead target). Kept side-effect free
// so ohosTest can cover the tree rules without a device UI.
export class BookmarkPlacement {
  id: string = '';
  folderId: string = '';

  constructor(id: string, folderId: string) {
    this.id = id;
    this.folderId = folderId;
  }
}

export class FolderDropPlan {
  bookmarkIds: string[] = [];
  folderIds: string[] = [];
  skipped: number = 0;
  noop: boolean = false;
}

export function planFolderDrop(
  bookmarks: BookmarkPlacement[],
  folders: Folder[],
  folderIds: string[],
  targetFolderId: string
): FolderDropPlan {
  const plan = new FolderDropPlan();
  const live = new Map<string, Folder>();
  const childrenOf = new Map<string, string[]>();
  for (let i = 0; i < folders.length; i++) {
    if (folders[i].deleted) {
      continue;
    }
    live.set(folders[i].id, folders[i]);
    const siblings = childrenOf.get(folders[i].parentId);
    if (siblings === undefined) {
      childrenOf.set(folders[i].parentId, [folders[i].id]);
    } else {
      siblings.push(folders[i].id);
    }
  }

  if (targetFolderId.length > 0 && !live.has(targetFolderId)) {
    plan.skipped = bookmarks.length + folderIds.length;
    return plan;
  }

  for (let i = 0; i < bookmarks.length; i++) {
    if (bookmarks[i].folderId === targetFolderId) {
      continue;
    }
    plan.bookmarkIds.push(bookmarks[i].id);
  }

  for (let i = 0; i < folderIds.length; i++) {
    const id = folderIds[i];
    const folder = live.get(id);
    if (folder === undefined) {
      plan.skipped = plan.skipped + 1;
      continue;
    }
    if (folder.parentId === targetFolderId) {
      continue;
    }
    if (isSelfOrDescendant(childrenOf, id, targetFolderId)) {
      plan.skipped = plan.skipped + 1;
      continue;
    }
    plan.folderIds.push(id);
  }

  plan.noop = plan.bookmarkIds.length === 0 && plan.folderIds.length === 0 && plan.skipped === 0;
  return plan;
}

function isSelfOrDescendant(childrenOf: Map<string, string[]>, id: string, targetFolderId: string): boolean {
  if (targetFolderId.length === 0) {
    return false;
  }
  if (id === targetFolderId) {
    return true;
  }
  const seen = new Set<string>([id]);
  const queue: string[] = [id];
  while (queue.length > 0) {
    const current = queue.shift();
    if (current === undefined) {
      continue;
    }
    const children = childrenOf.get(current);
    if (children === undefined) {
      continue;
    }
    for (let i = 0; i < children.length; i++) {
      if (children[i] === targetFolderId) {
        return true;
      }
      if (!seen.has(children[i])) {
        seen.add(children[i]);
        queue.push(children[i]);
      }
    }
  }
  return false;
}
