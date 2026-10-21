export class Space {
  static readonly xxs: number = 4;
  static readonly xs: number = 8;
  static readonly sm: number = 12;
  static readonly md: number = 16;
  static readonly lg: number = 20;
  static readonly xl: number = 24;
  static readonly xxl: number = 32;
  static readonly huge: number = 40;
}

export class Radius {
  static readonly xs: number = 2;
  static readonly sm: number = 6;
  static readonly md: number = 10;
  static readonly lg: number = 16;
}

export class FontSize {
  static readonly display: number = 34;
  static readonly title: number = 24;
  static readonly headline: number = 17;
  static readonly body: number = 15;
  static readonly reading: number = 17;
  static readonly caption: number = 12;
  static readonly label: number = 12;
}

export class Breakpoint {
  static readonly medium: number = 600;
  static readonly large: number = 840;
  static readonly rail: number = 72;
  static readonly sideNav: number = 240;
  static readonly list: number = 380;
}

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

export enum SheetMode {
  INBOX = 0,
  EDIT = 1
}

export class Limits {
  static readonly snapshotBytes: number = 204800;
  static readonly fetchBytes: number = 524288;
  static readonly titleChars: number = 200;
  static readonly descriptionChars: number = 400;
  static readonly searchLimit: number = 10000;
}
