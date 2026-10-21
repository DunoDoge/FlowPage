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
  @Trace sheetMode: number = 0;
  @Trace editingId: string = '';
  private routePending: boolean = false;

  notifyChanged(): void {
    this.refreshTick = this.refreshTick + 1;
  }

  openInbox(url: string, mode: number): void {
    this.inboxUrl = url;
    this.sheetMode = mode;
    this.showInbox = true;
  }

  closeInbox(): void {
    this.showInbox = false;
    this.inboxUrl = '';
    this.editingId = '';
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
