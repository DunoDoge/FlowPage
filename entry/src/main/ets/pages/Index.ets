import { ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { mediaquery } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { Pane } from '../common/Constants';
import { FolderDragSession } from '../common/FolderDragSession';
import { Bookmark } from '../model/Bookmark';
import { FlowRepository } from '../repository/FlowRepository';
import { StreamHome } from '../components/StreamHome';
import { FolderPanel } from '../components/FolderPanel';
import { DetailContent } from '../components/DetailContent';
import { InboxSheet } from '../components/InboxSheet';
import { SideNav } from '../components/NavigationRail';
import { NavList } from '../components/NavList';
import { TagsPage } from './TagsPage';
import { SyncPage } from './SyncPage';
import { SettingsPage } from './SettingsPage';
import { ReadingShell } from '../components/ReadingShell';

// Drawer / docked rail motion. The drawer stays mounted and animates by
// transform so open and close are symmetric; the panel leads and its
// content follows after a short delay on open.
const DRAWER_DURATION: number = 240;
const DRAWER_SLIDE: number = 340;
const DRAWER_CONTENT_DURATION: number = 200;
const DRAWER_CONTENT_DELAY: number = 100;
const RAIL_WIDTH: number = 280;

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
  private mdListener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(width>=700vp)');
  private lgListener: mediaquery.MediaQueryListener = mediaquery.matchMediaSync('(width>=1000vp)');

  aboutToAppear(): void {
    this.isWide = this.mdListener.matches;
    this.isLarge = this.lgListener.matches;
    this.mdListener.on('change', this.onMediumChange);
    this.lgListener.on('change', this.onLargeChange);
    this.restoreTheme();
    this.initRepository();
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

  private openPane(pane: string): void {
    if (this.isWide) {
      this.appState.goPane(pane);
      return;
    }
    // Drawer pane switching is top-level navigation: reset the stack so
    // system back always lands on the home stream instead of the previous
    // pane (same clear-then-push contract as showDetailOnPhone).
    this.navStack.clear(false);
    if (pane !== Pane.DETAIL) {
      this.navStack.pushPathByName(pane, '');
    }
  }

  private closeDetail(): void {
    this.navStack.pop();
  }

  build() {
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

      if (this.appState.showInbox) {
        InboxSheet()
      }

      if (this.appState.toastText.length > 0) {
        Text(this.appState.toastText)
          .fontSize(13)
          .fontColor($r('app.color.inverse_ink'))
          .backgroundColor($r('app.color.ink'))
          .borderRadius(999)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .margin({ bottom: 64 })
      }
    }
    .width('100%')
    .height('100%')
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
          // Same nav block as the docked rail (NavList owns the top inset so
          // the drawer no longer hugs the safe-area edge).
          NavList({
            onSelect: (pane: string) => {
              this.appState.folderDrawerOpen = false;
              this.openPane(pane);
            }
          })

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

      Column() {
        if (this.appState.pane === Pane.TAGS) {
          TagsPage()
        } else if (this.appState.pane === Pane.SYNC) {
          SyncPage()
        } else if (this.appState.pane === Pane.SETTINGS) {
          SettingsPage()
        } else {
          DetailContent({
            bookmarkId: this.appState.selectedId,
            compact: false,
            onRemoved: () => this.appState.clearSelection()
          })
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
      StreamHome({
        isWide: false,
        folderDocked: false,
        refreshKey: this.streamRefresh,
        onOpen: (id: string) => this.openDetail(id),
        onCompose: () => this.appState.openInbox(''),
        onOpenPane: (pane: string) => this.openPane(pane)
      })
    }
    .hideTitleBar(true)
    .mode(NavigationMode.Stack)
    .navDestination(this.PageMap)
    .width('100%')
    .height('100%')
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
    } else if (name === 'tags') {
      NavDestination() {
        TagsPage({
          showBack: true,
          showMenu: !this.isLarge,
          onBack: () => {
            this.navStack.pop();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.paper'))
      .onHidden(() => {
        this.streamRefresh = this.streamRefresh + 1;
      })
    } else if (name === 'sync') {
      NavDestination() {
        SyncPage({
          showBack: true,
          showMenu: !this.isLarge,
          onBack: () => {
            this.navStack.pop();
          }
        })
      }
      .hideTitleBar(true)
      .backgroundColor($r('app.color.paper'))
      .onHidden(() => {
        this.streamRefresh = this.streamRefresh + 1;
      })
    } else if (name === 'settings') {
      NavDestination() {
        SettingsPage({
          showBack: true,
          showMenu: !this.isLarge,
          onBack: () => {
            this.navStack.pop();
          }
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
