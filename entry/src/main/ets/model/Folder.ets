@ObservedV2
export class Folder {
  @Trace id: string = '';
  @Trace parentId: string = '';
  @Trace name: string = '';
  @Trace position: number = 0;
  // Browser semantic marker captured at import ('' | 'toolbar' | 'unfiled');
  // re-emitted on HTML export so marker-honoring browsers do not nest their
  // own bookmarks bar around ours (D13).
  @Trace kind: string = '';
  @Trace createdAt: number = 0;
  @Trace updatedAt: number = 0;
  @Trace rev: number = 1;
  @Trace dirty: boolean = true;
  @Trace remoteEtag: string = '';
  @Trace deleted: boolean = false;
}

export class FolderNode {
  folder: Folder = new Folder();
  children: FolderNode[] = [];
  directCount: number = 0;
  totalCount: number = 0;
  path: string = '';

  subtreeIds(): string[] {
    const ids: string[] = [this.folder.id];
    for (let i = 0; i < this.children.length; i++) {
      const nested = this.children[i].subtreeIds();
      for (let j = 0; j < nested.length; j++) {
        ids.push(nested[j]);
      }
    }
    return ids;
  }
}
