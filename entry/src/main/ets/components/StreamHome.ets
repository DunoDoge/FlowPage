import { pasteboard } from '@kit.BasicServicesKit';
import { Bookmark } from '../model/Bookmark';
import { BookmarkQuery, BookmarkSort } from '../model/BookmarkQuery';
import { AppState } from '../common/AppState';
import { ReadState, StreamFilter } from '../common/Constants';
import { extractFirstUrl } from '../common/UrlUtil';
import { LibrarySummary, FlowRepository } from '../repository/FlowRepository';
import { BookmarkRow } from './BookmarkRow';

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
  @Local loading: boolean = true;
  @Local hasMore: boolean = false;
  @Local loadingMore: boolean = false;
  @Local todayCount: number = 0;
  @Local focusIndex: number = 0;
  @Local selectionMode: boolean = false;
  @Local selectedIds: string[] = [];
  @Local actionTarget: Bookmark = new Bookmark();
  @Local showActions: boolean = false;
  private batchBusy: boolean = false;
  private searchTimer: number = -1;
  private loadGeneration: number = 0;

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
    this.load();
  }

  @Monitor('appState.tagFilter')
  onTagFilterChanged(): void {
    this.exitSelection();
    this.load();
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
    return query;
  }

  private async load(): Promise<void> {
    this.loadGeneration = this.loadGeneration + 1;
    const generation = this.loadGeneration;
    const repo = FlowRepository.get();
    this.loading = true;
    try {
      const page = await repo.queryPage(this.currentQuery(), 0, PAGE_SIZE);
      if (generation !== this.loadGeneration) {
        return;
      }
      this.filtered = page.items;
      this.hasMore = page.hasMore;
      this.focusIndex = 0;
      this.selectedIds = this.pruneSelection(page.items);
      if (this.selectionMode && this.selectedIds.length === 0) {
        this.selectionMode = false;
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

  private pruneSelection(items: Bookmark[]): string[] {
    const next: string[] = [];
    for (let i = 0; i < this.selectedIds.length; i++) {
      if (this.containsId(items, this.selectedIds[i])) {
        next.push(this.selectedIds[i]);
      }
    }
    return next;
  }

  private isChecked(id: string): boolean {
    return this.selectedIds.indexOf(id) >= 0;
  }

  private toggleSelect(id: string): void {
    const index = this.selectedIds.indexOf(id);
    const next = this.selectedIds.slice();
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(id);
    }
    this.selectedIds = next;
    this.selectionMode = next.length > 0;
  }

  private enterSelection(id: string): void {
    this.showActions = false;
    this.selectionMode = true;
    if (!this.isChecked(id)) {
      const next = this.selectedIds.slice();
      next.push(id);
      this.selectedIds = next;
    }
  }

  private exitSelection(): void {
    this.selectionMode = false;
    this.selectedIds = [];
  }

  private finishActions(): void {
    this.showActions = false;
    this.exitSelection();
  }

  private selectAllLoaded(): void {
    if (this.selectedIds.length === this.filtered.length) {
      this.selectedIds = [];
      this.selectionMode = false;
      return;
    }
    const next: string[] = [];
    for (let i = 0; i < this.filtered.length; i++) {
      next.push(this.filtered[i].id);
    }
    this.selectedIds = next;
    this.selectionMode = next.length > 0;
  }

  private requestActions(id: string): void {
    for (let i = 0; i < this.filtered.length; i++) {
      if (this.filtered[i].id === id) {
        this.actionTarget = this.filtered[i];
        this.showActions = true;
        return;
      }
    }
  }

  private allSelectedMatch(match: (item: Bookmark) => boolean): boolean {
    if (this.selectedIds.length === 0) {
      return false;
    }
    for (let i = 0; i < this.filtered.length; i++) {
      if (this.isChecked(this.filtered[i].id) && !match(this.filtered[i])) {
        return false;
      }
    }
    return true;
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

  private async batchStar(): Promise<void> {
    if (this.batchBusy || this.selectedIds.length === 0) {
      return;
    }
    const ids = this.selectedIds.slice();
    const next = !this.allSelectedStarred();
    this.batchBusy = true;
    try {
      await FlowRepository.get().setStarredMany(ids, next);
      AppState.shared.toast(next ? `已给 ${ids.length} 条加星` : `已取消 ${ids.length} 条星标`);
      this.exitSelection();
    } catch (error) {
      AppState.shared.toast('批量加星失败，请重试');
    } finally {
      this.batchBusy = false;
    }
  }

  private async batchArchive(): Promise<void> {
    if (this.batchBusy || this.selectedIds.length === 0) {
      return;
    }
    const ids = this.selectedIds.slice();
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
    if (this.batchBusy || this.selectedIds.length === 0) {
      return;
    }
    const ids = this.selectedIds.slice();
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

  private selectFilter(value: number): void {
    this.filter = value;
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
        Blank()
        Text('标签')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ left: 8, right: 8 })
          .accessibilityText('打开标签页')
          .onClick(() => this.onOpenPane('tags'))
        Text('同步')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ left: 8, right: 8 })
          .accessibilityText('打开同步页')
          .onClick(() => this.onOpenPane('sync'))
        Text('设置')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ left: 8, right: 8 })
          .accessibilityText('打开设置页')
          .onClick(() => this.onOpenPane('settings'))
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
                  selectionMode: this.selectionMode,
                  checked: this.isChecked(item.id),
                  onOpen: (id: string) => {
                    this.showActions = false;
                    this.onOpen(id);
                  },
                  onToggleStar: (id: string, starred: boolean) => {
                    FlowRepository.get().setStarred(id, starred);
                  },
                  onRequestActions: (id: string) => this.requestActions(id),
                  onToggleSelect: (id: string) => this.toggleSelect(id),
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
                this.showActions && !this.selectionMode && this.actionTarget.id === item.id,
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

      if (this.selectionMode) {
        this.BatchActionBar()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  @Builder
  ActionChip(label: string, danger: boolean, action: () => void) {
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
  }

  @Builder
  QuickActionPanel() {
    Flex({ wrap: FlexWrap.Wrap }) {
      if (this.actionTarget.deleted) {
        this.ActionChip('恢复', false, () => {
          this.restoreItems([this.actionTarget.id]);
        })
        this.ActionChip('彻底删除', true, () => {
          this.confirmPurge([this.actionTarget.id]);
        })
        this.ActionChip('多选', false, () => this.enterSelection(this.actionTarget.id))
      } else {
        this.ActionChip('打开', false, () => {
          const id = this.actionTarget.id;
          this.showActions = false;
          this.onOpen(id);
        })
        this.ActionChip('多选', false, () => this.enterSelection(this.actionTarget.id))
        this.ActionChip(this.actionTarget.starred ? '取消星标' : '加星标', false, () => {
          this.quickToggleStar();
        })
        this.ActionChip(this.actionTarget.archived ? '取消归档' : '归档', false, () => {
          this.quickToggleArchive();
        })
        this.ActionChip(this.actionTarget.readState === ReadState.READ ? '标记未读' : '标记已读', false, () => {
          this.quickToggleRead();
        })
        this.ActionChip('删除', true, () => {
          this.confirmTrash([this.actionTarget.id]);
        })
      }
    }
    .width(260)
    .padding({ left: 10, right: 10, top: 8, bottom: 8 })
  }

  @Builder
  BatchActionBar() {
    Column({ space: 10 }) {
      Row({ space: 8 }) {
        Text(`已选 ${this.selectedIds.length} 项`)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
        Blank()
        Text(this.selectedIds.length === this.filtered.length ? '取消全选' : '全选')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .height(36)
          .padding({ left: 8, right: 8 })
          .accessibilityText(this.selectedIds.length === this.filtered.length ? '取消全选当前列表' : '全选当前列表')
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

      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.filter === StreamFilter.TRASH) {
          this.ActionChip('恢复', false, () => {
            this.restoreItems(this.selectedIds.slice());
          })
          this.ActionChip('彻底删除', true, () => {
            this.confirmPurge(this.selectedIds.slice());
          })
        } else {
          this.ActionChip(this.allSelectedStarred() ? '取消星标' : '星标', false, () => {
            this.batchStar();
          })
          this.ActionChip(this.allSelectedArchived() ? '取消归档' : '归档', false, () => {
            this.batchArchive();
          })
          this.ActionChip(this.allSelectedRead() ? '标记未读' : '标记已读', false, () => {
            this.batchRead();
          })
          this.ActionChip('删除', true, () => {
            this.confirmTrash(this.selectedIds.slice());
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
