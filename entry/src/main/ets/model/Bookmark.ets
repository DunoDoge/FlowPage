import { util } from '@kit.ArkTS';
import { BookmarkSource, ReadState, SnapshotStatus } from '../common/Constants';
import { fallbackTitle, normalizeUrl } from '../common/UrlUtil';

@ObservedV2
export class Bookmark {
  @Trace id: string = '';
  @Trace url: string = '';
  @Trace urlKey: string = '';
  @Trace title: string = '';
  @Trace description: string = '';
  @Trace siteName: string = '';
  @Trace faviconUrl: string = '';
  @Trace coverUrl: string = '';
  @Trace note: string = '';
  @Trace excerpt: string = '';
  @Trace snapshotPath: string = '';
  @Trace snapshotStatus: number = SnapshotStatus.PENDING;
  @Trace snapshotAt: number = 0;
  @Trace searchText: string = '';
  @Trace source: number = BookmarkSource.MANUAL;
  @Trace folderPath: string = '';
  @Trace readState: number = ReadState.UNREAD;
  @Trace starred: boolean = false;
  @Trace archived: boolean = false;
  @Trace deleted: boolean = false;
  @Trace createdAt: number = 0;
  @Trace updatedAt: number = 0;
  @Trace readAt: number = 0;
  @Trace rev: number = 1;
  @Trace remoteEtag: string = '';
  @Trace dirty: boolean = true;
  @Trace linkStatus: number = 0;
  @Trace linkCheckedAt: number = 0;
  @Trace deviceId: string = '';
  @Trace tags: string[] = [];

  static create(rawUrl: string, title: string, source: number): Bookmark {
    const bookmark = new Bookmark();
    const normalized = normalizeUrl(rawUrl);
    const now = Date.now();
    bookmark.id = util.generateRandomUUID(true);
    bookmark.url = rawUrl.trim();
    bookmark.urlKey = normalized;
    bookmark.title = title.trim().length > 0 ? title.trim() : fallbackTitle(rawUrl);
    bookmark.source = source;
    bookmark.createdAt = now;
    bookmark.updatedAt = now;
    bookmark.snapshotStatus = SnapshotStatus.PENDING;
    bookmark.rebuildSearch();
    return bookmark;
  }

  rebuildSearch(): void {
    const tagPart = this.tags.join(' ');
    this.searchText = `${this.title} ${this.description} ${this.siteName} ${this.url} ${this.note} ${this.excerpt} ${tagPart}`.toLowerCase();
  }
}
