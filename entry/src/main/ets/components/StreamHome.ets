import { pasteboard } from '@kit.BasicServicesKit';
import { Bookmark } from '../model/Bookmark';
import { TagCount } from '../model/Tag';
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

@ComponentV2
export struct StreamHome {
  @Param isWide: boolean = false;
  @Param isLarge: boolean = false;
  @Param refreshKey: number = 0;
  @Event onOpen: (id: string) => void = (id: string) => {};
  @Event onCompose: () => void = () => {};
  @Event onComposeWithUrl: (url: string) => void = (url: string) => {};
  @Event onOpenPane: (pane: string) => void = (pane: string) => {};

  @Local appState: AppState = AppState.shared;
  @Local all: Bookmark[] = [];
  @Local filtered: Bookmark[] = [];
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local tags: TagCount[] = [];
  @Local keyword: string = '';
  @Local filter: number = StreamFilter.ALL;
  @Local loading: boolean = true;
  private searchTimer: number = -1;

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
    this.applyFilter();
  }

  @Monitor('refreshKey')
  onExternalRefresh(): void {
    this.load();
  }

  private async load(): Promise<void> {
    const repo = FlowRepository.get();
    try {
      this.all = await repo.listAll(true);
      this.tags = await repo.listTags();
      this.summary = await repo.summary();
      this.applyFilter();
    } catch (error) {
      AppState.shared.toast('没有读到本地数据');
    } finally {
      this.loading = false;
    }
  }

  private applyFilter(): void {
    const keyword = this.keyword.trim().toLowerCase();
    const tag = this.appState.tagFilter;
    const next: Bookmark[] = [];
    for (let i = 0; i < this.all.length; i++) {
      const item = this.all[i];
      if (this.filter === StreamFilter.TRASH) {
        if (!item.deleted) {
          continue;
        }
      } else {
        if (item.deleted) {
          continue;
        }
        if (this.filter === StreamFilter.ARCHIVED) {
          if (!item.archived) {
            continue;
          }
        } else if (item.archived) {
          continue;
        }
        if (this.filter === StreamFilter.UNREAD && item.readState !== ReadState.UNREAD) {
          continue;
        }
        if (this.filter === StreamFilter.STARRED && !item.starred) {
          continue;
        }
      }
      if (tag.length > 0 && item.tags.indexOf(tag) < 0) {
        continue;
      }
      if (keyword.length > 0 && item.searchText.indexOf(keyword) < 0) {
        continue;
      }
      next.push(item);
    }
    this.filtered = next;
  }

  private onKeywordChange(value: string): void {
    this.keyword = value;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.applyFilter();
    }, 120);
  }

  private selectFilter(value: number): void {
    this.filter = value;
    this.applyFilter();
  }

  private todayCount(): number {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    const startTime = start.getTime();
    let count = 0;
    for (let i = 0; i < this.all.length; i++) {
      if (!this.all[i].deleted && this.all[i].createdAt >= startTime) {
        count = count + 1;
      }
    }
    return count;
  }

  private subtitle(): string {
    if (this.loading) {
      return '正在翻开…';
    }
    return `${this.summary.total} 条 · 今天收下 ${this.todayCount()} 条`;
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
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => this.onOpenPane('tags'))
        Text('同步')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => this.onOpenPane('sync'))
        Text('设置')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .padding({ left: 8, right: 8, top: 6, bottom: 6 })
          .onClick(() => this.onOpenPane('settings'))
      }
      .width('100%')
      .padding({ left: 20, right: 12, top: 12 })

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
          .padding({ left: 14, right: 14, top: 8, bottom: 8 })
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
              .padding({ left: 12, right: 12, top: 6, bottom: 6 })
              .onClick(() => this.selectFilter(option.value))
          }, (option: FilterOption) => `${option.value}`)
        }
        .padding({ left: 20, right: 20 })
      }
      .scrollable(ScrollDirection.Horizontal)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
      .width('100%')
      .margin({ top: 12 })

      if (this.appState.tagFilter.length > 0) {
        Row({ space: 6 }) {
          Text(`标签：${this.appState.tagFilter}`)
            .fontSize(12)
            .fontColor($r('app.color.ink_secondary'))
          Text('×')
            .fontSize(14)
            .fontColor($r('app.color.ink_secondary'))
            .onClick(() => {
              this.appState.tagFilter = '';
            })
        }
        .padding({ left: 20, right: 20, top: 10 })
      }

      if (this.loading) {
        this.SkeletonList()
      } else if (this.filtered.length === 0) {
        this.EmptyView()
      } else {
        List({ space: 0 }) {
          ForEach(this.filtered, (item: Bookmark) => {
            ListItem() {
              Column() {
                BookmarkRow({
                  bookmark: item,
                  selected: this.isWide && item.id === this.appState.selectedId,
                  onOpen: (id: string) => this.onOpen(id),
                  onToggleStar: (id: string, starred: boolean) => {
                    FlowRepository.get().setStarred(id, starred).then(() => {
                      this.load();
                    });
                  }
                })
                Divider()
                  .strokeWidth(1)
                  .color($r('app.color.line'))
                  .margin({ left: 20, right: 20 })
              }
            }
          }, (item: Bookmark) => item.id)
        }
        .width('100%')
        .layoutWeight(1)
        .edgeEffect(EdgeEffect.None)
        .scrollBar(BarState.Off)
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
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
            .onClick(() => this.onCompose())
          Text('导入书签')
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .border({ width: 1, color: $r('app.color.line_strong') })
            .borderRadius(6)
            .padding({ left: 14, right: 14, top: 8, bottom: 8 })
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
