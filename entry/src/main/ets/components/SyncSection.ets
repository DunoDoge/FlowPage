import { AppState } from '../common/AppState';
import { Pane } from '../common/Constants';
import { formatRelative } from '../common/DateUtil';
import { SyncConfigStore } from '../core/sync/SyncConfigStore';

// Rail-only sync summary: configuration presence, last sync time and an
// entry into the sync destination. Refreshes with the library tick so a
// finished sync round updates the relative time immediately.
@ComponentV2
export struct SyncSection {
  @Local appState: AppState = AppState.shared;
  @Local configured: boolean = false;
  @Local lastSync: number = 0;
  @Local loadTick: number = 0;
  @Local hovered: boolean = false;
  @Local pressed: boolean = false;

  aboutToAppear(): void {
    if (this.appState.libraryReady) {
      this.load();
    }
  }

  @Monitor('appState.libraryReady')
  onLibraryReady(): void {
    if (this.appState.libraryReady) {
      this.load();
    }
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    this.load();
  }

  private load(): void {
    this.loadTick = this.loadTick + 1;
    const tick = this.loadTick;
    const context = getContext(this);
    SyncConfigStore.load(context).then((config): void => {
      if (tick !== this.loadTick) {
        return;
      }
      this.configured = config !== undefined;
      this.lastSync = SyncConfigStore.lastSync(context);
    }).catch((): void => {
      if (tick === this.loadTick) {
        this.configured = false;
      }
    });
  }

  private statusText(): string {
    if (!this.configured) {
      return '本地模式，未配置同步';
    }
    if (this.lastSync <= 0) {
      return '已配置，还没有同步过';
    }
    return `上次同步 ${formatRelative(this.lastSync)}`;
  }

  build() {
    Row() {
      SymbolGlyph($r('sys.symbol.arrow_2_circlepath'))
        .fontSize(16)
        .fontColor([$r('app.color.ink_secondary')])
      Text(this.statusText())
        .fontSize(12)
        .fontColor($r('app.color.ink_secondary'))
        .margin({ left: 8 })
        .layoutWeight(1)
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
      Text('去同步')
        .fontSize(12)
        .fontColor($r('app.color.ink'))
        .padding({ left: 8, right: 12 })
    }
    .width('100%')
    .height(44)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 10 })
    .accessibilityText('打开同步页')
    .focusable(true)
    .backgroundColor(this.pressed || this.hovered ? $r('app.color.surface_alt') : Color.Transparent)
    .onHover((isHover: boolean) => {
      this.hovered = isHover;
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.pressed = true;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.pressed = false;
      }
    })
    .onClick(() => {
      this.appState.goPane(Pane.SYNC);
    })
  }
}
