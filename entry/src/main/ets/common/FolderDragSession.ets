// In-app drag payload carrier: the system UDMF data only proves "this app's
// folder drag", while the actual mixed selection lives here. A single active
// session is enough because only one drag can be in flight at a time.
@ObservedV2
export class FolderDragSession {
  static readonly PAYLOAD: string = 'flowpage/folder-drag';
  private static instance: FolderDragSession | undefined = undefined;

  static get shared(): FolderDragSession {
    if (FolderDragSession.instance === undefined) {
      FolderDragSession.instance = new FolderDragSession();
    }
    return FolderDragSession.instance;
  }

  @Trace active: boolean = false;
  @Trace bookmarkIds: string[] = [];
  @Trace folderIds: string[] = [];
  originRowId: string = '';

  begin(bookmarkIds: string[], folderIds: string[], originRowId: string): void {
    this.bookmarkIds = bookmarkIds;
    this.folderIds = folderIds;
    this.originRowId = originRowId;
    this.active = bookmarkIds.length + folderIds.length > 0;
  }

  end(): void {
    this.active = false;
    this.bookmarkIds = [];
    this.folderIds = [];
    this.originRowId = '';
  }

  count(): number {
    return this.bookmarkIds.length + this.folderIds.length;
  }
}
