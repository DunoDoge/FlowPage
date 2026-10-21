import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { mediaquery } from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { Pane } from '../common/Constants';
import { Bookmark } from '../model/Bookmark';
import { FlowRepository } from '../repository/FlowRepository';
import { StreamHome } from '../components/StreamHome';
import { DetailContent } from '../components/DetailContent';
import { InboxSheet } from '../components/InboxSheet';
import { SideNav } from '../components/NavigationRail';
import { TagsPage } from './TagsPage';
import { SyncPage } from './SyncPage';
import { SettingsPage } from './SettingsPage';

@Entry
@ComponentV2
struct Index {
  @Local appState: AppState = AppState.shared;
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
      const context = getContext(this) as common.UIAbilityContext;
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
      const context = getContext(this) as common.Context;
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
        .width(240)
        .height('100%')
      }

      Column() {
        StreamHome({
          isWide: true,
          isLarge: this.isLarge,
          refreshKey: this.streamRefresh,
          onOpen: (id: string) => this.openDetail(id),
          onCompose: () => this.appState.openInbox('', 0),
          onComposeWithUrl: (url: string) => this.appState.openInbox(url, 0),
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
        isLarge: false,
        refreshKey: this.streamRefresh,
        onOpen: (id: string) => this.openDetail(id),
        onCompose: () => this.appState.openInbox('', 0),
        onComposeWithUrl: (url: string) => this.appState.openInbox(url, 0),
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
