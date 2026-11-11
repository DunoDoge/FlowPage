import { window } from '@kit.ArkUI';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { AppState } from '../common/AppState';
import { platformFailure } from '../common/PlatformError';
import { STRIP_HEIGHT_VP, AVOIDANCE_MARGIN_VP, sunkButtonAvoidance } from '../common/WindowChrome';
import { SubtitleStatus } from './SubtitleStatus';

const DOMAIN = 0x0000;

// Freeform title strip (design window-chrome D2/D4/D6): 40vp paper band at
// the window top. >=1000vp carries the docked-rail hamburger on the left and
// the stream count on the right; every breakpoint gets the drag surface and
// the sunk-button avoidance. Default decor drag/double-click is disabled
// app-wide (EntryAbility), so this strip owns the move gesture.
@ComponentV2
export struct WindowTitleBar {
  @Param isLarge: boolean = false;
  @Local appState: AppState = AppState.shared;
  // Manual hover/press feedback: stateStyles sticks on plain glyph surfaces.
  @Local hamburgerHovered: boolean = false;
  @Local hamburgerPressed: boolean = false;
  private dragStarted: boolean = false;

  private async mainWindow(): Promise<window.Window | undefined> {
    const context = this.getUIContext().getHostContext();
    if (context === undefined) {
      return undefined;
    }
    try {
      return await window.getLastWindow(context);
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'getLastWindow failed code=%{public}d', platformFailure(error).code);
      return undefined;
    }
  }

  // Move (finger/stylus/mouse) hands the drag to the window manager once per
  // contact; Up/Cancel re-arms so the next press can drag again.
  private onDragTouch(event: TouchEvent): void {
    if (event.type === TouchType.Move && !this.dragStarted) {
      this.dragStarted = true;
      this.moveWindow();
    } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
      this.dragStarted = false;
    }
  }

  private async moveWindow(): Promise<void> {
    const win = await this.mainWindow();
    if (win === undefined) {
      return;
    }
    try {
      await win.startMoving();
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'startMoving failed code=%{public}d', platformFailure(error).code);
    }
  }

  private async toggleMaximize(): Promise<void> {
    const win = await this.mainWindow();
    if (win === undefined) {
      return;
    }
    try {
      if (this.appState.windowStatus === window.WindowStatusType.MAXIMIZE) {
        await win.recover();
      } else {
        // Default presentation maps to FULL_SCREEN on device (status=1,
        // no buttons, strip predicate false -- unrecoverable via UI).
        // EXIT_IMMERSIVE keeps the PC-style maximize (status=MAXIMIZE).
        await win.maximize(window.MaximizePresentation.EXIT_IMMERSIVE);
      }
    } catch (error) {
      hilog.warn(DOMAIN, 'flowpage', 'toggle maximize failed code=%{public}d', platformFailure(error).code);
    }
  }

  private avoidance(): number {
    return sunkButtonAvoidance(this.appState.freeWindow, this.appState.titleButtonRight,
      this.appState.titleButtonWidth, AVOIDANCE_MARGIN_VP);
  }

  build() {
    Row() {
      if (this.isLarge) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph(this.appState.sideNavOpen
            ? $r('sys.symbol.open_sidebar')
            : $r('sys.symbol.close_sidebar'))
            .fontSize(20)
            .fontColor([$r('app.color.ink_secondary')])
        }
        .width(44)
        .height(STRIP_HEIGHT_VP)
        .backgroundColor(this.hamburgerPressed || this.hamburgerHovered
          ? $r('app.color.surface_alt')
          : Color.Transparent)
        .borderRadius(8)
        .responseRegion({ x: 0, y: 0, width: 44, height: 44 })
        .accessibilityText(this.appState.sideNavOpen ? '收起侧边栏' : '展开侧边栏')
        .focusable(true)
        .onHover((isHover: boolean) => {
          this.hamburgerHovered = isHover;
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.hamburgerPressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.hamburgerPressed = false;
          }
        })
        .onClick(() => {
          this.appState.sideNavOpen = !this.appState.sideNavOpen;
        })
      }
      Blank()
        .onTouch((event: TouchEvent) => {
          this.onDragTouch(event);
        })
        .gesture(TapGesture({ count: 2 }).onAction(() => {
          this.toggleMaximize();
        }))
      if (this.isLarge) {
        SubtitleStatus({
          loading: this.appState.streamLoading,
          total: this.appState.streamTotal,
          todayCount: this.appState.streamTodayCount
        })
      }
    }
    .width('100%')
    .height(STRIP_HEIGHT_VP)
    .padding({ right: this.avoidance() })
    .backgroundColor($r('app.color.paper'))
  }
}
