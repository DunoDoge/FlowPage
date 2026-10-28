import { unifiedDataChannel, uniformTypeDescriptor } from '@kit.ArkData';
import { KeyCode } from '@kit.InputKit';
import { Folder, FolderNode } from '../model/Folder';
import { AppState } from '../common/AppState';
import { FolderDragSession } from '../common/FolderDragSession';
import { BookmarkPlacement, FolderDropPlan, planFolderDrop } from '../common/FolderDropRules';
import { Pane, StreamFilter } from '../common/Constants';
import { FlowRepository } from '../repository/FlowRepository';
import { FolderPicker } from './FolderPicker';

class PanelRow {
  folder: Folder = new Folder();
  depth: number = 0;
  expanded: boolean = false;
  hasChildren: boolean = false;
  totalCount: number = 0;
}

// Home folder tree (D10). Docked mode fills the left rail below the nav items;
// drawer mode (narrow widths) fills the slide-in panel. Both render the same
// tree with inline create/rename, an anchored "…" menu per row, and drop
// targets for long-press drag. Expansion and scroll are parked in AppState so
// a phone detail round-trip does not reset the tree.
@ComponentV2
export struct FolderPanel {
  @Param isWide: boolean = false;
  @Param docked: boolean = true;

  @Local appState: AppState = AppState.shared;
  @Local dragSession: FolderDragSession = FolderDragSession.shared;
  @Local rows: PanelRow[] = [];
  @Local loading: boolean = true;
  @Local menuId: string = '';
  @Local editingId: string = '';
  @Local draftName: string = '';
  @Local createOpen: boolean = false;
  @Local createParentId: string = '';
  @Local createDraft: string = '';
  @Local moveTargetId: string = '';
  @Local moveTargetName: string = '';
  @Local moveTargetParentId: string = '';
  @Local dropTargetId: string = '';
  @Local rootHover: boolean = false;
  private nodes: FolderNode[] = [];
  private liveIds: string[] = [];
  private scroller: Scroller = new Scroller();
  private panelTop: number = 0;
  private panelBottom: number = 0;
  private pendingRefresh: boolean = false;
  private restoredScroll: boolean = false;
  private loadGeneration: number = 0;
  private dropBusy: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    if (this.dragSession.active) {
      this.pendingRefresh = true;
      return;
    }
    this.load();
  }

  // A drop ends the session before batchMove notifies, so normal refreshes
  // flow again; a cancelled drag only flushes a deferred sync refresh.
  @Monitor('dragSession.active')
  onDragActiveChanged(): void {
    if (!this.dragSession.active) {
      this.dropTargetId = '';
      this.rootHover = false;
      if (this.pendingRefresh) {
        this.pendingRefresh = false;
        this.load();
      }
    }
  }

  private async load(): Promise<void> {
    this.loadGeneration = this.loadGeneration + 1;
    const generation = this.loadGeneration;
    this.loading = true;
    let nodes: FolderNode[] = [];
    try {
      nodes = await FlowRepository.get().folderTree();
    } catch (error) {
      nodes = [];
    }
    if (generation !== this.loadGeneration) {
      return;
    }
    this.nodes = nodes;
    this.loading = false;
    const ids: string[] = [];
    this.collectIds(nodes, ids);
    this.liveIds = ids;
    this.pruneExpanded(ids);
    if (this.appState.folderFilter.length > 0 && ids.indexOf(this.appState.folderFilter) < 0) {
      this.appState.folderFilter = '';
      AppState.shared.toast('文件夹已不在，已清除筛选');
    }
    this.appState.pruneFolderSelection(ids);
    this.rebuildRows();
    if (!this.restoredScroll) {
      this.restoredScroll = true;
      const parked = this.appState.folderPanelScrollY;
      if (parked > 0) {
        setTimeout(() => {
          this.scroller.scrollTo({ xOffset: 0, yOffset: parked });
        }, 60);
      }
    }
  }

  private collectIds(nodes: FolderNode[], ids: string[]): void {
    for (let i = 0; i < nodes.length; i++) {
      ids.push(nodes[i].folder.id);
      this.collectIds(nodes[i].children, ids);
    }
  }

  private pruneExpanded(ids: string[]): void {
    const kept: string[] = [];
    for (let i = 0; i < this.appState.folderPanelExpandedIds.length; i++) {
      const id = this.appState.folderPanelExpandedIds[i];
      if (ids.indexOf(id) >= 0) {
        kept.push(id);
      }
    }
    if (kept.length !== this.appState.folderPanelExpandedIds.length) {
      this.appState.folderPanelExpandedIds = kept;
    }
  }

  private rebuildRows(): void {
    const rows: PanelRow[] = [];
    this.appendRows(this.nodes, 0, rows);
    this.rows = rows;
  }

  private appendRows(nodes: FolderNode[], depth: number, rows: PanelRow[]): void {
    for (let i = 0; i < nodes.length; i++) {
      const node = nodes[i];
      const row = new PanelRow();
      row.folder = node.folder;
      row.depth = depth;
      row.hasChildren = node.children.length > 0;
      row.expanded = this.appState.folderPanelExpandedIds.indexOf(node.folder.id) >= 0;
      row.totalCount = node.totalCount;
      rows.push(row);
      if (row.expanded) {
        this.appendRows(node.children, depth + 1, rows);
      }
    }
  }

  private findNode(nodes: FolderNode[], id: string): FolderNode | undefined {
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].folder.id === id) {
        return nodes[i];
      }
      const hit = this.findNode(nodes[i].children, id);
      if (hit !== undefined) {
        return hit;
      }
    }
    return undefined;
  }

  private rowById(id: string): PanelRow | undefined {
    for (let i = 0; i < this.rows.length; i++) {
      if (this.rows[i].folder.id === id) {
        return this.rows[i];
      }
    }
    return undefined;
  }

  private collectPathTo(nodes: FolderNode[], targetId: string, path: string[]): boolean {
    for (let i = 0; i < nodes.length; i++) {
      path.push(nodes[i].folder.id);
      if (nodes[i].folder.id === targetId) {
        return true;
      }
      if (this.collectPathTo(nodes[i].children, targetId, path)) {
        return true;
      }
      path.pop();
    }
    return false;
  }

  private expandWithAncestors(targetId: string): void {
    if (targetId.length === 0) {
      return;
    }
    const path: string[] = [];
    if (!this.collectPathTo(this.nodes, targetId, path)) {
      return;
    }
    const merged = this.appState.folderPanelExpandedIds.slice(0);
    for (let i = 0; i < path.length; i++) {
      if (merged.indexOf(path[i]) < 0) {
        merged.push(path[i]);
      }
    }
    this.appState.folderPanelExpandedIds = merged;
  }

  private toggleExpand(row: PanelRow): void {
    const ids = this.appState.folderPanelExpandedIds.slice(0);
    if (row.expanded) {
      const node = this.findNode(this.nodes, row.folder.id);
      const subtree = node !== undefined ? node.subtreeIds() : [row.folder.id];
      this.appState.folderPanelExpandedIds =
        ids.filter((one: string): boolean => subtree.indexOf(one) < 0);
    } else {
      this.appState.folderPanelExpandedIds = ids.concat([row.folder.id]);
    }
    this.rebuildRows();
  }

  // Unified row semantics (14.9, direct filter per section 15): any folder row
  // click filters the stream to that folder's direct bookmarks only;
  // subfolder content is reached by drilling into the child folder rows.
  // Parent rows also toggle expansion. Re-clicking a row never toggles the
  // filter off (clear via the root row or the stream filter chip), and
  // collapsing keeps the filter. Narrow screens keep the drawer open on
  // parent rows so drilling stays possible; leaf and root rows close it.
  private activateRow(row: PanelRow): void {
    if (this.editingId === row.folder.id) {
      return;
    }
    this.applyFilter(row.folder.id, !row.hasChildren);
    if (row.hasChildren) {
      this.toggleExpand(row);
    }
  }

  private rowLabel(row: PanelRow): string {
    if (row.hasChildren) {
      return row.expanded ? `收起${row.folder.name}` : `展开并筛选${row.folder.name}`;
    }
    return `筛选文件夹${row.folder.name}`;
  }

  private applyFilter(id: string, closeDrawer: boolean): void {
    this.appState.folderFilter = id;
    if (this.appState.pane !== Pane.DETAIL) {
      this.appState.goPane(Pane.DETAIL);
    }
    if (closeDrawer && !this.docked) {
      this.appState.folderDrawerOpen = false;
    }
  }

  private clearFilter(): void {
    this.applyFilter('', true);
  }

  private openMenu(id: string): void {
    this.menuId = id;
  }

  private closeMenu(): void {
    this.menuId = '';
  }

  private startRename(row: PanelRow): void {
    this.closeMenu();
    this.editingId = row.folder.id;
    this.draftName = row.folder.name;
  }

  private async submitRename(): Promise<void> {
    const name = this.draftName.trim();
    if (name.length === 0) {
      AppState.shared.toast('文件夹名不能为空');
      return;
    }
    try {
      const renamed = await FlowRepository.get().renameFolder(this.editingId, name);
      if (!renamed) {
        AppState.shared.toast('同级已有同名文件夹');
        return;
      }
      this.editingId = '';
      AppState.shared.toast('改好了');
    } catch (error) {
      AppState.shared.toast('改名失败，请稍后再试');
    }
  }

  private startCreate(parentId: string): void {
    this.closeMenu();
    this.createParentId = parentId;
    this.createDraft = '';
    this.createOpen = true;
    if (parentId.length > 0) {
      this.expandWithAncestors(parentId);
    }
    this.rebuildRows();
  }

  private async submitCreate(): Promise<void> {
    const name = this.createDraft.trim();
    if (name.length === 0) {
      AppState.shared.toast('文件夹名不能为空');
      return;
    }
    const parentId = this.createParentId;
    try {
      const created = await FlowRepository.get().createFolder(parentId, name);
      if (created === undefined) {
        AppState.shared.toast('同级已有同名文件夹');
        return;
      }
      this.createOpen = false;
      this.createParentId = '';
      this.createDraft = '';
      if (parentId.length > 0) {
        this.expandWithAncestors(parentId);
        const ids = this.appState.folderPanelExpandedIds.slice(0);
        if (ids.indexOf(parentId) < 0) {
          this.appState.folderPanelExpandedIds = ids.concat([parentId]);
        }
      }
      this.rebuildRows();
    } catch (error) {
      AppState.shared.toast('新建失败，请稍后再试');
    }
  }

  private startMove(row: PanelRow): void {
    this.closeMenu();
    this.moveTargetId = row.folder.id;
    this.moveTargetName = row.folder.name;
    this.moveTargetParentId = row.folder.parentId;
  }

  private resetMove(): void {
    this.moveTargetId = '';
    this.moveTargetName = '';
    this.moveTargetParentId = '';
  }

  private async pickMove(parentId: string, label: string): Promise<void> {
    const id = this.moveTargetId;
    if (id.length === 0) {
      return;
    }
    if (parentId === this.moveTargetParentId) {
      this.resetMove();
      AppState.shared.toast('已经在这个位置');
      return;
    }
    try {
      const moved = await FlowRepository.get().moveFolder(id, parentId);
      if (!moved) {
        AppState.shared.toast('不能移到自己里面');
        return;
      }
      AppState.shared.toast(`已移到${label.length > 0 ? label : '根目录'}`);
      this.resetMove();
      this.expandWithAncestors(parentId);
      const ids = this.appState.folderPanelExpandedIds.slice(0);
      if (parentId.length > 0 && ids.indexOf(parentId) < 0) {
        this.appState.folderPanelExpandedIds = ids.concat([parentId]);
      }
      this.rebuildRows();
    } catch (error) {
      AppState.shared.toast('移动失败，请稍后再试');
    }
  }

  private askDelete(row: PanelRow): void {
    this.closeMenu();
    const id = row.folder.id;
    const name = row.folder.name;
    FlowRepository.get().countFolderBookmarks(id).then((count: number): void => {
      AlertDialog.show({
        title: `删除「${name}」？`,
        message: `会连同子文件夹与其中 ${count} 条笺一起移入回收站，可在回收站恢复。`,
        primaryButton: {
          value: '取消',
          action: () => {}
        },
        secondaryButton: {
          value: '删除',
          fontColor: $r('app.color.danger'),
          action: (): void => {
            this.runDelete(id);
          }
        }
      });
    }).catch((): void => {
      AppState.shared.toast('删除失败，请稍后再试');
    });
  }

  private async runDelete(id: string): Promise<void> {
    try {
      await FlowRepository.get().deleteFolderCascade(id);
      AppState.shared.toast('已移入回收站');
    } catch (error) {
      AppState.shared.toast('删除失败，请稍后再试');
    }
  }

  private viewInStream(id: string): void {
    this.closeMenu();
    this.applyFilter(id, true);
  }

  private isFolderSelected(id: string): boolean {
    return this.appState.isFolderSelected(id);
  }

  private beginDrag(id: string): void {
    const inGroup = this.appState.isFolderSelected(id);
    if (inGroup) {
      this.dragSession.begin(this.appState.selectedBookmarkIds.slice(0),
        this.appState.selectedFolderIds.slice(0), id);
    } else {
      this.dragSession.begin([], [id], id);
    }
    this.menuId = '';
  }

  private fillDragPayload(event: DragEvent): void {
    const data = new unifiedDataChannel.PlainText();
    data.textContent = FolderDragSession.PAYLOAD;
    event.setData(new unifiedDataChannel.UnifiedData(data));
  }

  private makeDragPreview(): DragItemInfo {
    const info: DragItemInfo = { extraInfo: FolderDragSession.PAYLOAD };
    return info;
  }

  private dropOn(targetFolderId: string, event: DragEvent): void {
    this.dropTargetId = '';
    this.rootHover = false;
    if (this.dragSession.active) {
      this.commitDrop(targetFolderId);
      event.setResult(DragResult.DRAG_SUCCESSFUL);
    } else {
      event.setResult(DragResult.DRAG_FAILED);
    }
  }

  // The tree is the only drop target now, so the commit lives here instead of
  // round-tripping through StreamHome. A valid drop still refreshes once.
  private async commitDrop(targetFolderId: string): Promise<void> {
    if (this.dropBusy) {
      return;
    }
    const bookmarkIds = this.dragSession.bookmarkIds.slice(0);
    const folderIds = this.dragSession.folderIds.slice(0);
    this.dragSession.end();
    if (bookmarkIds.length + folderIds.length === 0) {
      return;
    }
    this.dropBusy = true;
    try {
      const folders = await FlowRepository.get().listAllFolders();
      const placements: BookmarkPlacement[] = [];
      let vanished = 0;
      for (let i = 0; i < bookmarkIds.length; i++) {
        const bookmark = await FlowRepository.get().get(bookmarkIds[i]);
        if (bookmark === undefined || bookmark.deleted) {
          vanished = vanished + 1;
          continue;
        }
        placements.push(new BookmarkPlacement(bookmark.id, bookmark.folderId));
      }
      const plan: FolderDropPlan = planFolderDrop(placements, folders, folderIds, targetFolderId);
      const skipped = plan.skipped + vanished;
      if (plan.noop) {
        AppState.shared.toast('位置没有变化');
        return;
      }
      if (plan.bookmarkIds.length + plan.folderIds.length === 0) {
        AppState.shared.toast(`无法移动，跳过 ${skipped} 项`);
        return;
      }
      const outcome = await FlowRepository.get().batchMove(plan.bookmarkIds, plan.folderIds, targetFolderId);
      const totalSkipped = skipped + outcome.skipped;
      const suffix = totalSkipped > 0 ? `，跳过 ${totalSkipped} 项` : '';
      AppState.shared.toast(`已移动 ${outcome.done} 项${suffix}`);
      this.appState.clearRowSelection();
    } catch (error) {
      AppState.shared.toast('移动失败，请稍后再试');
    } finally {
      this.dropBusy = false;
    }
  }

  private maybeAutoScroll(windowY: number): void {
    if (this.panelBottom <= this.panelTop) {
      return;
    }
    if (windowY < this.panelTop + 48) {
      this.scroller.scrollBy(0, -18);
    } else if (windowY > this.panelBottom - 48) {
      this.scroller.scrollBy(0, 18);
    }
  }

  build() {
    Column() {
      Row() {
        Text('文件夹')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        if (this.appState.folderFilter.length > 0) {
          Text('· 已筛选')
            .fontSize(11)
            .fontColor($r('app.color.ink_secondary'))
            .margin({ left: 6 })
        }
        Blank()
        if (!this.docked) {
          Text('×')
            .fontSize(18)
            .fontColor($r('app.color.ink_secondary'))
            .width(44)
            .height(40)
            .textAlign(TextAlign.Center)
            .accessibilityText('关闭文件夹抽屉')
            .focusable(true)
            .onClick(() => {
              this.closeMenu();
              this.appState.folderDrawerOpen = false;
            })
        }
      }
      .width('100%')
      .height(40)
      .padding({ left: this.docked ? 10 : 8, right: 4 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))

      if (this.moveTargetId.length > 0) {
        this.MoveView()
      } else if (this.loading) {
        Text('正在整理…')
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
          .padding({ left: 20, top: 12 })
      } else {
        Scroll(this.scroller) {
          Column() {
            this.AllRow()
            if (this.dragSession.active) {
              this.RootDropRow()
            }
            ForEach(this.rows, (row: PanelRow) => {
              this.FolderRowView(row)
              if (this.createOpen && this.createParentId === row.folder.id) {
                this.CreateEditor(row.depth + 1)
              }
            }, (row: PanelRow) =>
              `${row.folder.id}|${row.folder.name}|${row.totalCount}|${row.depth}|${row.expanded}`)
            this.RootCreateRow()
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
          .padding({ bottom: 10 })
        }
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
        .align(Alignment.TopStart)
        .layoutWeight(1)
        .width('100%')
        .onDidScroll(() => {
          this.appState.folderPanelScrollY = this.scroller.currentOffset().yOffset;
        })
      }
    }
    .width('100%')
    .height('100%')
    .padding({ left: 12, right: 12 })
    .backgroundColor($r('app.color.paper'))
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const top = newArea.globalPosition.y;
      const height = newArea.height;
      if (typeof top === 'number' && typeof height === 'number') {
        this.panelTop = top;
        this.panelBottom = top + height;
      }
    })
  }

  @Builder
  AllRow() {
    Row() {
      Text('全部')
        .fontSize(14)
        .fontWeight(this.appState.folderFilter.length === 0 ? FontWeight.Medium : FontWeight.Normal)
        .fontColor($r('app.color.ink'))
        .layoutWeight(1)
      if (this.appState.folderFilter.length === 0) {
        Text('当前')
          .fontSize(11)
          .fontColor($r('app.color.ink_secondary'))
      }
    }
    .width('100%')
    .height(38)
    .padding({ left: 12, right: 12 })
    .borderRadius(6)
    .backgroundColor(this.appState.folderFilter.length === 0 ? $r('app.color.row_selected') : Color.Transparent)
    .accessibilityText('查看全部书签')
    .focusable(true)
    .onClick(() => this.clearFilter())
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down &&
        (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
        this.clearFilter();
      }
    })
  }

  @Builder
  RootDropRow() {
    Row() {
      Text('放到这里：根目录')
        .fontSize(12)
        .fontColor($r('app.color.ink_secondary'))
        .layoutWeight(1)
    }
    .width('100%')
    .height(38)
    .padding({ left: 12, right: 12 })
    .borderRadius(6)
    .border({ width: 1, color: $r('app.color.line_strong') })
    .backgroundColor(this.rootHover ? $r('app.color.row_drop') : $r('app.color.surface_alt'))
    .allowDrop([uniformTypeDescriptor.UniformDataType.PLAIN_TEXT])
    .onDragEnter(() => {
      this.rootHover = true;
    })
    .onDragLeave(() => {
      this.rootHover = false;
    })
    .onDragMove((event: DragEvent) => {
      this.maybeAutoScroll(event.getWindowY());
    })
    .onDrop((event: DragEvent) => {
      this.dropOn('', event);
    })
  }

  @Builder
  FolderRowView(row: PanelRow) {
    Column() {
      Row() {
        if (this.appState.selectionMode && this.appState.homeFilter !== StreamFilter.TRASH) {
          Text(this.isFolderSelected(row.folder.id) ? '✓' : '')
            .fontSize(12)
            .fontWeight(FontWeight.Bold)
            .fontColor(this.isFolderSelected(row.folder.id) ? $r('app.color.inverse_ink') : $r('app.color.ink_tertiary'))
            .width(20)
            .height(20)
            .textAlign(TextAlign.Center)
            .border({ width: 1, color: this.isFolderSelected(row.folder.id) ? $r('app.color.ink') : $r('app.color.line_strong') })
            .borderRadius(4)
            .margin({ right: 6 })
            .accessibilityText(this.isFolderSelected(row.folder.id) ? `取消选择文件夹${row.folder.name}` : `选择文件夹${row.folder.name}`)
            .focusable(true)
            .onClick(() => this.appState.toggleFolderSelected(row.folder.id))
        }

        Row() {
          if (this.editingId === row.folder.id) {
            TextInput({ text: this.draftName })
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.surface'))
              .borderRadius(6)
              .height(32)
              .layoutWeight(1)
              .onChange((value: string) => {
                this.draftName = value;
              })
            Text('存')
              .fontSize(12)
              .fontColor($r('app.color.inverse_ink'))
              .backgroundColor($r('app.color.ink'))
              .borderRadius(6)
              .height(32)
              .padding({ left: 8, right: 8 })
              .textAlign(TextAlign.Center)
              .accessibilityText('保存文件夹名')
              .onClick(() => {
                this.submitRename();
              })
            Text('取消')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .height(32)
              .padding({ left: 8, right: 8 })
              .accessibilityText('取消改名')
              .onClick(() => {
                this.editingId = '';
              })
          } else {
            Text(row.folder.name)
              .fontSize(14)
              .fontWeight(this.appState.folderFilter === row.folder.id ? FontWeight.Medium : FontWeight.Normal)
              .fontColor($r('app.color.ink'))
              .maxLines(1)
              .textOverflow({ overflow: TextOverflow.Ellipsis })
              .layoutWeight(1)
            Text(`${row.totalCount}`)
              .fontSize(11)
              .fontColor($r('app.color.ink_tertiary'))
              .margin({ left: 6, right: 2 })
          }
        }
        .layoutWeight(1)
        .padding({ left: row.depth * 14 })
        .accessibilityText(this.rowLabel(row))
        .focusable(true)
        .onClick(() => this.activateRow(row))
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
            this.activateRow(row);
          }
        })

        Text('…')
          .fontSize(16)
          .fontColor($r('app.color.ink_secondary'))
          .width(36)
          .height(36)
          .textAlign(TextAlign.Center)
          .accessibilityText(`文件夹操作${row.folder.name}`)
          .focusable(true)
          .onClick(() => this.openMenu(row.folder.id))
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              this.openMenu(row.folder.id);
            }
          })
          .bindPopup(this.menuId === row.folder.id, {
            builder: this.FolderMenu,
            placement: Placement.Bottom,
            popupColor: $r('app.color.surface'),
            enableArrow: true,
            autoCancel: true,
            radius: 12,
            targetSpace: 8,
            onStateChange: (event: PopupStateChangeParam) => {
              if (!event.isVisible && this.menuId === row.folder.id) {
                this.menuId = '';
              }
            }
          })
      }
      .width('100%')
      .height(42)
      .padding({ left: 8, right: 4 })
      .borderRadius(6)
      .backgroundColor(this.dropTargetId === row.folder.id
        ? $r('app.color.row_drop')
        : (this.appState.folderFilter === row.folder.id ? $r('app.color.row_selected') : Color.Transparent))
      .allowDrop([uniformTypeDescriptor.UniformDataType.PLAIN_TEXT])
      .draggable(true)
      .onDragStart((event: DragEvent): DragItemInfo => {
        this.beginDrag(row.folder.id);
        this.fillDragPayload(event);
        return this.makeDragPreview();
      })
      .onDragEnd(() => {
        this.dragSession.end();
      })
      .onDragEnter(() => {
        this.dropTargetId = row.folder.id;
      })
      .onDragLeave(() => {
        if (this.dropTargetId === row.folder.id) {
          this.dropTargetId = '';
        }
      })
      .onDragMove((event: DragEvent) => {
        this.maybeAutoScroll(event.getWindowY());
      })
      .onDrop((event: DragEvent) => {
        this.dropOn(row.folder.id, event);
      })
      .onMouse((event: MouseEvent) => {
        if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
          this.openMenu(row.folder.id);
        }
      })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  RootCreateRow() {
    if (this.createOpen && this.createParentId.length === 0) {
      this.CreateEditor(0)
    } else {
      Text('+ 新建文件夹')
        .fontSize(12)
        .fontColor($r('app.color.ink_secondary'))
        .width('100%')
        .height(36)
        .padding({ left: 12, right: 12 })
        .textAlign(TextAlign.Start)
        .accessibilityText('新建根文件夹')
        .focusable(true)
        .onClick(() => this.startCreate(''))
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
            this.startCreate('');
          }
        })
    }
  }

  @Builder
  CreateEditor(depth: number) {
    Row({ space: 6 }) {
      TextInput({ text: this.createDraft, placeholder: '文件夹名' })
        .fontSize(13)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_tertiary'))
        .backgroundColor($r('app.color.surface'))
        .borderRadius(6)
        .height(34)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.createDraft = value;
        })
      Text('建')
        .fontSize(12)
        .fontColor($r('app.color.inverse_ink'))
        .backgroundColor($r('app.color.ink'))
        .borderRadius(6)
        .height(34)
        .padding({ left: 10, right: 10 })
        .textAlign(TextAlign.Center)
        .accessibilityText('新建文件夹')
        .focusable(true)
        .onClick(() => {
          this.submitCreate();
        })
      Text('取消')
        .fontSize(12)
        .fontColor($r('app.color.ink_secondary'))
        .height(34)
        .padding({ left: 8, right: 8 })
        .accessibilityText('取消新建文件夹')
        .onClick(() => {
          this.createOpen = false;
          this.createParentId = '';
        })
    }
    .width('100%')
    .padding({ left: 8 + depth * 14, right: 8, top: 4, bottom: 4 })
  }

  @Builder
  MoveView() {
    Column({ space: 8 }) {
      Row() {
        Text(`移动「${this.moveTargetName}」到…`)
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .layoutWeight(1)
        Text('取消')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(32)
          .padding({ left: 8, right: 8 })
          .accessibilityText('取消移动')
          .onClick(() => this.resetMove())
      }
      .width('100%')

      FolderPicker({
        selectedId: this.moveTargetParentId,
        rootLabel: '根目录',
        excludeSubtreeOf: this.moveTargetId,
        pickerHeight: this.isWide ? 220 : 180,
        onPick: (folderId: string, label: string): void => {
          this.pickMove(folderId, label);
        }
      })
        .width('100%')
    }
    .width('100%')
    .padding({ left: 14, right: 14, top: 8 })
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  MenuAction(label: string, danger: boolean, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(danger ? $r('app.color.danger') : $r('app.color.ink'))
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(6)
      .height(40)
      .padding({ left: 14, right: 14 })
      .textAlign(TextAlign.Center)
      .margin({ right: 8, top: 4 })
      .accessibilityText(label)
      .focusable(true)
      .onClick(action)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Down &&
          (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
          action();
        }
      })
  }

  @Builder
  FolderMenu() {
    Flex({ wrap: FlexWrap.Wrap }) {
      this.MenuAction('新建子文件夹', false, () => {
        this.startCreate(this.menuId);
      })
      this.MenuAction('改名', false, () => {
        const row = this.rowById(this.menuId);
        if (row !== undefined) {
          this.startRename(row);
        }
      })
      this.MenuAction('移动', false, () => {
        const row = this.rowById(this.menuId);
        if (row !== undefined) {
          this.startMove(row);
        }
      })
      this.MenuAction('在流中查看', false, () => {
        this.viewInStream(this.menuId);
      })
      this.MenuAction('删除', true, () => {
        const row = this.rowById(this.menuId);
        if (row !== undefined) {
          this.askDelete(row);
        }
      })
    }
    .width(220)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
  }
}
