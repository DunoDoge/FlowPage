import { FolderNode } from '../model/Folder';
import { AppState } from '../common/AppState';
import { FlowRepository } from '../repository/FlowRepository';
import { KeyCode } from '@kit.InputKit';

class PickerColumn {
  parentId: string = '';
  title: string = '';
  nodes: FolderNode[] = [];

  static of(parentId: string, title: string, nodes: FolderNode[]): PickerColumn {
    const column = new PickerColumn();
    column.parentId = parentId;
    column.title = title;
    column.nodes = nodes;
    return column;
  }
}

// Miller-style folder selector: one column per level, click drills right.
// Shared by the bookmark editor and the folder move target picker.
@ComponentV2
export struct FolderPicker {
  @Param selectedId: string = '';
  @Param rootLabel: string = '根目录';
  // When set (move mode), this folder and its descendants are rejected.
  @Param excludeSubtreeOf: string = '';
  // Batch move: every selected folder and its descendants are rejected.
  @Param excludeSubtreeOfIds: string[] = [];
  @Param showCreate: boolean = true;
  @Param pickerHeight: number = 300;
  @Event onPick: (folderId: string, label: string) => void = () => {};

  @Local appState: AppState = AppState.shared;
  @Local columns: PickerColumn[] = [];
  @Local loading: boolean = true;
  @Local createParentId: string = '';
  @Local createDraft: string = '';
  private nodes: FolderNode[] = [];
  private chain: string[] = [];
  private createPrefix: string[] = [];
  private scroller: Scroller = new Scroller();

  aboutToAppear(): void {
    this.load(true);
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    this.load(false);
  }

  @Monitor('selectedId')
  onSelectedChanged(): void {
    this.initChain();
    this.rebuild();
    this.scrollToEnd();
  }

  private async load(init: boolean): Promise<void> {
    try {
      this.nodes = await FlowRepository.get().folderTree();
    } catch (error) {
      this.nodes = [];
    } finally {
      this.loading = false;
      if (init) {
        this.initChain();
      }
      this.pruneChain();
      this.rebuild();
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

  private collectAncestors(nodes: FolderNode[], id: string, trail: string[]): boolean {
    for (let i = 0; i < nodes.length; i++) {
      if (nodes[i].folder.id === id) {
        return true;
      }
      trail.push(nodes[i].folder.id);
      if (this.collectAncestors(nodes[i].children, id, trail)) {
        return true;
      }
      trail.pop();
    }
    return false;
  }

  private initChain(): void {
    this.chain = [];
    if (this.selectedId.length === 0) {
      return;
    }
    const trail: string[] = [];
    if (this.collectAncestors(this.nodes, this.selectedId, trail)) {
      trail.push(this.selectedId);
      this.chain = trail;
    }
  }

  private pruneChain(): void {
    while (this.chain.length > 0 && this.findNode(this.nodes, this.chain[this.chain.length - 1]) === undefined) {
      this.chain.pop();
    }
  }

  private isDisabled(id: string): boolean {
    if (this.excludeSubtreeOf.length > 0 && this.isInSubtree(this.excludeSubtreeOf, id)) {
      return true;
    }
    for (let i = 0; i < this.excludeSubtreeOfIds.length; i++) {
      if (this.isInSubtree(this.excludeSubtreeOfIds[i], id)) {
        return true;
      }
    }
    return false;
  }

  private isInSubtree(rootId: string, id: string): boolean {
    const root = this.findNode(this.nodes, rootId);
    if (root === undefined) {
      return false;
    }
    const ids = root.subtreeIds();
    for (let i = 0; i < ids.length; i++) {
      if (ids[i] === id) {
        return true;
      }
    }
    return false;
  }

  private pathOf(id: string): string {
    const node = this.findNode(this.nodes, id);
    return node !== undefined ? node.path : '';
  }

  private rebuild(): void {
    const columns: PickerColumn[] = [PickerColumn.of('', this.rootLabel, this.nodes)];
    for (let i = 0; i < this.chain.length; i++) {
      const node = this.findNode(this.nodes, this.chain[i]);
      if (node === undefined) {
        break;
      }
      columns.push(PickerColumn.of(node.folder.id, node.folder.name, node.children));
    }
    this.columns = columns;
  }

  private scrollToEnd(): void {
    setTimeout(() => {
      this.scroller.scrollEdge(Edge.End);
    }, 60);
  }

  private pick(node: FolderNode, index: number): void {
    if (this.isDisabled(node.folder.id)) {
      AppState.shared.toast('不能选这个位置');
      return;
    }
    this.onPick(node.folder.id, node.path);
    this.chain = this.chain.slice(0, index).concat([node.folder.id]);
    this.rebuild();
    this.scrollToEnd();
  }

  private pickRoot(): void {
    this.onPick('', this.rootLabel);
    this.chain = [];
    this.rebuild();
  }

  private startCreate(column: PickerColumn, index: number): void {
    this.createParentId = column.parentId;
    this.createPrefix = this.chain.slice(0, index);
    this.createDraft = '';
  }

  private async submitCreate(): Promise<void> {
    const name = this.createDraft.trim();
    if (name.length === 0) {
      AppState.shared.toast('文件夹名不能为空');
      return;
    }
    try {
      const created = await FlowRepository.get().createFolder(this.createParentId, name);
      if (created === undefined) {
        AppState.shared.toast('同级已有同名文件夹');
        return;
      }
      this.createParentId = '';
      this.nodes = await FlowRepository.get().folderTree();
      this.chain = this.createPrefix.concat([created.id]);
      this.pruneChain();
      this.rebuild();
      this.onPick(created.id, this.pathOf(created.id));
      this.scrollToEnd();
    } catch (error) {
      AppState.shared.toast('新建失败，请稍后再试');
    }
  }

  build() {
    Column() {
      if (this.loading) {
        Text('正在整理…')
          .fontSize(13)
          .fontColor($r('app.color.ink_tertiary'))
          .padding({ left: 12, top: 12 })
          .alignSelf(ItemAlign.Start)
      } else {
        Scroll(this.scroller) {
          Row() {
            ForEach(this.columns, (column: PickerColumn, index: number) => {
              this.ColumnView(column, index)
            }, (column: PickerColumn, index: number) => `${index}-${column.parentId}`)
          }
          .alignItems(VerticalAlign.Top)
        }
        .scrollable(ScrollDirection.Horizontal)
        .scrollBar(BarState.Auto)
        .edgeEffect(EdgeEffect.None)
        .width('100%')
        .layoutWeight(1)
      }
    }
    .width('100%')
    .height(this.pickerHeight)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(8)
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  ColumnView(column: PickerColumn, index: number) {
    Column() {
      if (index === 0) {
        Text(this.rootLabel)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor(this.selectedId.length === 0 ? $r('app.color.ink') : $r('app.color.ink_secondary'))
          .backgroundColor(this.selectedId.length === 0 ? $r('app.color.surface') : Color.Transparent)
          .width('100%')
          .height(36)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .accessibilityText(this.rootLabel)
          .focusable(true)
          .onClick(() => this.pickRoot())
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              this.pickRoot();
            }
          })
      } else {
        Text(column.title)
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .width('100%')
          .height(36)
          .textAlign(TextAlign.Center)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
      }
      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))

      Scroll() {
        Column() {
          ForEach(column.nodes, (node: FolderNode) => {
            this.RowView(node, index)
          }, (node: FolderNode) => node.folder.id)
          if (this.showCreate) {
            this.CreateRow(column, index)
          }
        }
        .width('100%')
      }
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .layoutWeight(1)
    }
    .width(216)
    .height('100%')
    .padding({ left: 6, right: 6, top: 6, bottom: 6 })
  }

  @Builder
  RowView(node: FolderNode, index: number) {
    Row() {
      Text(node.folder.name)
        .fontSize(14)
        .fontColor(this.isDisabled(node.folder.id) ? $r('app.color.ink_tertiary') : $r('app.color.ink'))
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text(`${node.totalCount}`)
        .fontSize(11)
        .fontColor($r('app.color.ink_tertiary'))
    }
    .width('100%')
    .height(38)
    .padding({ left: 8, right: 8 })
    .borderRadius(6)
    .backgroundColor(this.isSelected(node, index) ? $r('app.color.surface') : Color.Transparent)
    .accessibilityText(`选择${node.folder.name}`)
    .focusable(true)
    .onClick(() => this.pick(node, index))
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down &&
        (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
        this.pick(node, index);
      }
    })
  }

  private isSelected(node: FolderNode, index: number): boolean {
    return index < this.chain.length && this.chain[index] === node.folder.id;
  }

  @Builder
  CreateRow(column: PickerColumn, index: number) {
    if (this.createParentId === column.parentId) {
      Row({ space: 6 }) {
        TextInput({ text: this.createDraft, placeholder: '文件夹名' })
          .fontSize(13)
          .fontColor($r('app.color.ink'))
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
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              this.submitCreate();
            }
          })
      }
      .width('100%')
      .padding({ left: 8, right: 8, top: 6 })
    } else {
      Text('+ 新建文件夹')
        .fontSize(12)
        .fontColor($r('app.color.ink_secondary'))
        .width('100%')
        .height(34)
        .padding({ left: 8, right: 8 })
        .textAlign(TextAlign.Start)
        .accessibilityText('新建文件夹')
        .focusable(true)
        .onClick(() => {
          this.startCreate(column, index);
        })
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
            this.startCreate(column, index);
          }
        })
    }
  }
}
