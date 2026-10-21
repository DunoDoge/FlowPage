import { pasteboard } from '@kit.BasicServicesKit';
import { Bookmark } from '../model/Bookmark';
import { BookmarkQuery, BookmarkSort } from '../model/BookmarkQuery';
import { AppState } from '../common/AppState';
import { StreamFilter } from '../common/Constants';
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
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.load();
    }, 120);
  }

  private selectFilter(value: number): void {
    this.filter = value;
    this.load();
  }

  private selectSort(value: number): void {
    this.sort = value;
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
                  onOpen: (id: string) => this.onOpen(id),
                  onToggleStar: (id: string, starred: boolean) => {
                    FlowRepository.get().setStarred(id, starred);
                  },
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
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
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
