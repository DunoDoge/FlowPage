import { pasteboard } from '@kit.BasicServicesKit';
import { KeyCode } from '@kit.InputKit';
import { Bookmark } from '../model/Bookmark';
import { BookmarkQuery, BookmarkSort } from '../model/BookmarkQuery';
import { AppState } from '../common/AppState';
import { ReadState, StreamFilter } from '../common/Constants';
import { FolderDragSession } from '../common/FolderDragSession';
import { extractFirstUrl } from '../common/UrlUtil';
import { LibrarySummary, BatchImpact, BatchOutcome, FlowRepository } from '../repository/FlowRepository';
import { BookmarkRow } from './BookmarkRow';
import { FolderPicker } from './FolderPicker';

class FilterOption {
  label: string = '';
  value: number = 0;
}

const FILTERS: FilterOption[] = [
  { label: '全部', value: StreamFilter.ALL },
  { label: '未读', value: StreamFilter.UNREAD },
  { label: '星标', value: StreamFilter.STARRED },
  { label: '归档', value: StreamFilter.ARCHIVED },
  { label: '回收站', value: StreamFilter.TRASH }
];

const PAGE_SIZE: number = 50;

@ComponentV2
export struct StreamHome {
  @Param isWide: boolean = false;
  @Param folderDocked: boolean = false;
  @Param refreshKey: number = 0;
  @Event onOpen: (id: string) => void = (id: string) => {};
  @Event onCompose: () => void = () => {};
  @Event onComposeWithUrl: (url: string) => void = (url: string) => {};
  @Event onOpenPane: (pane: string) => void = (pane: string) => {};

  @Local appState: AppState = AppState.shared;
  @Local filtered: Bookmark[] = [];
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local keyword: string = '';
  @Local filter: number = StreamFilter.ALL;
  @Local sort: number = BookmarkSort.CREATED_DESC;
  @Local folderLabel: string = '';
  @Local loading: boolean = true;
  @Local hasMore: boolean = false;
  @Local loadingMore: boolean = false;
  @Local todayCount: number = 0;
  @Local focusIndex: number = 0;
  @Local batchMoveOpen: boolean = false;
  @Local actionTarget: Bookmark = new Bookmark();
  @Local showActions: boolean = false;
  @Local bookmarkMoveOpen: boolean = false;
  @Local dragSession: FolderDragSession = FolderDragSession.shared;
  private batchBusy: boolean = false;
  private searchTimer: number = -1;
  private loadGeneration: number = 0;
  private pendingReload: boolean = false;

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    if (this.dragSession.active) {
      this.pendingReload = true;
      return;
    }
    this.load();
  }

  @Monitor('dragSession.active')
  onDragSessionChanged(): void {
    if (!this.dragSession.active && this.pendingReload) {
      this.pendingReload = false;
      this.load();
    }
  }

  @Monitor('appState.tagFilter')
  onTagFilterChanged(): void {
    this.exitSelection();
    this.load();
  }

  @Monitor('appState.folderFilter')
  onFolderFilterChanged(): void {
    this.exitSelection();
    this.load();
  }

  @Monitor('appState.selectionMode')
  onRowSelectionModeChanged(): void {
    if (!this.appState.selectionMode) {
      this.batchMoveOpen = false;
      this.bookmarkMoveOpen = false;
    }
  }

  @Monitor('refreshKey')
  onExternalRefresh(): void {
    this.load();
  }

  private currentQuery(): BookmarkQuery {
    const query = new BookmarkQuery();
    query.filter = this.filter;
    query.tag = this.appState.tagFilter;
    query.keyword = this.keyword;
    query.sort = this.sort;
    // Direct-membership folder filter: subfolder bookmarks are reached by
    // drilling into their own folder rows, not by expanding the subtree here.
    query.folderId = this.appState.folderFilter;
    return query;
  }

  private async load(): Promise<void> {
    this.loadGeneration = this.loadGeneration + 1;
    const generation = this.loadGeneration;
    const repo = FlowRepository.get();
    this.loading = true;
    try {
      if (this.appState.folderFilter.length > 0) {
        const folder = await repo.getFolder(this.appState.folderFilter);
        this.folderLabel = folder !== undefined ? folder.name : '';
      } else {
        this.folderLabel = '';
      }
      const page = await repo.queryPage(this.currentQuery(), 0, PAGE_SIZE);
      if (generation !== this.loadGeneration) {
        return;
      }
      this.filtered = page.items;
      this.hasMore = page.hasMore;
      this.focusIndex = 0;
      this.pruneSelection(page.items);
      if (this.appState.selectionMode && this.appState.rowSelectionCount() === 0) {
        this.appState.clearRowSelection();
      }
      if (this.showActions && !this.containsId(page.items, this.actionTarget.id)) {
        this.showActions = false;
      }
      const summary = await repo.summary();
      if (generation !== this.loadGeneration) {
        return;
      }
      this.summary = summary;
      const todayCount = await repo.countToday();
      if (generation !== this.loadGeneration) {
        return;
      }
      this.todayCount = todayCount;
    } catch (error) {
      if (generation === this.loadGeneration) {
        AppState.shared.toast('没有读到本地数据');
      }
    } finally {
      if (generation === this.loadGeneration) {
        this.loading = false;
      }
    }
  }

  private async loadMore(): Promise<void> {
    if (!this.hasMore || this.loadingMore || this.loading) {
      return;
    }
    this.loadingMore = true;
    const generation = this.loadGeneration;
    const base = this.filtered;
    try {
      const page = await FlowRepository.get().queryPage(this.currentQuery(), base.length, PAGE_SIZE);
      if (generation !== this.loadGeneration || this.filtered !== base) {
        return;
      }
      const next = this.filtered.slice();
      for (let i = 0; i < page.items.length; i++) {
        next.push(page.items[i]);
      }
      this.filtered = next;
      this.hasMore = page.hasMore;
    } catch (error) {
      if (generation === this.loadGeneration) {
        AppState.shared.toast('没有读到更多数据');
      }
    } finally {
      this.loadingMore = false;
    }
  }

  private onKeywordChange(value: string): void {
    this.keyword = value;
    this.exitSelection();
    this.showActions = false;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.load();
    }, 120);
  }

  private containsId(items: Bookmark[], id: string): boolean {
    for (let i = 0; i < items.length; i++) {
      if (items[i].id === id) {
        return true;
      }
    }
    return false;
  }

  private pruneSelection(items: Bookmark[]): void {
    const live: string[] = [];
    for (let i = 0; i < items.length; i++) {
      live.push(items[i].id);
    }
    this.appState.pruneBookmarkSelection(live);
  }

  private isChecked(id: string): boolean {
    return this.appState.isBookmarkSelected(id);
  }

  private selectedCount(): number {
    return this.appState.rowSelectionCount();
  }

  private toggleSelect(id: string): void {
    this.appState.toggleBookmarkSelected(id);
  }

  private toggleSelectionMode(): void {
    if (this.appState.selectionMode) {
      this.exitSelection();
      return;
    }
    this.appState.selectionMode = true;
    this.showActions = false;
  }

  private enterSelection(id: string): void {
    this.showActions = false;
    this.appState.beginRowSelection(id);
  }

  private exitSelection(): void {
    this.appState.clearRowSelection();
    this.batchMoveOpen = false;
    this.bookmarkMoveOpen = false;
  }

  private finishActions(): void {
    this.showActions = false;
    this.bookmarkMoveOpen = false;
    this.exitSelection();
  }

  private selectAllLoaded(): void {
    if (this.appState.selectedBookmarkIds.length === this.filtered.length) {
      this.appState.selectedBookmarkIds = [];
      this.appState.selectionMode = this.appState.rowSelectionCount() > 0;
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.filtered.length; i++) {
      next.push(this.filtered[i].id);
    }
    this.appState.setBookmarkSelection(next);
  }

  private requestActions(id: string): void {
    for (let i = 0; i < this.filtered.length; i++) {
      if (this.filtered[i].id === id) {
        this.actionTarget = this.filtered[i];
        this.bookmarkMoveOpen = false;
        this.showActions = true;
        return;
      }
    }
  }

  private allSelectedMatch(match: (item: Bookmark) => boolean): boolean {
    return this.appState.selectedBookmarkIds.length > 0 &&
      this.countSelectedMatch(match) === this.appState.selectedBookmarkIds.length;
  }

  private anySelectedMatch(match: (item: Bookmark) => boolean): boolean {
    return this.countSelectedMatch(match) > 0;
  }

  private countSelectedMatch(match: (item: Bookmark) => boolean): number {
    let count = 0;
    for (let i = 0; i < this.filtered.length; i++) {
      if (this.isChecked(this.filtered[i].id) && match(this.filtered[i])) {
        count = count + 1;
      }
    }
    return count;
  }

  private allSelectedStarred(): boolean {
    return this.allSelectedMatch((item: Bookmark) => item.starred);
  }

  private allSelectedArchived(): boolean {
    return this.allSelectedMatch((item: Bookmark) => item.archived);
  }

  private allSelectedRead(): boolean {
    return this.allSelectedMatch((item: Bookmark) => item.readState === ReadState.READ);
  }

  private starActionLabel(): string {
    return this.allSelectedStarred() ? '取消星标' : '星标';
  }

  private archiveActionLabel(): string {
    if (this.allSelectedArchived()) {
      return '取消归档';
    }
    if (this.anySelectedMatch((item: Bookmark) => item.archived)) {
      return '全部归档';
    }
    return '归档';
  }

  private readActionLabel(): string {
    if (this.allSelectedRead()) {
      return '标记未读';
    }
    if (this.anySelectedMatch((item: Bookmark) => item.readState === ReadState.READ)) {
      return '全部已读';
    }
    return '标记已读';
  }

  private async batchStar(): Promise<void> {
    if (this.batchBusy || this.appState.selectedBookmarkIds.length === 0) {
      return;
    }
    const ids = this.appState.selectedBookmarkIds.slice();
    const next = !this.allSelectedStarred();
    const added = this.countSelectedMatch((item: Bookmark) => !item.starred);
    this.batchBusy = true;
    try {
      await FlowRepository.get().setStarredMany(ids, next);
      AppState.shared.toast(next ? `已加上 ${added} 条星标` : `已取消 ${ids.length} 条星标`);
      this.exitSelection();
    } catch (error) {
      AppState.shared.toast('批量加星失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private async batchArchive(): Promise<void> {
    if (this.batchBusy || this.appState.selectedBookmarkIds.length === 0) {
      return;
    }
    const ids = this.appState.selectedBookmarkIds.slice();
    const next = !this.allSelectedArchived();
    this.batchBusy = true;
    try {
      await FlowRepository.get().setArchivedMany(ids, next);
      AppState.shared.toast(next ? `已归档 ${ids.length} 条` : `已取消 ${ids.length} 条归档`);
      this.exitSelection();
    } catch (error) {
      AppState.shared.toast('批量归档失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private async batchRead(): Promise<void> {
    if (this.batchBusy || this.appState.selectedBookmarkIds.length === 0) {
      return;
    }
    const ids = this.appState.selectedBookmarkIds.slice();
    const next = this.allSelectedRead() ? ReadState.UNREAD : ReadState.READ;
    this.batchBusy = true;
    try {
      await FlowRepository.get().setReadMany(ids, next);
      AppState.shared.toast(next === ReadState.READ ? `已标记 ${ids.length} 条已读` : `已标记 ${ids.length} 条未读`);
      this.exitSelection();
    } catch (error) {
      AppState.shared.toast('批量标记失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private batchResultToast(outcome: BatchOutcome, verb: string): void {
    const suffix = outcome.skipped > 0 ? `，跳过 ${outcome.skipped} 项` : '';
    AppState.shared.toast(`已${verb} ${outcome.done} 项${suffix}`);
  }

  private runBatchMove(folderId: string, label: string): void {
    const books = this.appState.selectedBookmarkIds.slice(0);
    const folders = this.appState.selectedFolderIds.slice(0);
    if (books.length + folders.length === 0) {
      AppState.shared.toast('先勾选要移动的行');
      return;
    }
    this.batchMoveOpen = false;
    FlowRepository.get().batchMove(books, folders, folderId).then((outcome: BatchOutcome): void => {
      this.batchResultToast(outcome, `移到${label.length > 0 ? label : '根目录'}`);
      this.exitSelection();
    }).catch((): void => {
      AppState.shared.toast('批量移动失败，请稍后再试');
    });
  }

  private runBatchMoveOut(): void {
    const books = this.appState.selectedBookmarkIds.slice(0);
    const folders = this.appState.selectedFolderIds.slice(0);
    if (books.length + folders.length === 0) {
      AppState.shared.toast('先勾选要移出的行');
      return;
    }
    FlowRepository.get().batchMoveOut(books, folders).then((outcome: BatchOutcome): void => {
      this.batchResultToast(outcome, '移出');
      this.exitSelection();
    }).catch((): void => {
      AppState.shared.toast('批量移出失败，请稍后再试');
    });
  }

  private confirmBatchDelete(): void {
    const books = this.appState.selectedBookmarkIds.slice(0);
    const folders = this.appState.selectedFolderIds.slice(0);
    if (books.length + folders.length === 0) {
      AppState.shared.toast('先勾选要删除的行');
      return;
    }
    if (folders.length === 0) {
      this.confirmTrash(books);
      return;
    }
    FlowRepository.get().batchDeleteImpact(books, folders).then((impact: BatchImpact): void => {
      const parts: string[] = [];
      if (impact.folders > 0) {
        parts.push(`${impact.folders} 个文件夹（连同子文件夹内 ${impact.subtreeBooks} 条笺）`);
      }
      if (impact.looseBooks > 0) {
        parts.push(`${impact.looseBooks} 条笺`);
      }
      AlertDialog.show({
        title: '批量删除？',
        message: `将把${parts.join('与')}移入回收站，可在回收站恢复。`,
        primaryButton: {
          value: '取消',
          action: () => {}
        },
        secondaryButton: {
          value: '删除',
          fontColor: $r('app.color.danger'),
          action: (): void => {
            this.runBatchDelete(books, folders);
          }
        }
      });
    }).catch((): void => {
      AppState.shared.toast('删除失败，请稍后再试');
    });
  }

  private runBatchDelete(books: string[], folders: string[]): void {
    FlowRepository.get().batchDelete(books, folders).then((outcome: BatchOutcome): void => {
      this.batchResultToast(outcome, '删除');
      this.exitSelection();
    }).catch((): void => {
      AppState.shared.toast('删除失败，请稍后再试');
    });
  }

  private beginDragFromBookmark(id: string): void {
    if (this.isChecked(id)) {
      this.dragSession.begin(this.appState.selectedBookmarkIds.slice(0), this.appState.selectedFolderIds.slice(0), id);
    } else {
      this.dragSession.begin([id], [], id);
    }
    this.showActions = false;
    if (!this.folderDocked) {
      this.appState.folderDrawerOpen = true;
    }
  }

  private async trashItems(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    this.batchBusy = true;
    try {
      await FlowRepository.get().deleteMany(ids);
      AppState.shared.toast(`已把 ${ids.length} 条放进回收站`);
      this.finishActions();
    } catch (error) {
      AppState.shared.toast('删除失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private async restoreItems(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    this.batchBusy = true;
    try {
      await FlowRepository.get().restoreMany(ids);
      AppState.shared.toast(`已恢复 ${ids.length} 条`);
      this.finishActions();
    } catch (error) {
      AppState.shared.toast('恢复失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private async purgeItems(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    this.batchBusy = true;
    try {
      await FlowRepository.get().purgeMany(ids);
      AppState.shared.toast(`已彻底删除 ${ids.length} 条`);
      this.finishActions();
    } catch (error) {
      AppState.shared.toast('彻底删除失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private confirmTrash(ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    this.showActions = false;
    AlertDialog.show({
      title: ids.length === 1 ? '删除这一笺？' : `删除这 ${ids.length} 条？`,
      message: '30 天内可在回收站恢复。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.trashItems(ids);
        }
      }
    });
  }

  private confirmPurge(ids: string[]): void {
    if (ids.length === 0) {
      return;
    }
    this.showActions = false;
    AlertDialog.show({
      title: ids.length === 1 ? '彻底删除这一笺？' : `彻底删除这 ${ids.length} 条？`,
      message: '删除后不可恢复，正文快照也会一并删除。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '彻底删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          this.purgeItems(ids);
        }
      }
    });
  }

  private async quickToggleStar(): Promise<void> {
    const target = this.actionTarget;
    const next = !target.starred;
    this.showActions = false;
    try {
      await FlowRepository.get().setStarred(target.id, next);
      AppState.shared.toast(next ? '已加星标' : '已取消星标');
    } catch (error) {
      AppState.shared.toast('操作失败，请重试');
    }
  }

  private async quickToggleArchive(): Promise<void> {
    const target = this.actionTarget;
    const next = !target.archived;
    this.showActions = false;
    try {
      await FlowRepository.get().setArchived(target.id, next);
      AppState.shared.toast(next ? '已归档' : '已取消归档');
    } catch (error) {
      AppState.shared.toast('操作失败，请重试');
    }
  }

  private async quickToggleRead(): Promise<void> {
    const target = this.actionTarget;
    const next = target.readState === ReadState.READ ? ReadState.UNREAD : ReadState.READ;
    this.showActions = false;
    try {
      await FlowRepository.get().setRead(target.id, next);
      AppState.shared.toast(next === ReadState.READ ? '已标记为已读' : '已标记为未读');
    } catch (error) {
      AppState.shared.toast('操作失败，请重试');
    }
  }

  private async runBookmarkMove(folderId: string, label: string): Promise<void> {
    const id = this.actionTarget.id;
    this.showActions = false;
    this.bookmarkMoveOpen = false;
    try {
      await FlowRepository.get().setBookmarkFolder(id, folderId);
      AppState.shared.toast(`已移到${label.length > 0 ? label : '根目录'}`);
    } catch (error) {
      AppState.shared.toast('移动失败，请稍后再试');
    }
  }

  private selectFilter(value: number): void {
    this.filter = value;
    this.appState.homeFilter = value;
    this.exitSelection();
    this.showActions = false;
    this.load();
  }

  private selectSort(value: number): void {
    this.sort = value;
    this.exitSelection();
    this.showActions = false;
    this.load();
  }

  private moveFocus(delta: number): void {
    if (this.filtered.length === 0) {
      return;
    }
    let next = this.focusIndex + delta;
    if (next < 0) {
      next = 0;
    }
    if (next >= this.filtered.length) {
      next = this.filtered.length - 1;
    }
    this.focusIndex = next;
    focusControl.requestFocus(`bookmark-row-${this.filtered[next].id}`);
    if (next >= this.filtered.length - 5 && this.hasMore) {
      this.loadMore();
    }
  }

  private subtitle(): string {
    if (this.loading) {
      return '正在翻开…';
    }
    return `${this.summary.total} 条 · 今天收下 ${this.todayCount} 条`;
  }

  private async readClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      const found = extractFirstUrl(text);
      if (found.length === 0) {
        AppState.shared.toast('剪贴板里没有链接');
        return;
      }
      this.onComposeWithUrl(found);
    } catch (error) {
      AppState.shared.toast('读不到剪贴板');
    }
  }

  build() {
    Column() {
      Row() {
        if (!this.folderDocked) {
          Text('☰')
            .fontSize(16)
            .fontColor($r('app.color.ink_secondary'))
            .width(44)
            .height(44)
            .textAlign(TextAlign.Center)
            .accessibilityText('打开文件夹')
            .focusable(true)
            .onClick(() => {
              this.appState.folderDrawerOpen = true;
            })
        }
        Blank()
        Text(this.appState.selectionMode ? '完成' : '批量')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ left: 8, right: 8 })
          .accessibilityText(this.appState.selectionMode ? '退出批量选择' : '进入批量选择')
          .focusable(true)
          .onClick(() => this.toggleSelectionMode())
      }
      .width('100%')
      .padding({ left: 20, right: 12 })

      Row() {
        Column({ space: 4 }) {
          Text('流笺')
            .fontSize(34)
            .fontWeight(FontWeight.Bold)
            .fontColor($r('app.color.ink'))
          Text(this.subtitle())
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
        }
        .alignItems(HorizontalAlign.Start)
        .layoutWeight(1)

        Text('+ 收笺')
          .fontSize(13)
          .fontColor($r('app.color.inverse_ink'))
          .backgroundColor($r('app.color.ink'))
          .borderRadius(6)
          .height(44)
          .padding({ left: 14, right: 14 })
          .textAlign(TextAlign.Center)
          .accessibilityText('收一笺')
          .onClick(() => this.onCompose())
      }
      .width('100%')
      .alignItems(VerticalAlign.Bottom)
      .padding({ left: 20, right: 20, top: 14 })

      Row({ space: 8 }) {
        TextInput({ placeholder: '搜索标题、域名或摘录', text: this.keyword })
          .fontSize(14)
          .fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.ink_tertiary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(6)
          .height(44)
          .layoutWeight(1)
          .accessibilityText('搜索')
          .onChange((value: string) => this.onKeywordChange(value))
        PasteButton({ text: PasteDescription.PASTE })
          .fontSize(14)
          .fontColor($r('app.color.ink_secondary'))
          .backgroundColor($r('app.color.surface'))
          .borderRadius(6)
          .height(44)
          .padding({ left: 16, right: 16 })
          .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
            if (result === PasteButtonOnClickResult.SUCCESS) {
              this.readClipboard();
            } else {
              AppState.shared.toast('没有获得剪贴板授权');
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 18 })

      Scroll() {
        Row({ space: 8 }) {
          ForEach(FILTERS, (option: FilterOption) => {
            Text(option.label)
              .fontSize(12)
              .fontColor(this.filter === option.value ? $r('app.color.inverse_ink') : $r('app.color.ink_secondary'))
              .backgroundColor(this.filter === option.value ? $r('app.color.ink') : Color.Transparent)
              .border({
                width: 1,
                color: this.filter === option.value ? $r('app.color.ink') : $r('app.color.line_strong')
              })
              .borderRadius(999)
              .height(44)
              .padding({ left: 12, right: 12 })
              .textAlign(TextAlign.Center)
              .accessibilityText(`筛选：${option.label}`)
              .onClick(() => this.selectFilter(option.value))
          }, (option: FilterOption) => `${option.value}`)
        }
        .padding({ left: 20, right: 20 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .width('100%')
      .margin({ top: 8 })

      Row({ space: 12 }) {
        Text('排序')
          .fontSize(11)
          .fontColor($r('app.color.ink_tertiary'))
        Text('最新')
          .fontSize(12)
          .fontColor(this.sort === BookmarkSort.CREATED_DESC ? $r('app.color.ink') : $r('app.color.ink_tertiary'))
          .height(44)
          .padding({ left: 6, right: 6 })
          .accessibilityText('按创建时间排序')
          .onClick(() => this.selectSort(BookmarkSort.CREATED_DESC))
        Text('域名')
          .fontSize(12)
          .fontColor(this.sort === BookmarkSort.DOMAIN_ASC ? $r('app.color.ink') : $r('app.color.ink_tertiary'))
          .height(44)
          .padding({ left: 6, right: 6 })
          .accessibilityText('按域名排序')
          .onClick(() => this.selectSort(BookmarkSort.DOMAIN_ASC))
      }
      .width('100%')
      .padding({ left: 20, right: 20 })
      .alignItems(VerticalAlign.Center)

      if (this.appState.tagFilter.length > 0) {
        Row({ space: 6 }) {
          Text(`标签：${this.appState.tagFilter}`)
            .fontSize(12)
            .fontColor($r('app.color.ink_secondary'))
          Text('×')
            .fontSize(14)
            .fontColor($r('app.color.ink_secondary'))
            .height(44)
            .width(44)
            .textAlign(TextAlign.Center)
            .accessibilityText('清除标签筛选')
            .onClick(() => {
              this.appState.tagFilter = '';
            })
        }
        .padding({ left: 20, right: 20 })
      }

      if (this.appState.folderFilter.length > 0) {
        Row({ space: 6 }) {
          Text(`文件夹：${this.folderLabel}`)
            .fontSize(12)
            .fontColor($r('app.color.ink_secondary'))
          Text('×')
            .fontSize(14)
            .fontColor($r('app.color.ink_secondary'))
            .height(44)
            .width(44)
            .textAlign(TextAlign.Center)
            .accessibilityText('清除文件夹筛选')
            .onClick(() => {
              this.appState.folderFilter = '';
            })
        }
        .padding({ left: 20, right: 20 })
      }

      if (this.loading) {
        this.SkeletonList()
      } else if (this.filtered.length === 0) {
        this.EmptyView()
      } else {
        List({ space: 0 }) {
          ForEach(this.filtered, (item: Bookmark, index: number) => {
            ListItem() {
              Column() {
                BookmarkRow({
                  bookmark: item,
                  index: index,
                  keyword: this.keyword,
                  selected: this.isWide && item.id === this.appState.selectedId,
                  selectionMode: this.appState.selectionMode,
                  checked: this.isChecked(item.id),
                  selectedBookmarkIds: this.appState.selectedBookmarkIds,
                  selectedFolderIds: this.appState.selectedFolderIds,
                  dragEnabled: !item.deleted,
                  onOpen: (id: string) => {
                    this.showActions = false;
                    this.bookmarkMoveOpen = false;
                    this.onOpen(id);
                  },
                  onToggleStar: (id: string, starred: boolean) => {
                    FlowRepository.get().setStarred(id, starred);
                  },
                  onRequestActions: (id: string) => this.requestActions(id),
                  onToggleSelect: (id: string) => this.toggleSelect(id),
                  onBeginDrag: (id: string) => this.beginDragFromBookmark(id),
                  onDragFinished: () => this.dragSession.end(),
                  onMoveFocus: (delta: number) => this.moveFocus(delta),
                  onFocused: (focused: number) => {
                    this.focusIndex = focused;
                  }
                })
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.line'))
                  .margin({ left: 20, right: 20 })
              }
              .bindPopup(
                this.showActions && !this.appState.selectionMode && this.actionTarget.id === item.id,
                {
                  builder: this.QuickActionPanel,
                  placement: Placement.Bottom,
                  popupColor: $r('app.color.surface'),
                  enableArrow: true,
                  autoCancel: true,
                  radius: 12,
                  targetSpace: 8,
                  onStateChange: (event: PopupStateChangeParam) => {
                    if (!event.isVisible && this.actionTarget.id === item.id) {
                      this.showActions = false;
                      this.bookmarkMoveOpen = false;
                    }
                  }
                }
              )
            }
          }, (item: Bookmark) => `${item.id}:${item.rev}:${item.updatedAt}`)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
        .onReachEnd(() => {
          this.loadMore();
        })
      }

      if (this.appState.selectionMode) {
        this.BatchActionBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  // Labels are providers so the Text update function reads selection state itself;
  // a precomputed string would freeze when only the selection changes.
  @Builder
  ActionChip(label: () => string, danger: boolean, action: () => void) {
    Text(label())
      .fontSize(13)
      .fontColor(danger ? $r('app.color.danger') : $r('app.color.ink'))
      .backgroundColor($r('app.color.surface_alt'))
      .borderRadius(6)
      .height(40)
      .padding({ left: 14, right: 14 })
      .textAlign(TextAlign.Center)
      .margin({ right: 8, top: 4 })
      .accessibilityText(label())
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
  QuickActionPanel() {
    if (this.bookmarkMoveOpen) {
      Column({ space: 6 }) {
        Row() {
          Text(`移动「${this.actionTarget.title.length > 0 ? this.actionTarget.title : this.actionTarget.url}」到…`)
            .fontSize(12)
            .fontColor($r('app.color.ink_secondary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          Text('取消')
            .fontSize(12)
            .fontColor($r('app.color.ink_secondary'))
            .height(32)
            .padding({ left: 8, right: 8 })
            .accessibilityText('取消移动书签')
            .onClick(() => {
              this.bookmarkMoveOpen = false;
            })
        }
        .width('100%')

        FolderPicker({
          selectedId: this.actionTarget.folderId,
          rootLabel: '根目录',
          pickerHeight: 170,
          onPick: (folderId: string, label: string): void => {
            this.runBookmarkMove(folderId, label);
          }
        })
          .width('100%')
      }
      .width(236)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    } else {
      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.actionTarget.deleted) {
          this.ActionChip(() => '恢复', false, () => {
            this.restoreItems([this.actionTarget.id]);
          })
          this.ActionChip(() => '彻底删除', true, () => {
            this.confirmPurge([this.actionTarget.id]);
          })
          this.ActionChip(() => '多选', false, () => this.enterSelection(this.actionTarget.id))
        } else {
          this.ActionChip(() => '打开', false, () => {
            const id = this.actionTarget.id;
            this.showActions = false;
            this.onOpen(id);
          })
          this.ActionChip(() => '多选', false, () => this.enterSelection(this.actionTarget.id))
          this.ActionChip(() => '移动到文件夹', false, () => {
            this.bookmarkMoveOpen = true;
          })
          this.ActionChip(() => this.actionTarget.starred ? '取消星标' : '加星标', false, () => {
            this.quickToggleStar();
          })
          this.ActionChip(() => this.actionTarget.archived ? '取消归档' : '归档', false, () => {
            this.quickToggleArchive();
          })
          this.ActionChip(() => this.actionTarget.readState === ReadState.READ ? '标记未读' : '标记已读', false, () => {
            this.quickToggleRead();
          })
          this.ActionChip(() => '删除', true, () => {
            this.confirmTrash([this.actionTarget.id]);
          })
        }
      }
      .width(260)
      .padding({ left: 10, right: 10, top: 8, bottom: 8 })
    }
  }

  @Builder
  BatchActionBar() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`已选 ${this.selectedCount()} 项`)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
        if (this.appState.selectedFolderIds.length > 0) {
          Text(`含 ${this.appState.selectedFolderIds.length} 个文件夹`)
            .fontSize(11)
            .fontColor($r('app.color.ink_tertiary'))
        }
        Blank()
        Text(this.appState.selectedBookmarkIds.length === this.filtered.length ? '取消全选' : '全选')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .accessibilityText(this.appState.selectedBookmarkIds.length === this.filtered.length ? '取消全选当前列表' : '全选当前列表')
          .onClick(() => this.selectAllLoaded())
        Text('完成')
          .fontSize(12)
          .fontColor($r('app.color.ink'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .accessibilityText('退出多选')
          .onClick(() => this.exitSelection())
      }
      .width('100%')

      if (this.batchMoveOpen) {
        Column({ space: 6 }) {
          Row() {
            Text('移动所选项到…')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .layoutWeight(1)
            Text('取消')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .height(32)
              .padding({ left: 8, right: 8 })
              .accessibilityText('取消批量移动')
              .onClick(() => {
                this.batchMoveOpen = false;
              })
          }
          .width('100%')

          FolderPicker({
            rootLabel: '根目录',
            pickerHeight: 170,
            excludeSubtreeOfIds: this.appState.selectedFolderIds.slice(0),
            onPick: (folderId: string, label: string): void => {
              this.runBatchMove(folderId, label);
            }
          })
            .width('100%')
        }
        .width('100%')
        .alignItems(HorizontalAlign.Start)
      }

      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.filter === StreamFilter.TRASH) {
          this.ActionChip(() => '恢复', false, () => {
            this.restoreItems(this.appState.selectedBookmarkIds.slice());
          })
          this.ActionChip(() => '彻底删除', true, () => {
            this.confirmPurge(this.appState.selectedBookmarkIds.slice());
          })
        } else {
          if (this.appState.selectedBookmarkIds.length > 0) {
            this.ActionChip(() => this.starActionLabel(), false, () => {
              this.batchStar();
            })
            this.ActionChip(() => this.archiveActionLabel(), false, () => {
              this.batchArchive();
            })
            this.ActionChip(() => this.readActionLabel(), false, () => {
              this.batchRead();
            })
          }
          this.ActionChip(() => '移动到…', false, () => {
            this.batchMoveOpen = !this.batchMoveOpen;
          })
          this.ActionChip(() => '移出一级', false, () => {
            this.runBatchMoveOut();
          })
          this.ActionChip(() => '删除', true, () => {
            this.confirmBatchDelete();
          })
        }
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12, bottom: 12 })
    .backgroundColor($r('app.color.surface'))
    .border({ width: { top: 1 }, color: $r('app.color.line') })
  }

  @Builder
  SkeletonList() {
    Column({ space: 20 }) {
      ForEach([1, 2, 3], (item: number) => {
        Column({ space: 8 }) {
          Row()
            .width('72%')
            .height(14)
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(2)
          Row()
            .width('46%')
            .height(10)
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(2)
        }
        .alignItems(HorizontalAlign.Start)
        .width('100%')
      }, (item: number) => `${item}`)
    }
    .padding({ left: 20, right: 20, top: 24 })
    .layoutWeight(1)
  }

  @Builder
  EmptyView() {
    Column({ space: 10 }) {
      Text(this.emptyTitle())
        .fontSize(17)
        .fontColor($r('app.color.ink'))
      Text(this.emptyHint())
        .fontSize(13)
        .fontColor($r('app.color.ink_secondary'))
        .textAlign(TextAlign.Center)
        .lineHeight(21)
      if (this.filter !== StreamFilter.TRASH) {
        Row({ space: 12 }) {
          Text('收第一笺')
            .fontSize(13)
            .fontColor($r('app.color.inverse_ink'))
            .backgroundColor($r('app.color.ink'))
            .borderRadius(6)
            .height(44)
            .padding({ left: 14, right: 14 })
            .textAlign(TextAlign.Center)
            .accessibilityText('收第一笺')
            .onClick(() => this.onCompose())
          Text('导入书签')
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .border({ width: 1, color: $r('app.color.line_strong') })
            .borderRadius(6)
            .height(44)
            .padding({ left: 14, right: 14 })
            .textAlign(TextAlign.Center)
            .accessibilityText('导入书签')
            .onClick(() => this.onOpenPane('settings'))
        }
        .margin({ top: 8 })
      }
    }
    .width('100%')
    .layoutWeight(1)
    .justifyContent(FlexAlign.Center)
    .padding({ left: 40, right: 40 })
  }

  private emptyTitle(): string {
    if (this.keyword.length > 0) {
      return '没有找到';
    }
    if (this.filter === StreamFilter.TRASH) {
      return '回收站是空的';
    }
    return '纸还空着';
  }

  private emptyHint(): string {
    if (this.keyword.length > 0) {
      return '换个词，或去标签里翻翻。';
    }
    if (this.filter === StreamFilter.TRASH) {
      return '删掉的笺会在这里留 30 天。';
    }
    return '收下第一条链接，纸就有了内容。';
  }
}
