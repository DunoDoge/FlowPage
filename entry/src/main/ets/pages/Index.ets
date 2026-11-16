import { ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { mediaquery } from '@kit.ArkUI';
import { HdsTabs, HdsTabsFloatingStyle, HdsBarStyle, hdsMaterial } from '@kit.UIDesignKit';
import { AppState } from '../common/AppState';
import { NAV_ITEMS, Pane } from '../common/Constants';
import { showStrip, STRIP_HEIGHT_VP } from '../common/WindowChrome';
import { FolderDragSession } from '../common/FolderDragSession';
import { Bookmark } from '../model/Bookmark';
import { FlowRepository } from '../repository/FlowRepository';
import { StreamHome } from '../components/StreamHome';
import { FolderPanel } from '../components/FolderPanel';
import { SmartViews } from '../components/SmartViews';
import { DetailContent } from '../components/DetailContent';
import { InboxSheet } from '../components/InboxSheet';
import { SideNav } from '../components/NavigationRail';
import { NavList } from '../components/NavList';
import { WindowTitleBar } from '../components/WindowTitleBar';
import { TagsPage } from './TagsPage';
import { SyncPage } from './SyncPage';
import { SettingsPage } from './SettingsPage';
import { ReadingShell } from '../components/ReadingShell';
import { FolderPickerPage } from '../components/FolderPickerPage';

// Drawer / docked rail motion. The drawer stays mounted and animates by
// transform so open and close are symmetric; the panel leads and its
// content follows after a short delay on open.
const DRAWER_DURATION: number = 240;
const DRAWER_SLIDE: number = 340;
const DRAWER_CONTENT_DURATION: number = 200;
const DRAWER_CONTENT_DELAY: number = 100;
const RAIL_WIDTH: number = 280;
// One-way pane entrance (design D11): a cold-mounted destination rises
// this far while fading in, reusing the drawer duration and curve.
const PANE_ENTRANCE_OFFSET: number = 12;
// Persistent toast floats in with the same rise-only vocabulary.
const TOAST_MOTION_MS: number = 180;

// Floating tab bar (<1000vp), hosted by HdsTabs from @kit.UIDesignKit. The
// bar keeps the 56vp system default height for custom builders; the content
// reserve covers the bar row (tab bar + side-by-side mini bar) plus
// breathing room. Material and bottom margin live in tabFloatingStyle().
const TAB_BAR_HEIGHT: number = 56;
const TAB_BOTTOM_RESERVE: number = 88;

@Builder
function paneEntranceEmpty() {
  Column() {
  }
}

// One-way entrance for destination panes (design D11): every switch fades
// the incoming pane in and rises it slightly. State-driven animation only --
// TransitionEffect attached to conditionally inserted content was measured
// not to animate (drawer lesson). Two trigger paths: first mount flips
// appeared on appear (implicit animation), and re-activation replays it via
// an explicit animateTo because onAppear never fires again while mounted.
@ComponentV2
struct PaneEntrance {
  @Param active: boolean = true;
  @Param animate: boolean = true;
  @Local appeared: boolean = false;
  @BuilderParam content: () => void = paneEntranceEmpty;

  aboutToAppear(): void {
    // Panes that are live at startup (>=1000vp right column) skip the
    // entrance: the transition belongs to switches, not first layout.
    if (!this.animate) {
      this.appeared = true;
    }
  }

  @Monitor('active')
  onActiveChange(): void {
    if (!this.active) {
      // Reset while offstage so the next activation replays the entrance.
      this.appeared = false;
    } else if (!this.appeared) {
      // Warm switch: the mount-time onAppear will not fire again, so the
      // replay runs through an explicit animation.
      this.getUIContext().animateTo({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn }, () => {
        this.appeared = true;
      });
    }
  }

  build() {
    Column() {
      this.content()
    }
    .width('100%')
    .height('100%')
    .opacity(this.appeared ? 1 : 0)
    .translate({ y: this.appeared ? 0 : PANE_ENTRANCE_OFFSET })
    .animation({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn })
    .onAppear(() => {
      if (!this.appeared) {
        this.appeared = true;
      }
    })
  }
}

// Library entry hosted by the HdsTabs mini bar (design D12): icon only --
// real-device feedback dropped the "资料库" label. The glyph mirrors the
// drawer STATE (open -> open_sidebar, closed -> close_sidebar), the same
// convention as the docked ☰ (navigation-shell spec); tapping toggles the
// drawer, and while it is open the drawer scrim owns the tap layer.
@ComponentV2
struct MiniBarEntry {
  @Local appState: AppState = AppState.shared;
  @Local hovered: boolean = false;
  @Local pressed: boolean = false;

  build() {
    Row() {
      SymbolGlyph(this.appState.folderDrawerOpen
        ? $r('sys.symbol.open_sidebar')
        : $r('sys.symbol.close_sidebar'))
        .fontSize(26)
        .fontColor([$r('app.color.ink_secondary')])
    }
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(VerticalAlign.Center)
    .padding({ left: 14, right: 14 })
    .constraintSize({ minHeight: 44, minWidth: 44 })
    .backgroundColor(this.hovered || this.pressed ? $r('app.color.surface_alt') : Color.Transparent)
    .borderRadius(16)
    .accessibilityText('资料库')
    .accessibilityDescription(this.appState.folderDrawerOpen
      ? '收起资料库抽屉'
      : '打开资料库抽屉')
    .focusable(true)
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
      this.appState.folderDrawerOpen = !this.appState.folderDrawerOpen;
    })
  }
}

@Entry
@ComponentV2
struct Index {
  @Local appState: AppState = AppState.shared;
  @Local dragSession: FolderDragSession = FolderDragSession.shared;
  @Local isWide: boolean = false;
  @Local isLarge: boolean = false;
  @Local navStack: NavPathStack = new NavPathStack();
  @Local ready: boolean = false;
  @Local streamRefresh: number = 0;
  // Tabs state: pane is the single source of truth (D4); tabIndex is the
  // shadow index fed to the Tabs component, rewritten by the pane monitor.
  @Local activeTabIndex: number = 0;
  // Lazy mount gate (design risk mitigation): tab pages build on first
  // activation and then stay alive.
  @Local visitedTabs: boolean[] = [true, false, false, false];
  // Startup-live panes (>=1000vp right column, <1000vp home tab) must
  // appear without the entrance transition; any pane switch afterwards
  // re-enables it.
  @Local paneSwitchedOnce: boolean = false;
  @Local tabHovered: number = -1;
  @Local tabPressed: number = -1;
  private mdListener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(width>=700vp)');
  private lgListener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(width>=1000vp)');

  aboutToAppear(): void {
    this.isWide = this.mdListener.matches;
    this.isLarge = this.lgListener.matches;
    this.mdListener.on('change', this.onMediumChange);
    this.lgListener.on('change', this.onLargeChange);
    this.restoreTheme();
    this.initRepository();
    // Pane may have been routed before attach (cold-start import handoff);
    // @Monitor does not replay pre-attach changes, so sync once here.
    const initialPane = this.paneIndex(this.appState.pane);
    this.markTabVisited(initialPane);
    this.activeTabIndex = initialPane;
    if (this.appState.hasPendingRoute()) {
      this.appState.consumeRoute();
      if (!this.isWide) {
        this.showDetailOnPhone();
      }
    }
  }

  aboutToDisappear(): void {
    this.mdListener.off('change', this.onMediumChange);
    this.lgListener.off('change', this.onLargeChange);
  }

  onBackPress(): boolean {
    if (this.appState.folderDrawerOpen) {
      this.appState.folderDrawerOpen = false;
      return true;
    }
    // Tab destinations never stack: with an empty nav stack, back returns
    // to the stream tab instead of leaving the app.
    if (!this.isLarge && this.navStack.getAllPathName().length === 0 && this.appState.pane !== Pane.DETAIL) {
      this.appState.goPane(Pane.DETAIL);
      return true;
    }
    return false;
  }

  @Monitor('appState.routeTick')
  onRouteRequested(): void {
    const id = this.appState.consumeRoute();
    if (id.length === 0) {
      return;
    }
    if (this.isWide) {
      return;
    }
    this.showDetailOnPhone();
  }

  @Monitor('appState.pane')
  onPaneChanged(): void {
    this.paneSwitchedOnce = true;
    const next = this.paneIndex(this.appState.pane);
    this.markTabVisited(next);
    if (next !== this.activeTabIndex) {
      this.activeTabIndex = next;
    }
  }

  private paneIndex(pane: string): number {
    for (let i = 0; i < NAV_ITEMS.length; i++) {
      if (NAV_ITEMS[i].pane === pane) {
        return i;
      }
    }
    return 0;
  }

  private paneAt(index: number): string {
    if (index < 0 || index >= NAV_ITEMS.length) {
      return Pane.DETAIL;
    }
    return NAV_ITEMS[index].pane;
  }

  private markTabVisited(index: number): void {
    if (this.visitedTabs[index]) {
      return;
    }
    const next = this.visitedTabs.slice();
    next[index] = true;
    this.visitedTabs = next;
  }

  private showDetailOnPhone(): void {
    const names = this.navStack.getAllPathName();
    if (names.length > 0 && names[names.length - 1] === 'detail') {
      return;
    }
    if (names.length > 0) {
      this.navStack.clear(false);
    }
    this.navStack.pushPathByName('detail', '');
  }

  private onMediumChange = (result: mediaquery.MediaQueryResult): void => {
    this.isWide = result.matches;
  };

  private onLargeChange = (result: mediaquery.MediaQueryResult): void => {
    this.isLarge = result.matches;
  };

  private restoreTheme(): void {
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: 'flowpage_settings' });
      const stored = store.getSync('theme_mode', 'system');
      const mode = typeof stored === 'string' ? stored : 'system';
      const context = getContext(this);
      if (mode === 'light') {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      }
    } catch (error) {
      return;
    }
  }

  private async initRepository(): Promise<void> {
    try {
      const context = getContext(this);
      await FlowRepository.get().init(context);
      // libraryReady first: drawer-mounted library blocks (mounted before
      // this point) reload off the flag, and shell components that mount
      // right after ready=true read it in aboutToAppear.
      this.appState.libraryReady = true;
      this.ready = true;
      if (this.isWide && this.appState.selectedId.length === 0) {
        const list: Bookmark[] = await FlowRepository.get().listAll(false);
        if (list.length > 0) {
          this.appState.select(list[0].id);
        }
      }
    } catch (error) {
      AppState.shared.toast('本地数据没有打开');
    }
  }

  private openDetail(id: string): void {
    this.appState.openBookmark(id);
  }

  // Destinations are tabs below 1000vp: switching writes the pane only,
  // never the nav stack (which exists for detail pages alone).
  private openPane(pane: string): void {
    this.appState.goPane(pane);
  }

  private closeDetail(): void {
    this.navStack.pop();
  }

  // Batch selection swaps the phone tab bar for the batch action bar.
  private tabsBarHidden(): boolean {
    return !this.isWide && this.appState.selectionMode;
  }

  private phoneTabReserve(): number {
    return this.tabsBarHidden() ? 0 : TAB_BOTTOM_RESERVE;
  }

  private onTabChanged(index: number): void {
    this.markTabVisited(index);
    this.appState.goPane(this.paneAt(index));
  }

  // Material scope is the bar backplanes only (design D9): ADAPTIVE type and
  // level follow the system material policy per device (PC/2in1 included),
  // so no getSystemMaterialTypes() query is needed. barBottomMargin must
  // stay 0: the bar hugs the top edge of the bottom nav avoidance area,
  // and the system default spacing is visibly too high on real devices.
  // Built per call so the mini bar builder closes over this shell.
  private tabFloatingStyle(): HdsTabsFloatingStyle {
    return {
      barBottomMargin: 0,
      systemMaterialEffect: {
        materialType: hdsMaterial.MaterialType.ADAPTIVE,
        materialLevel: hdsMaterial.MaterialLevel.ADAPTIVE
      },
      miniBar: {
        miniBarBuilder: (): void => {
          this.MiniBarHost();
        },
        // Foldable-width hosts (>600vp) boot the mini bar in EXPAND style
        // and the segmented width balloons toward the 328vp cap. The entry
        // is a single glyph: request COLLAPSE and pin every expanded width
        // tier to the bar height so the button stays a 56x56 circle on
        // every breakpoint (the style init param only applies <600vp, the
        // width pin covers the rest).
        miniBarStyle: HdsBarStyle.COLLAPSE,
        miniBarWidth: {
          smallWidth: TAB_BAR_HEIGHT,
          mediumWidth: TAB_BAR_HEIGHT,
          largeWidth: TAB_BAR_HEIGHT
        }
      }
    };
  }

  @Builder
  MiniBarHost() {
    MiniBarEntry()
  }

  build() {
    Column() {
      // Persistent shell: the strip toggles as a child instead of swapping
      // root branches, so floating/fullscreen/maximize switches never
      // rebuild the Stack subtree (scroll, keyword, drawer state survive).
      if (this.stripVisible()) {
        WindowTitleBar({ isLarge: this.isLarge })
      }
      Stack({ alignContent: Alignment.Bottom }) {
        if (!this.ready) {
          Column() {
            Text('流笺')
              .fontSize(12)
              .fontColor($r('app.color.ink_tertiary'))
              .letterSpacing(2)
          }
          .width('100%')
          .height('100%')
          .justifyContent(FlexAlign.Center)
        } else if (this.isWide) {
          this.WideShell()
        } else {
          this.PhoneShell()
        }

        if (!this.isLarge) {
          this.FolderDrawer()
        }

        // Persistently mounted (drawer lesson): the sheet animates by
        // transform through its internal phase machine, so both the exit
        // animation and the reopen reset are available. Breakpoints come
        // from the shared Index listeners (no local mediaquery rebuild).
        InboxSheet({ isWide: this.isWide, isLarge: this.isLarge })

        // Toast stays mounted and fades in/out with the intent flag. The
        // container never intercepts touches; only an action chip (undo)
        // opts back into hit-testing -- HitTestMode.None disables the node
        // itself, children stay reachable.
        Row({ space: 10 }) {
          Text(this.appState.toastText)
            .fontSize(13)
            .fontColor($r('app.color.inverse_ink'))
            .maxLines(2)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
          if (this.appState.toastAction !== undefined) {
            Text(this.appState.toastAction.label)
              .fontSize(12)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
              .backgroundColor($r('app.color.inverse_ink'))
              .borderRadius(999)
              .padding({ left: 12, right: 12, top: 5, bottom: 5 })
              .responseRegion({ x: -6, y: -8, width: 76, height: 44 })
              .accessibilityText(this.appState.toastAction.label)
              .hitTestBehavior(HitTestMode.Default)
              .onClick(() => {
                this.appState.runToastAction();
              })
          }
        }
        .backgroundColor($r('app.color.ink'))
        .borderRadius(999)
        .padding({ left: 18, right: 18, top: 9, bottom: 9 })
        .margin({ bottom: 64 })
        .opacity(this.appState.toastText.length > 0 ? 1 : 0)
        .translate({ y: this.appState.toastText.length > 0 ? 0 : 8 })
        .animation({ duration: TOAST_MOTION_MS, curve: Curve.FastOutSlowIn })
        .hitTestBehavior(HitTestMode.None)
      }
      .width('100%')
      .height(this.rootStackHeight())
      .backgroundColor($r('app.color.paper'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .bindContentCover(this.appState.readingOpen, this.ReadingCover(), {
        enableSafeArea: true,
        onWillDismiss: (action: DismissContentCoverAction) => {
          if (this.appState.readingCanGoBack && action.reason === DismissReason.PRESS_BACK) {
            this.appState.requestReadingBack();
          } else {
            action.dismiss();
          }
        },
        onDisappear: () => {
          this.appState.closeReading();
        }
      })
    }
    .width('100%')
    .height('100%')
    // Second full-screen layer on the root column (one bindContentCover per
    // node): the folder target page. Leaving without the confirm bar writes
    // nothing (zero-write dismiss).
    .bindContentCover(this.appState.folderPickOpen, this.FolderPickCover(), {
      enableSafeArea: true,
      onWillDismiss: (action: DismissContentCoverAction) => {
        action.dismiss();
      },
      onDisappear: () => {
        this.appState.folderPickOpen = false;
      }
    })
  }

  private stripVisible(): boolean {
    return showStrip(this.appState.freeWindow, this.appState.windowStatus);
  }

  private rootStackHeight(): string {
    return this.stripVisible() ? `calc(100% - ${STRIP_HEIGHT_VP}vp)` : '100%';
  }

  @Builder
  ReadingCover() {
    ReadingShell({
      compact: !this.isWide,
      onClose: () => {
        this.appState.closeReading();
      }
    })
  }

  @Builder
  FolderPickCover() {
    FolderPickerPage({ bookmark: this.appState.folderPickBookmark })
  }

  @Builder
  FolderDrawer() {
    Stack({ alignContent: Alignment.TopStart }) {
      // Full-bleed scrim sits under the sliding panel so the dimmed area is
      // visible across the whole screen while the panel travels.
      Row()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .hitTestBehavior(this.appState.folderDrawerOpen && !this.dragSession.active
          ? HitTestMode.Default
          : HitTestMode.None)
        .opacity(this.appState.folderDrawerOpen ? 1 : 0)
        .animation({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn })
        .onClick(() => {
          this.appState.folderDrawerOpen = false;
        })

      Column() {
        Column() {
          // The drawer is library-only below 1000vp: NavList contributes
          // the shared top inset, destinations live in the tab bar. The
          // library blocks defer their first query until this drawer opens
          // (cold start stays free for the first stream page).
          NavList({ showItems: false })

          SmartViews({ deferUntilDrawerOpen: true })

          Column() {
            FolderPanel({
              isWide: false,
              docked: false
            })
          }
          .width('100%')
          .layoutWeight(1)
          .clip(false)
        }
        .width('100%')
        .height('100%')
        .translate({ x: this.appState.folderDrawerOpen ? 0 : -16 })
        .opacity(this.appState.folderDrawerOpen ? 1 : 0)
        .animation({
          duration: DRAWER_CONTENT_DURATION,
          delay: this.appState.folderDrawerOpen ? DRAWER_CONTENT_DELAY : 0,
          curve: Curve.FastOutSlowIn
        })
      }
      .width('84%')
      .constraintSize({ maxWidth: 320 })
      .height('100%')
      .backgroundColor($r('app.color.paper'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .border({ width: { right: 1 }, color: $r('app.color.line') })
      .clip(false)
      .enabled(this.appState.folderDrawerOpen)
      .hitTestBehavior(this.appState.folderDrawerOpen ? HitTestMode.Default : HitTestMode.None)
      .translate({ x: this.appState.folderDrawerOpen ? 0 : -DRAWER_SLIDE })
      .animation({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn })
    }
    .width('100%')
    .height('100%')
    .hitTestBehavior(this.appState.folderDrawerOpen ? HitTestMode.Default : HitTestMode.None)
    .accessibilityLevel(this.appState.folderDrawerOpen ? 'auto' : 'no-hide-descendants')
  }

  @Builder
  WideShell() {
    Row() {
      if (this.isLarge) {
        Column() {
          Column() {
            SideNav({
              onSelect: (pane: string) => {
                this.appState.goPane(pane);
              }
            })
          }
          .width(RAIL_WIDTH)
          .height('100%')
          .translate({ x: this.appState.sideNavOpen ? 0 : -RAIL_WIDTH })
          .animation({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn })
        }
        .width(this.appState.sideNavOpen ? RAIL_WIDTH : 0)
        .height('100%')
        .clip(true)
        .enabled(this.appState.sideNavOpen)
        .accessibilityLevel(this.appState.sideNavOpen ? 'auto' : 'no-hide-descendants')
        .animation({ duration: DRAWER_DURATION, curve: Curve.FastOutSlowIn })
      }

      Column() {
        StreamHome({
          isWide: true,
          folderDocked: this.isLarge,
          refreshKey: this.streamRefresh,
          onOpen: (id: string) => this.openDetail(id),
          onCompose: () => this.appState.openInbox(''),
          onOpenPane: (pane: string) => this.openPane(pane)
        })
      }
      .width(this.isLarge ? 380 : 340)
      .height('100%')
      // 700-999vp only: the stream list extends to the screen edge like the
      // tab-hosted right column. At >=1000vp the original immersive rule
      // keeps content inside the safe area (no floating bar to underlap).
      .expandSafeArea(this.isLarge ? [] : [SafeAreaType.SYSTEM], this.isLarge ? [] : [SafeAreaEdge.BOTTOM])

      Column() {
        if (this.isLarge) {
          if (this.appState.pane === Pane.TAGS) {
            PaneEntrance({ animate: this.paneSwitchedOnce }) {
              TagsPage()
            }
          } else if (this.appState.pane === Pane.SYNC) {
            PaneEntrance({ animate: this.paneSwitchedOnce }) {
              SyncPage()
            }
          } else if (this.appState.pane === Pane.SETTINGS) {
            PaneEntrance({ animate: this.paneSwitchedOnce }) {
              SettingsPage()
            }
          } else {
            PaneEntrance({ animate: this.paneSwitchedOnce }) {
              DetailContent({
                bookmarkId: this.appState.selectedId,
                compact: false,
                onRemoved: () => this.appState.clearSelection()
              })
            }
          }
        } else {
          // 700–999vp: tabs wrap the right pane only, so the left stream
          // column keeps its scroll and selection across switches.
          HdsTabs({ index: this.activeTabIndex, barPosition: BarPosition.End }) {
            TabContent() {
              // Same as the phone home tab: startup-live pane without the
              // first-screen entrance, replayed on every return switch.
              PaneEntrance({ active: this.activeTabIndex === 0, animate: this.paneSwitchedOnce }) {
                DetailContent({
                  bookmarkId: this.appState.selectedId,
                  compact: false,
                  bottomReserve: TAB_BOTTOM_RESERVE,
                  onRemoved: () => this.appState.clearSelection()
                })
              }
            }
            .tabBar(this.TabBarItem(0))

            TabContent() {
              if (this.visitedTabs[1]) {
                PaneEntrance({ active: this.activeTabIndex === 1 }) {
                  TagsPage({ bottomReserve: TAB_BOTTOM_RESERVE })
                }
              }
            }
            .tabBar(this.TabBarItem(1))

            TabContent() {
              if (this.visitedTabs[2]) {
                PaneEntrance({ active: this.activeTabIndex === 2 }) {
                  SyncPage({ bottomReserve: TAB_BOTTOM_RESERVE })
                }
              }
            }
            .tabBar(this.TabBarItem(2))

            TabContent() {
              if (this.visitedTabs[3]) {
                PaneEntrance({ active: this.activeTabIndex === 3 }) {
                  SettingsPage({ bottomReserve: TAB_BOTTOM_RESERVE })
                }
              }
            }
            .tabBar(this.TabBarItem(3))
          }
          .barMode(BarMode.Fixed)
          .vertical(false)
          .scrollable(false)
          // The default 300ms horizontal slide fights the D11 entrance and
          // breaks the instant warm-switch contract; keep cuts hard so the
          // one-way entrance is the only motion.
          .animationDuration(0)
          .barOverlap(true)
          .barHeight(TAB_BAR_HEIGHT)
          .barFloatingStyle(this.tabFloatingStyle())
          .onChange((index: number) => {
            this.onTabChanged(index);
          })
          .width('100%')
          .height('100%')
          // Extend into the bottom safe area so the stream scrolls under
          // the floating bar to the screen edge.
          .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
        }
      }
      .layoutWeight(1)
      .height('100%')
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  PhoneShell() {
    Navigation(this.navStack) {
      HdsTabs({ index: this.activeTabIndex, barPosition: BarPosition.End }) {
        TabContent() {
          // The home tab is a switch target too: it is live at startup
          // (animate skips the first-screen entrance), and every later
          // return replays the D11 entrance like tabs 1-3.
          PaneEntrance({ active: this.activeTabIndex === 0, animate: this.paneSwitchedOnce }) {
            StreamHome({
              isWide: false,
              folderDocked: false,
              refreshKey: this.streamRefresh,
              bottomReserve: this.phoneTabReserve(),
              onOpen: (id: string) => this.openDetail(id),
              onCompose: () => this.appState.openInbox(''),
              onOpenPane: (pane: string) => this.openPane(pane)
            })
          }
        }
        .tabBar(this.TabBarItem(0))

        TabContent() {
          if (this.visitedTabs[1]) {
            PaneEntrance({ active: this.activeTabIndex === 1 }) {
              TagsPage({ bottomReserve: this.phoneTabReserve() })
            }
          }
        }
        .tabBar(this.TabBarItem(1))

        TabContent() {
          if (this.visitedTabs[2]) {
            PaneEntrance({ active: this.activeTabIndex === 2 }) {
              SyncPage({ bottomReserve: this.phoneTabReserve() })
            }
          }
        }
        .tabBar(this.TabBarItem(2))

        TabContent() {
          if (this.visitedTabs[3]) {
            PaneEntrance({ active: this.activeTabIndex === 3 }) {
              SettingsPage({ bottomReserve: this.phoneTabReserve() })
            }
          }
        }
        .tabBar(this.TabBarItem(3))
      }
      .barMode(BarMode.Fixed)
      .vertical(false)
      .scrollable(false)
      // Same as the wide shell: kill the default slide, entrance only.
      .animationDuration(0)
      .barOverlap(true)
      // Batch mode keeps the proven collapse: barHeight 0 plus dropping the
      // floating style (which owns the mini bar) hides bar and mini bar
      // together. applyHideAnimation targets transient scroll/click scenes,
      // not a persistent selection mode (design D8 revision fallback).
      .barHeight(this.tabsBarHidden() ? 0 : TAB_BAR_HEIGHT)
      .barFloatingStyle(this.tabsBarHidden() ? undefined : this.tabFloatingStyle())
      .onChange((index: number) => {
        this.onTabChanged(index);
      })
      .width('100%')
      .height('100%')
      // Same extension as the wide shell: content reaches the screen edge.
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.PageMap)
    .width('100%')
    .height('100%')
  }

  // Custom tab item: SymbolGlyph + label from the shared NAV_ITEMS
  // definition; the floating style draws the capsule on the selected item,
  // so the manual surface_alt feedback skips it to stay uncovered.
  @Builder
  TabBarItem(index: number) {
    Column({ space: 3 }) {
      SymbolGlyph(NAV_ITEMS[index].icon)
        .fontSize(22)
        .fontColor([this.activeTabIndex === index ? $r('app.color.ink') : $r('app.color.ink_secondary')])
      Text(NAV_ITEMS[index].label)
        .fontSize(11)
        .fontColor(this.activeTabIndex === index ? $r('app.color.ink') : $r('app.color.ink_secondary'))
        .fontWeight(this.activeTabIndex === index ? FontWeight.Medium : FontWeight.Normal)
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .alignItems(HorizontalAlign.Center)
    .accessibilityText(NAV_ITEMS[index].label)
    .accessibilitySelected(this.activeTabIndex === index)
    .focusable(true)
    .backgroundColor(this.activeTabIndex !== index && (this.tabPressed === index || this.tabHovered === index)
      ? $r('app.color.surface_alt')
      : Color.Transparent)
    .borderRadius(16)
    .onHover((isHover: boolean) => {
      this.tabHovered = isHover ? index : -1;
    })
    .onTouch((event: TouchEvent) => {
      if (event.type === TouchType.Down) {
        this.tabPressed = index;
      } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
        this.tabPressed = -1;
      }
    })
  }

  @Builder
  PageMap(name: string) {
    if (name === 'detail') {
      NavDestination() {
        DetailContent({
          bookmarkId: this.appState.selectedId,
          showBack: true,
          compact: true,
          onBack: () => this.closeDetail(),
          onRemoved: () => this.closeDetail()
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.paper'))
      .onHidden(() => {
        this.streamRefresh = this.streamRefresh + 1;
      })
    }
  }
}
