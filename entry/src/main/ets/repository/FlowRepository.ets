import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { Bookmark } from '../model/Bookmark';
import { ImportResult, ImportedBookmark } from '../model/ImportResult';
import { TagCount } from '../model/Tag';
import { Tombstone } from '../model/Tombstone';
import { BookmarkDao } from '../core/db/BookmarkDao';
import { Database } from '../core/db/Database';
import { MetadataService } from '../core/service/MetadataService';
import { SnapshotStore } from '../core/service/SnapshotStore';
import { BookmarkHtmlParser } from '../core/parser/BookmarkHtmlParser';
import { SyncRecord } from '../core/sync/SyncRecord';
import { AppState } from '../common/AppState';
import { BookmarkSource, ReadState, SnapshotStatus } from '../common/Constants';
import { domainOf, fallbackTitle, normalizeUrl } from '../common/UrlUtil';

export class SaveOutcome {
  bookmark: Bookmark = new Bookmark();
  created: boolean = false;
}

export class LibrarySummary {
  total: number = 0;
  unread: number = 0;
  starred: number = 0;
  archived: number = 0;
  trash: number = 0;
}

class ExportDocument {
  schema: number = 1;
  exportedAt: number = 0;
  items: Bookmark[] = [];
}

function escapeHtml(input: string): string {
  let text = input;
  text = text.replace(new RegExp('&', 'g'), '&amp;');
  text = text.replace(new RegExp('<', 'g'), '&lt;');
  text = text.replace(new RegExp('>', 'g'), '&gt;');
  text = text.replace(new RegExp('"', 'g'), '&quot;');
  return text;
}

export class FlowRepository {
  private static readonly instance: FlowRepository = new FlowRepository();
  private dao: BookmarkDao = new BookmarkDao();
  private context: common.Context | undefined = undefined;

  static get(): FlowRepository {
    return FlowRepository.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.context = context;
    await Database.init(context);
    await this.dao.purgeExpired(30);
  }

  private requireContext(): common.Context {
    if (this.context === undefined) {
      throw new Error('Repository is not initialized');
    }
    return this.context;
  }

  private notify(): void {
    AppState.shared.notifyChanged();
    this.writeCardSnapshot().catch(() => {});
  }

  private async writeCardSnapshot(): Promise<void> {
    if (this.context === undefined) {
      return;
    }
    const all = await this.dao.listAll(false);
    const active: Bookmark[] = [];
    for (let i = 0; i < all.length; i++) {
      if (!all[i].archived) {
        active.push(all[i]);
      }
    }
    let today: Bookmark | undefined = undefined;
    if (active.length > 0) {
      const index = new Date().getDate() % active.length;
      today = active[index];
    }
    const store = preferences.getPreferencesSync(this.context, { name: 'flowpage_card' });
    store.putSync('today_title', today !== undefined ? today.title : '纸还空着');
    store.putSync('today_domain', today !== undefined ? domainOf(today.url) : '');
    store.putSync('today_id', today !== undefined ? today.id : '');
    store.putSync('total_count', `${active.length}`);
    const limit = active.length < 3 ? active.length : 3;
    let lines = '';
    for (let i = 0; i < limit; i++) {
      lines += `${active[i].title}|${domainOf(active[i].url)}|${active[i].id}`;
      if (i < limit - 1) {
        lines += '\n';
      }
    }
    store.putSync('recent_lines', lines);
    await store.flush();
  }

  async upsertFromRemote(record: SyncRecord, etag: string): Promise<boolean> {
    const tombstone = await this.dao.findTombstone(record.id);
    if (tombstone !== undefined) {
      return false;
    }
    const existing = await this.dao.findById(record.id);
    const bookmark = record.toBookmark();
    if (bookmark.urlKey.length === 0) {
      return false;
    }
    bookmark.remoteEtag = etag;
    bookmark.dirty = false;
    if (existing !== undefined) {
      if (existing.dirty) {
        await this.dao.insertConflict(
          existing.id,
          SyncRecord.fromBookmark(existing).toJson(),
          record.toJson(),
          'lww-remote-wins'
        );
      }
      if (bookmark.linkStatus === 0 && existing.linkStatus !== 0) {
        bookmark.linkStatus = existing.linkStatus;
        bookmark.linkCheckedAt = existing.linkCheckedAt;
      }
      bookmark.snapshotPath = existing.snapshotPath;
      bookmark.snapshotStatus = existing.snapshotStatus;
      bookmark.snapshotAt = existing.snapshotAt;
      bookmark.rev = existing.rev + 1;
      await this.dao.update(bookmark);
    } else {
      await this.dao.insert(bookmark);
    }
    return true;
  }

  async setLinkStatus(id: string, status: number): Promise<void> {
    await this.dao.setLinkStatus(id, status, Date.now());
  }

  async setRemoteEtagIfUnchanged(
    id: string,
    etag: string,
    expectedRev: number,
    expectedUpdatedAt: number
  ): Promise<boolean> {
    return this.dao.setRemoteEtagIfUnchanged(id, etag, expectedRev, expectedUpdatedAt);
  }

  afterSync(): void {
    this.notify();
  }

  async listAll(includeDeleted: boolean): Promise<Bookmark[]> {
    return this.dao.listAll(includeDeleted);
  }

  async get(id: string): Promise<Bookmark | undefined> {
    return this.dao.findById(id);
  }

  async summary(): Promise<LibrarySummary> {
    const all = await this.dao.listAll(true);
    const summary = new LibrarySummary();
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      if (item.deleted) {
        summary.trash = summary.trash + 1;
        continue;
      }
      summary.total = summary.total + 1;
      if (item.readState === ReadState.UNREAD) {
        summary.unread = summary.unread + 1;
      }
      if (item.starred) {
        summary.starred = summary.starred + 1;
      }
      if (item.archived) {
        summary.archived = summary.archived + 1;
      }
    }
    return summary;
  }

  async saveUrl(
    rawUrl: string,
    title: string,
    tags: string[],
    note: string,
    source: number
  ): Promise<SaveOutcome> {
    const normalized = normalizeUrl(rawUrl);
    if (normalized.length === 0) {
      throw new Error('Invalid URL');
    }
    const existing = await this.dao.findByUrlKey(normalized);
    const outcome = new SaveOutcome();
    if (existing !== undefined) {
      if (existing.deleted) {
        existing.deleted = false;
        existing.updatedAt = Date.now();
        existing.rev = existing.rev + 1;
        await this.dao.update(existing);
        outcome.bookmark = existing;
        outcome.created = true;
        this.notify();
        return outcome;
      }
      outcome.bookmark = existing;
      outcome.created = false;
      return outcome;
    }

    const bookmark = Bookmark.create(rawUrl, title, source);
    bookmark.tags = tags;
    bookmark.note = note;
    bookmark.siteName = domainOf(rawUrl);
    bookmark.rebuildSearch();
    await this.dao.insert(bookmark);
    outcome.bookmark = bookmark;
    outcome.created = true;
    this.notify();
    return outcome;
  }

  async applyMetadata(id: string): Promise<void> {
    const bookmark = await this.dao.findById(id);
    if (bookmark === undefined) {
      return;
    }
    const metadata = await MetadataService.fetch(bookmark.url);
    if (!metadata.success) {
      bookmark.snapshotStatus = SnapshotStatus.FAILED;
      bookmark.updatedAt = Date.now();
      bookmark.rev = bookmark.rev + 1;
      await this.dao.update(bookmark);
      this.notify();
      return;
    }
    const currentTitle = bookmark.title.trim();
    const fallback = domainOf(bookmark.url);
    if (metadata.title.length > 0 && (currentTitle.length === 0 || currentTitle === fallback)) {
      bookmark.title = metadata.title;
    }
    if (metadata.description.length > 0) {
      bookmark.description = metadata.description;
    }
    if (metadata.siteName.length > 0) {
      bookmark.siteName = metadata.siteName;
    }
    if (metadata.faviconUrl.length > 0) {
      bookmark.faviconUrl = metadata.faviconUrl;
    }
    if (metadata.coverUrl.length > 0) {
      bookmark.coverUrl = metadata.coverUrl;
    }
    if (metadata.snapshotText.length > 0) {
      const path = SnapshotStore.save(this.requireContext(), bookmark.id, metadata.snapshotText);
      bookmark.snapshotPath = path;
      bookmark.snapshotStatus = SnapshotStatus.DONE;
      bookmark.snapshotAt = Date.now();
    } else {
      bookmark.snapshotStatus = SnapshotStatus.FAILED;
    }
    bookmark.updatedAt = Date.now();
    bookmark.rev = bookmark.rev + 1;
    bookmark.rebuildSearch();
    await this.dao.update(bookmark);
    this.notify();
  }

  async refreshPending(): Promise<void> {
    const all = await this.dao.listAll(false);
    let count = 0;
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      if (item.snapshotStatus === SnapshotStatus.PENDING && count < 10) {
        await this.applyMetadata(item.id);
        count = count + 1;
      }
    }
  }

  async loadSnapshot(bookmark: Bookmark): Promise<string> {
    return SnapshotStore.read(bookmark.snapshotPath);
  }

  async saveSnapshot(id: string, text: string): Promise<void> {
    const bookmark = await this.dao.findById(id);
    if (bookmark === undefined) {
      return;
    }
    const path = SnapshotStore.save(this.requireContext(), id, text);
    bookmark.snapshotPath = path;
    bookmark.snapshotStatus = SnapshotStatus.DONE;
    bookmark.snapshotAt = Date.now();
    bookmark.updatedAt = Date.now();
    bookmark.rev = bookmark.rev + 1;
    await this.dao.update(bookmark);
    this.notify();
  }

  async setStarred(id: string, starred: boolean): Promise<void> {
    await this.dao.setStarred(id, starred);
    this.notify();
  }

  async setArchived(id: string, archived: boolean): Promise<void> {
    await this.dao.setArchived(id, archived);
    this.notify();
  }

  async setRead(id: string, state: number): Promise<void> {
    await this.dao.setReadState(id, state);
    this.notify();
  }

  async setTitle(id: string, title: string): Promise<void> {
    await this.dao.setTitle(id, title);
    this.notify();
  }

  async setNote(id: string, note: string): Promise<void> {
    await this.dao.setNote(id, note);
    this.notify();
  }

  async setExcerpt(id: string, excerpt: string): Promise<void> {
    await this.dao.setExcerpt(id, excerpt);
    this.notify();
  }

  async setTags(id: string, tags: string[]): Promise<void> {
    const bookmark = await this.dao.findById(id);
    if (bookmark === undefined) {
      return;
    }
    bookmark.tags = tags;
    bookmark.updatedAt = Date.now();
    bookmark.rev = bookmark.rev + 1;
    bookmark.rebuildSearch();
    await this.dao.update(bookmark);
    this.notify();
  }

  async delete(id: string): Promise<void> {
    await this.dao.softDelete(id);
    this.notify();
  }

  async restore(id: string): Promise<void> {
    await this.dao.restore(id);
    this.notify();
  }

  async purge(id: string): Promise<void> {
    const bookmark = await this.dao.findById(id);
    if (bookmark !== undefined) {
      SnapshotStore.remove(bookmark.snapshotPath);
    }
    await this.dao.purge(id);
    this.notify();
  }

  async purgeExpired(): Promise<number> {
    const count = await this.dao.purgeExpired(30);
    if (count > 0) {
      this.notify();
    }
    return count;
  }

  async listTombstones(): Promise<Tombstone[]> {
    return this.dao.listTombstones();
  }

  async removeTombstone(id: string): Promise<void> {
    await this.dao.removeTombstone(id);
  }

  async markTombstoneFailed(id: string, message: string): Promise<void> {
    await this.dao.markTombstoneFailed(id, message);
  }

  async listTags(): Promise<TagCount[]> {
    return this.dao.listTags();
  }

  async renameTag(id: string, name: string): Promise<void> {
    await this.dao.renameTag(id, name);
    this.notify();
  }

  async deleteTag(id: string): Promise<void> {
    await this.dao.deleteTag(id);
    this.notify();
  }

  async mergeTags(sourceId: string, targetId: string): Promise<void> {
    if (sourceId === targetId) {
      return;
    }
    await this.dao.mergeTags(sourceId, targetId);
    this.notify();
  }

  async importHtml(
    html: string,
    keepFolders: boolean,
    onProgress: (done: number, total: number) => void
  ): Promise<ImportResult> {
    const items = BookmarkHtmlParser.parse(html);
    const result = new ImportResult();
    result.total = items.length;
    result.folderCount = BookmarkHtmlParser.countFolders(items);

    for (let i = 0; i < items.length; i++) {
      const item = items[i];
      const normalized = normalizeUrl(item.url);
      if (normalized.length === 0) {
        result.failed = result.failed + 1;
        result.failedUrls.push(item.url);
        continue;
      }
      const existing = await this.dao.findByUrlKey(normalized);
      if (existing !== undefined) {
        result.skipped = result.skipped + 1;
        continue;
      }
      try {
        const bookmark = Bookmark.create(item.url, item.title, BookmarkSource.IMPORT);
        bookmark.folderPath = item.folderPath;
        bookmark.siteName = domainOf(item.url);
        if (keepFolders && item.folderPath.length > 0) {
          bookmark.tags = [item.folderPath];
        }
        bookmark.rebuildSearch();
        await this.dao.insert(bookmark);
        result.imported = result.imported + 1;
      } catch (error) {
        result.failed = result.failed + 1;
        result.failedUrls.push(item.url);
      }
      if (i % 10 === 0) {
        onProgress(i + 1, items.length);
      }
    }
    onProgress(items.length, items.length);
    this.notify();
    return result;
  }

  async exportJson(): Promise<string> {
    const all = await this.dao.listAll(false);
    const document = new ExportDocument();
    document.exportedAt = Date.now();
    document.items = all;
    return JSON.stringify(document, null, 2);
  }

  async exportHtml(): Promise<string> {
    const all = await this.dao.listAll(false);
    const groups = new Map<string, Bookmark[]>();
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      const key = item.folderPath.length > 0 ? item.folderPath : '';
      const existing = groups.get(key);
      if (existing === undefined) {
        groups.set(key, [item]);
      } else {
        existing.push(item);
      }
    }
    let html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n';
    html += '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n';
    html += '<TITLE>流笺 Bookmarks</TITLE>\n<H1>流笺</H1>\n<DL><p>\n';
    const keys: string[] = [];
    groups.forEach((value: Bookmark[], key: string) => {
      keys.push(key);
    });
    for (let i = 0; i < keys.length; i++) {
      const key = keys[i];
      const items = groups.get(key);
      if (items === undefined) {
        continue;
      }
      if (key.length === 0) {
        for (let j = 0; j < items.length; j++) {
          html += FlowRepository.anchorLine(items[j], '    ');
        }
      } else {
        html += `    <DT><H3>${escapeHtml(key)}</H3>\n    <DL><p>\n`;
        for (let j = 0; j < items.length; j++) {
          html += FlowRepository.anchorLine(items[j], '        ');
        }
        html += '    </DL><p>\n';
      }
    }
    html += '</DL><p>\n';
    return html;
  }

  private static anchorLine(bookmark: Bookmark, indent: string): string {
    const seconds = Math.floor(bookmark.createdAt / 1000);
    return `${indent}<DT><A HREF="${escapeHtml(bookmark.url)}" ADD_DATE="${seconds}">${escapeHtml(bookmark.title)}</A>\n`;
  }

  async clearAll(): Promise<void> {
    await this.dao.clearAll();
    this.notify();
  }
}
