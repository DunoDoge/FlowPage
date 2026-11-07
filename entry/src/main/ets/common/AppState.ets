import { common } from '@kit.AbilityKit';
import { Pane } from './Constants';
import { ReadingSeed } from '../model/ReadingEntry';

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
  @Trace folderFilter: string = '';
  // Home folder tree session state, hoisted so a phone detail round-trip
  // (NavDestination cover) or a wide rebuild never resets expansion.
  @Trace folderDrawerOpen: boolean = false;
  // >=1000vp: the docked rail is expanded by default; the home ☰ toggles it.
  @Trace sideNavOpen: boolean = true;
  @Trace folderPanelExpandedIds: string[] = [];
  folderPanelScrollY: number = 0;
  // The tree lives in the left rail while bookmark rows live in the stream
  // column, so both components share one selection set from here.
  @Trace selectionMode: boolean = false;
  @Trace selectedBookmarkIds: string[] = [];
  @Trace selectedFolderIds: string[] = [];
  @Trace homeFilter: number = 0;
  @Trace inboxUrl: string = '';
  @Trace showInbox: boolean = false;
  @Trace readingOpen: boolean = false;
  @Trace readingTick: number = 0;
  @Trace readingBackTick: number = 0;
  @Trace readingCanGoBack: boolean = false;
  readingSeed: ReadingSeed = new ReadingSeed();
  // Ability contexts are published once at startup so pages never cast getContext().
  abilityContext: common.UIAbilityContext | undefined = undefined;
  shareContext: common.UIExtensionContext | undefined = undefined;
  private routePending: boolean = false;

  notifyChanged(): void {
    this.refreshTick = this.refreshTick + 1;
  }

  openReading(seed: ReadingSeed): void {
    this.readingSeed = seed;
    this.readingCanGoBack = false;
    this.readingTick = this.readingTick + 1;
    this.readingOpen = true;
  }

  closeReading(): void {
    this.readingOpen = false;
    this.readingCanGoBack = false;
    this.readingSeed = new ReadingSeed();
  }

  requestReadingBack(): void {
    this.readingBackTick = this.readingBackTick + 1;
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

  rowSelectionCount(): number {
    return this.selectedBookmarkIds.length + this.selectedFolderIds.length;
  }

  isBookmarkSelected(id: string): boolean {
    return this.selectedBookmarkIds.indexOf(id) >= 0;
  }

  isFolderSelected(id: string): boolean {
    return this.selectedFolderIds.indexOf(id) >= 0;
  }

  toggleBookmarkSelected(id: string): void {
    const next = this.selectedBookmarkIds.slice();
    const index = next.indexOf(id);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(id);
    }
    this.selectedBookmarkIds = next;
    this.selectionMode = this.rowSelectionCount() > 0;
  }

  toggleFolderSelected(id: string): void {
    const next = this.selectedFolderIds.slice();
    const index = next.indexOf(id);
    if (index >= 0) {
      next.splice(index, 1);
    } else {
      next.push(id);
    }
    this.selectedFolderIds = next;
    this.selectionMode = this.rowSelectionCount() > 0;
  }

  beginRowSelection(id: string): void {
    this.selectionMode = true;
    if (!this.isBookmarkSelected(id)) {
      this.selectedBookmarkIds = this.selectedBookmarkIds.concat([id]);
    }
  }

  setBookmarkSelection(ids: string[]): void {
    this.selectedBookmarkIds = ids;
    this.selectionMode = this.rowSelectionCount() > 0;
  }

  pruneBookmarkSelection(liveIds: string[]): void {
    const next = this.selectedBookmarkIds.filter((one: string): boolean => liveIds.indexOf(one) >= 0);
    if (next.length !== this.selectedBookmarkIds.length) {
      this.selectedBookmarkIds = next;
      this.selectionMode = this.rowSelectionCount() > 0;
    }
  }

  pruneFolderSelection(liveIds: string[]): void {
    const next = this.selectedFolderIds.filter((one: string): boolean => liveIds.indexOf(one) >= 0);
    if (next.length !== this.selectedFolderIds.length) {
      this.selectedFolderIds = next;
      this.selectionMode = this.rowSelectionCount() > 0;
    }
  }

  clearRowSelection(): void {
    this.selectionMode = false;
    this.selectedBookmarkIds = [];
    this.selectedFolderIds = [];
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
