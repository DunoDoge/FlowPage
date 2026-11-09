import { AppState } from '../common/AppState';
import { Pane, StreamFilter } from '../common/Constants';
import { LibrarySummary, FlowRepository } from '../repository/FlowRepository';

class SmartViewOption {
  label: string = '';
  value: number = StreamFilter.ALL;
  icon: Resource = $r('sys.symbol.inbox');
}

const SMART_VIEWS: SmartViewOption[] = [
  { label: '全部', value: StreamFilter.ALL, icon: $r('sys.symbol.inbox') },
  { label: '未读', value: StreamFilter.UNREAD, icon: $r('sys.symbol.dot_circle') },
  { label: '星标', value: StreamFilter.STARRED, icon: $r('sys.symbol.star') },
  { label: '归档', value: StreamFilter.ARCHIVED, icon: $r('sys.symbol.archivebox') },
  { label: '回收站', value: StreamFilter.TRASH, icon: $r('sys.symbol.trash') }
];

// Label inset matches NavList rows so both blocks align in the rail.
const LABEL_INSET: number = 20;

// Library smart views shared by the phone drawer and the docked rail.
// Selecting a view writes AppState.homeFilter (the stream's single filter
// source), exits batch selection, returns to the stream destination and
// closes the drawer.
@ComponentV2
export struct SmartViews {
  // Drawer copies defer their first query until the drawer actually opens
  // so cold start does not queue summary/tree queries ahead of the first
  // stream page (real-device feedback: tab content painted late). Rail
  // copies stay eager — the rail is visible from the first frame.
  @Param deferUntilDrawerOpen: boolean = false;
  @Local started: boolean = false;
  @Local appState: AppState = AppState.shared;
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local hovered: number = -1;
  @Local pressed: number = -1;

  aboutToAppear(): void {
    if (!this.deferUntilDrawerOpen && this.appState.libraryReady) {
      this.started = true;
      this.load();
    }
  }

  @Monitor('appState.libraryReady')
  onLibraryReady(): void {
    if (this.appState.libraryReady && (!this.deferUntilDrawerOpen || this.started)) {
      this.load();
    }
  }

  @Monitor('appState.folderDrawerOpen')
  onDrawerOpenChanged(): void {
    if (this.appState.folderDrawerOpen && !this.started) {
      this.started = true;
      if (this.appState.libraryReady) {
        this.load();
      }
    }
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    if (this.started) {
      this.load();
    }
  }

  private async load(): Promise<void> {
    try {
      this.summary = await FlowRepository.get().summary();
    } catch (error) {
      // Keep the previous counts; the stream toast already covers failures.
    }
  }

  private countOf(value: number): number {
    if (value === StreamFilter.UNREAD) {
      return this.summary.unread;
    }
    if (value === StreamFilter.STARRED) {
      return this.summary.starred;
    }
    if (value === StreamFilter.ARCHIVED) {
      return this.summary.archived;
    }
    if (value === StreamFilter.TRASH) {
      return this.summary.trash;
    }
    return this.summary.total;
  }

  private pick(value: number): void {
    this.appState.homeFilter = value;
    this.appState.clearRowSelection();
    this.appState.goPane(Pane.DETAIL);
    this.appState.folderDrawerOpen = false;
  }

  build() {
    Column() {
      Row() {
        Text('智能视图')
          .fontSize(13)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
      }
      .width('100%')
      .height(40)
      .padding({ left: 10 })
      .alignItems(VerticalAlign.Center)

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))

      Column() {
        ForEach(SMART_VIEWS, (option: SmartViewOption) => {
          Row() {
            if (this.appState.homeFilter === option.value) {
              Row()
                .width(2)
                .height(20)
                .backgroundColor($r('app.color.ink'))
                .borderRadius(1)
            }
            SymbolGlyph(option.icon)
              .fontSize(16)
              .fontColor([this.appState.homeFilter === option.value
                ? $r('app.color.ink')
                : $r('app.color.ink_secondary')])
              .margin({ left: LABEL_INSET })
            Text(option.label)
              .fontSize(14)
              .fontColor(this.appState.homeFilter === option.value ? $r('app.color.ink') : $r('app.color.ink_secondary'))
              .fontWeight(this.appState.homeFilter === option.value ? FontWeight.Medium : FontWeight.Normal)
              .margin({ left: 8 })
            Blank()
            Text(`${this.countOf(option.value)}`)
              .fontSize(12)
              .fontColor($r('app.color.ink_tertiary'))
              .margin({ right: 12 })
          }
          .width('100%')
          .height(44)
          .alignItems(VerticalAlign.Center)
          .accessibilityText(`筛选：${option.label}，${this.countOf(option.value)} 条`)
          .focusable(true)
          .backgroundColor(this.pressed === option.value || this.hovered === option.value
            ? $r('app.color.surface_alt')
            : Color.Transparent)
          .onHover((isHover: boolean) => {
            this.hovered = isHover ? option.value : -1;
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.pressed = option.value;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.pressed = -1;
            }
          })
          .onClick(() => {
            this.pick(option.value);
          })
        }, (option: SmartViewOption) => `${option.value}`)
      }
      .width('100%')
    }
    .width('100%')
  }
}
