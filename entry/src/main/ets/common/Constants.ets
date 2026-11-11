export enum StreamFilter {
  ALL = 0,
  UNREAD = 1,
  STARRED = 2,
  ARCHIVED = 3,
  TRASH = 4
}

export enum ReadState {
  UNREAD = 0,
  READING = 1,
  READ = 2
}

export enum SnapshotStatus {
  PENDING = 0,
  DONE = 1,
  FAILED = 2,
  OFF = 3
}

export enum BookmarkSource {
  MANUAL = 0,
  SHARE = 1,
  CLIPBOARD = 2,
  IMPORT = 3,
  KNOCK = 4,
  BROWSER = 5
}

export enum Pane {
  DETAIL = 'detail',
  TAGS = 'tags',
  SYNC = 'sync',
  SETTINGS = 'settings'
}

// Single destination definition shared by the floating tab bar (<1000vp) and
// the docked rail nav list (>=1000vp); the rail renders labels only. The icon
// default mirrors the first entry; every NAV_ITEMS literal overrides it.
export class NavItem {
  label: string = '';
  pane: string = '';
  icon: Resource = $r('sys.symbol.house');
}

export const NAV_ITEMS: NavItem[] = [
  { label: '笺流', pane: Pane.DETAIL, icon: $r('sys.symbol.house') },
  { label: '标签', pane: Pane.TAGS, icon: $r('sys.symbol.label') },
  { label: '同步', pane: Pane.SYNC, icon: $r('sys.symbol.arrow_2_circlepath') },
  { label: '设置', pane: Pane.SETTINGS, icon: $r('sys.symbol.gearshape') }
];

export class Limits {
  static readonly snapshotBytes: number = 204800;
  static readonly fetchBytes: number = 524288;
  static readonly titleChars: number = 200;
  static readonly descriptionChars: number = 400;
  static readonly searchLimit: number = 10000;
}
