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
import { SideNav, NAV_ITEMS, NavItem } from '../components/NavigationRail';
import { TagsPage } from './TagsPage';
import { SyncPage } from './SyncPage';
import { SettingsPage } from './SettingsPage';
import { ReadingShell } from '../components/ReadingShell';

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
    if (pane === Pane.DETAIL) {
      return;
    }
    this.navStack.pushPathByName(pane, '');
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

      if (!this.isLarge && this.appState.folderDrawerOpen) {
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
    Row() {
      Column() {
        // Same nav set as the docked rail; label text keeps the home ☰ inset
        // (20vp) so the drawer visually continues from the button.
        ForEach(NAV_ITEMS, (item: NavItem) => {
          Row() {
            if (this.appState.pane === item.pane) {
              Row()
                .width(2)
                .height(20)
                .backgroundColor($r('app.color.ink'))
                .borderRadius(1)
            }
            Text(item.label)
              .fontSize(14)
              .fontColor(this.appState.pane === item.pane ? $r('app.color.ink') : $r('app.color.ink_secondary'))
              .fontWeight(this.appState.pane === item.pane ? FontWeight.Medium : FontWeight.Normal)
              .margin({ left: 20 })
          }
          .width('100%')
          .height(44)
          .alignItems(VerticalAlign.Center)
          .accessibilityText(`打开${item.label}`)
          .focusable(true)
          .onClick(() => {
            this.appState.folderDrawerOpen = false;
            this.openPane(item.pane);
          })
        }, (item: NavItem) => item.pane)

        Divider()
          .strokeWidth(1)
          .color($r('app.color.line'))
          .margin({ top: 4, bottom: 4 })

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
      .width('84%')
      .constraintSize({ maxWidth: 320 })
      .height('100%')
      .backgroundColor($r('app.color.paper'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
      .border({ width: { right: 1 }, color: $r('app.color.line') })
      .clip(false)

      Row()
        .layoutWeight(1)
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .hitTestBehavior(this.dragSession.active ? HitTestMode.None : HitTestMode.Default)
        .onClick(() => {
          this.appState.folderDrawerOpen = false;
        })
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  WideShell() {
    Row() {
      if (this.isLarge) {
        Column() {
          SideNav({
            onSelect: (pane: string) => {
              this.appState.goPane(pane);
            }
          })
        }
        .width(280)
        .height('100%')
      }

      Column() {
        StreamHome({
          isWide: true,
          folderDocked: this.isLarge,
          refreshKey: this.streamRefresh,
          onOpen: (id: string) => this.openDetail(id),
          onCompose: () => this.appState.openInbox(''),
          onComposeWithUrl: (url: string) => this.appState.openInbox(url),
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
        onComposeWithUrl: (url: string) => this.appState.openInbox(url),
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
