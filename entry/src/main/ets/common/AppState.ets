import { common } from '@kit.AbilityKit';
import { Pane } from './Constants';

@ObservedV2
export class AppState {
  private static instance: AppState | undefined = undefined;

  static get shared(): AppState {
    if (AppState.instance === undefined) {
      AppState.instance = new AppState();
    }
    return AppState.instance;
  }

  @Trace selectedId: string = '';
  @Trace pane: string = Pane.DETAIL;
  @Trace routeTick: number = 0;
  @Trace routeId: string = '';
  @Trace refreshTick: number = 0;
  @Trace toastText: string = '';
  @Trace tagFilter: string = '';
  @Trace inboxUrl: string = '';
  @Trace showInbox: boolean = false;
  // Ability contexts are published once at startup so pages never cast getContext().
  abilityContext: common.UIAbilityContext | undefined = undefined;
  shareContext: common.UIExtensionContext | undefined = undefined;
  private routePending: boolean = false;

  notifyChanged(): void {
    this.refreshTick = this.refreshTick + 1;
  }

  openInbox(url: string): void {
    this.inboxUrl = url;
    this.showInbox = true;
  }

  closeInbox(): void {
    this.showInbox = false;
    this.inboxUrl = '';
  }

  select(id: string): void {
    this.selectedId = id;
    this.pane = Pane.DETAIL;
  }

  openBookmark(id: string): void {
    this.selectedId = id;
    this.pane = Pane.DETAIL;
    this.routeId = id;
    this.routePending = true;
    this.routeTick = this.routeTick + 1;
  }

  hasPendingRoute(): boolean {
    return this.routePending;
  }

  consumeRoute(): string {
    if (!this.routePending) {
      return '';
    }
    this.routePending = false;
    return this.routeId;
  }

  goPane(pane: string): void {
    this.pane = pane;
  }

  clearSelection(): void {
    this.selectedId = '';
  }

  toast(text: string): void {
    this.toastText = text;
    setTimeout(() => {
      if (this.toastText === text) {
        this.toastText = '';
      }
    }, 2400);
  }
}
