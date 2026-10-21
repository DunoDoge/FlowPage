import { Bookmark } from '../../model/Bookmark';
import { SnapshotStatus } from '../../common/Constants';
import { normalizeUrl } from '../../common/UrlUtil';

export class SyncRecord {
  schema: number = 1;
  id: string = '';
  url: string = '';
  title: string = '';
  description: string = '';
  siteName: string = '';
  faviconUrl: string = '';
  coverUrl: string = '';
  note: string = '';
  excerpt: string = '';
  tags: string[] = [];
  createdAt: number = 0;
  updatedAt: number = 0;
  readState: number = 0;
  readAt: number = 0;
  starred: boolean = false;
  archived: boolean = false;
  deleted: boolean = false;
  rev: number = 1;
  deviceId: string = '';
  linkStatus: number = 0;
  linkCheckedAt: number = 0;

  static fromBookmark(bookmark: Bookmark): SyncRecord {
    const record = new SyncRecord();
    record.id = bookmark.id;
    record.url = bookmark.url;
    record.title = bookmark.title;
    record.description = bookmark.description;
    record.siteName = bookmark.siteName;
    record.faviconUrl = bookmark.faviconUrl;
    record.coverUrl = bookmark.coverUrl;
    record.note = bookmark.note;
    record.excerpt = bookmark.excerpt;
    record.tags = bookmark.tags;
    record.createdAt = bookmark.createdAt;
    record.updatedAt = bookmark.updatedAt;
    record.readState = bookmark.readState;
    record.readAt = bookmark.readAt;
    record.starred = bookmark.starred;
    record.archived = bookmark.archived;
    record.deleted = bookmark.deleted;
    record.rev = bookmark.rev;
    record.deviceId = bookmark.deviceId;
    record.linkStatus = bookmark.linkStatus;
    record.linkCheckedAt = bookmark.linkCheckedAt;
    return record;
  }

  static parse(text: string): SyncRecord {
    const raw = JSON.parse(text) as SyncRecord;
    const record = new SyncRecord();
    record.schema = typeof raw.schema === 'number' ? raw.schema : 1;
    record.id = typeof raw.id === 'string' ? raw.id : '';
    record.url = typeof raw.url === 'string' ? raw.url : '';
    record.title = typeof raw.title === 'string' ? raw.title : '';
    record.description = typeof raw.description === 'string' ? raw.description : '';
    record.siteName = typeof raw.siteName === 'string' ? raw.siteName : '';
    record.faviconUrl = typeof raw.faviconUrl === 'string' ? raw.faviconUrl : '';
    record.coverUrl = typeof raw.coverUrl === 'string' ? raw.coverUrl : '';
    record.note = typeof raw.note === 'string' ? raw.note : '';
    record.excerpt = typeof raw.excerpt === 'string' ? raw.excerpt : '';
    record.tags = raw.tags !== undefined ? raw.tags : [];
    record.createdAt = typeof raw.createdAt === 'number' ? raw.createdAt : 0;
    record.updatedAt = typeof raw.updatedAt === 'number' ? raw.updatedAt : 0;
    record.readState = typeof raw.readState === 'number' ? raw.readState : 0;
    record.readAt = typeof raw.readAt === 'number' ? raw.readAt : 0;
    record.starred = raw.starred === true;
    record.archived = raw.archived === true;
    record.deleted = raw.deleted === true;
    record.rev = typeof raw.rev === 'number' ? raw.rev : 1;
    record.deviceId = typeof raw.deviceId === 'string' ? raw.deviceId : '';
    record.linkStatus = typeof raw.linkStatus === 'number' ? raw.linkStatus : 0;
    record.linkCheckedAt = typeof raw.linkCheckedAt === 'number' ? raw.linkCheckedAt : 0;
    return record;
  }

  toBookmark(): Bookmark {
    const bookmark = new Bookmark();
    bookmark.id = this.id;
    bookmark.url = this.url;
    bookmark.urlKey = normalizeUrl(this.url);
    bookmark.title = this.title;
    bookmark.description = this.description;
    bookmark.siteName = this.siteName;
    bookmark.faviconUrl = this.faviconUrl;
    bookmark.coverUrl = this.coverUrl;
    bookmark.note = this.note;
    bookmark.excerpt = this.excerpt;
    bookmark.tags = this.tags;
    bookmark.createdAt = this.createdAt;
    bookmark.updatedAt = this.updatedAt;
    bookmark.readState = this.readState;
    bookmark.readAt = this.readAt;
    bookmark.starred = this.starred;
    bookmark.archived = this.archived;
    bookmark.deleted = this.deleted;
    bookmark.rev = this.rev;
    bookmark.deviceId = this.deviceId;
    bookmark.linkStatus = this.linkStatus;
    bookmark.linkCheckedAt = this.linkCheckedAt;
    bookmark.snapshotStatus = SnapshotStatus.PENDING;
    bookmark.rebuildSearch();
    return bookmark;
  }

  toJson(): string {
    return JSON.stringify(this);
  }
}
