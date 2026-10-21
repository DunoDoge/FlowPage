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

export class Limits {
  static readonly snapshotBytes: number = 204800;
  static readonly fetchBytes: number = 524288;
  static readonly titleChars: number = 200;
  static readonly descriptionChars: number = 400;
  static readonly searchLimit: number = 10000;
}
