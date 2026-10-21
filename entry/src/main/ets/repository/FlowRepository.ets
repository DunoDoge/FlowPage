import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Bookmark } from '../model/Bookmark';
import { BookmarkPage, BookmarkQuery } from '../model/BookmarkQuery';
import { ConflictRecord } from '../model/Conflict';
import { ImportPreview } from '../model/ImportPreview';
import { ImportResult } from '../model/ImportResult';
import { TagCount } from '../model/Tag';
import { Tombstone } from '../model/Tombstone';
import { BookmarkDao } from '../core/db/BookmarkDao';
import { Database } from '../core/db/Database';
import { MetadataService } from '../core/service/MetadataService';
import { SnapshotStore } from '../core/service/SnapshotStore';
import { BookmarkHtmlParser } from '../core/parser/BookmarkHtmlParser';
import { SyncRecord } from '../core/sync/SyncRecord';
import { AppState } from '../common/AppState';
import { BookmarkSource, SnapshotStatus } from '../common/Constants';
import { cardLineOf, cardTitleOf } from '../common/CardFormat';
import { domainOf, normalizeUrl } from '../common/UrlUtil';
import { CardPublisher } from '../core/service/CardPublisher';
import {
  CARD_KEY_CANDIDATES,
  CARD_KEY_RECENT_LINES,
  CARD_KEY_TODAY_DOMAIN,
  CARD_KEY_TODAY_ID,
  CARD_KEY_TODAY_TITLE,
  CARD_KEY_TOTAL_COUNT,
  CARD_PREFERENCES_NAME
} from '../core/service/CardSnapshot';

const SETTINGS_NAME: string = 'flowpage_settings';
const AUTO_SNAPSHOT_KEY: string = 'auto_snapshot';

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

export class ImportOptions {
  keepFolders: boolean = true;
  onProgress: (done: number, total: number) => void = (done: number, total: number) => {};
  shouldCancel: () => boolean = () => false;
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
  private cardSnapshotRunning: boolean = false;
  private cardSnapshotPending: boolean = false;

  static get(): FlowRepository {
    return FlowRepository.instance;
  }

  async init(context: common.Context): Promise<void> {
    this.context = context;
    await Database.init(context);
    await this.dao.backfillDomains();
    await this.purgeExpired();
    this.scheduleCardSnapshot();
  }

  private requireContext(): common.Context {
    if (this.context === undefined) {
      throw new Error('Repository is not initialized');
    }
    return this.context;
  }

  autoSnapshotEnabled(): boolean {
    if (this.context === undefined) {
      return true;
    }
    try {
      const store = preferences.getPreferencesSync(this.context, { name: SETTINGS_NAME });
      const value = store.getSync(AUTO_SNAPSHOT_KEY, true);
      return typeof value === 'boolean' ? value : true;
    } catch (error) {
      return true;
    }
  }

  private notify(): void {
    AppState.shared.notifyChanged();
    this.scheduleCardSnapshot();
  }

  private scheduleCardSnapshot(): void {
    if (this.context === undefined) {
      return;
    }
    if (this.cardSnapshotRunning) {
      this.cardSnapshotPending = true;
      return;
    }
    this.cardSnapshotRunning = true;
    this.runCardSnapshot();
  }

  private async runCardSnapshot(): Promise<void> {
    if (this.context === undefined) {
      return;
    }
    try {
      await this.writeCardSnapshot();
      await CardPublisher.publish(this.requireContext());
    } catch (error) {
      hilog.warn(
        0x0000,
        'flowpage',
        'Failed to refresh card snapshot or push cards reason=%{public}s',
        JSON.stringify(error)
      );
    } finally {
      this.cardSnapshotRunning = false;
      if (this.cardSnapshotPending) {
        this.cardSnapshotPending = false;
        this.scheduleCardSnapshot();
      }
    }
  }

  private async writeCardSnapshot(): Promise<void> {
    if (this.context === undefined) {
      return;
    }
    const active = await this.dao.listForCard(10);
    const counts = await this.dao.summaryCounts();
    let today: Bookmark | undefined = undefined;
    if (active.length > 0) {
      const index = new Date().getDate() % active.length;
      today = active[index];
    }
    const store = preferences.getPreferencesSync(this.context, { name: CARD_PREFERENCES_NAME });
    store.putSync(CARD_KEY_TODAY_TITLE, today !== undefined ? cardTitleOf(today.title) : '纸还空着');
    store.putSync(CARD_KEY_TODAY_DOMAIN, today !== undefined ? domainOf(today.url) : '');
    store.putSync(CARD_KEY_TODAY_ID, today !== undefined ? today.id : '');
    store.putSync(CARD_KEY_TOTAL_COUNT, `${counts.total}`);
    const lines: string[] = [];
    for (let i = 0; i < active.length; i++) {
      lines.push(cardLineOf(active[i].title, domainOf(active[i].url), active[i].id));
    }
    const recentLimit = lines.length < 3 ? lines.length : 3;
    store.putSync(CARD_KEY_RECENT_LINES, lines.slice(0, recentLimit).join('\n'));
    store.putSync(CARD_KEY_CANDIDATES, lines.join('\n'));
    await store.flush();
  }

  // A remote-wins overwrite keeps local-only snapshot fields. Schema 1 records predate
  // folderPath/source, so those two stay local until the peer upgrades to schema 2.
  private carryLocalFields(target: Bookmark, existing: Bookmark, remoteHasFolders: boolean): void {
    target.snapshotPath = existing.snapshotPath;
    target.snapshotStatus = existing.snapshotStatus;
    target.snapshotAt = existing.snapshotAt;
    if (!remoteHasFolders) {
      target.folderPath = existing.folderPath;
      target.source = existing.source;
    }
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
      this.carryLocalFields(bookmark, existing, record.schema >= 2);
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

  async clearRemoteEtags(): Promise<void> {
    await this.dao.clearRemoteEtags();
  }

  afterSync(): void {
    this.notify();
  }

  async listAll(includeDeleted: boolean): Promise<Bookmark[]> {
    return this.dao.listAll(includeDeleted);
  }

  async queryPage(query: BookmarkQuery, offset: number, limit: number): Promise<BookmarkPage> {
    const rows = await this.dao.queryPage(query, offset, limit);
    const page = new BookmarkPage();
    page.hasMore = rows.length > limit;
    if (page.hasMore) {
      rows.pop();
    }
    page.items = rows;
    return page;
  }

  async countToday(): Promise<number> {
    const start = new Date();
    start.setHours(0, 0, 0, 0);
    return this.dao.countCreatedSince(start.getTime());
  }

  async get(id: string): Promise<Bookmark | undefined> {
    return this.dao.findById(id);
  }

  async summary(): Promise<LibrarySummary> {
    const counts = await this.dao.summaryCounts();
    const summary = new LibrarySummary();
    summary.total = counts.total;
    summary.unread = counts.unread;
    summary.starred = counts.starred;
    summary.archived = counts.archived;
    summary.trash = counts.trash;
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
        existing.dirty = true;
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
    const autoSnapshot = this.autoSnapshotEnabled();
    const metadata = await MetadataService.fetch(bookmark.url, autoSnapshot);
    if (!metadata.success) {
      bookmark.snapshotStatus = autoSnapshot ? SnapshotStatus.FAILED : SnapshotStatus.OFF;
      bookmark.updatedAt = Date.now();
      bookmark.rev = bookmark.rev + 1;
      bookmark.dirty = true;
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
    if (!autoSnapshot) {
      bookmark.snapshotStatus = SnapshotStatus.OFF;
    } else if (metadata.snapshotText.length > 0) {
      const path = SnapshotStore.save(this.requireContext(), bookmark.id, metadata.snapshotText);
      bookmark.snapshotPath = path;
      bookmark.snapshotStatus = SnapshotStatus.DONE;
      bookmark.snapshotAt = Date.now();
    } else {
      bookmark.snapshotStatus = SnapshotStatus.FAILED;
    }
    bookmark.updatedAt = Date.now();
    bookmark.rev = bookmark.rev + 1;
    bookmark.dirty = true;
    bookmark.rebuildSearch();
    await this.dao.update(bookmark);
    this.notify();
  }

  async loadSnapshot(bookmark: Bookmark): Promise<string> {
    return SnapshotStore.read(bookmark.snapshotPath);
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
    bookmark.dirty = true;
    bookmark.rebuildSearch();
    await this.dao.update(bookmark);
    this.notify();
  }

  async saveEdits(id: string, title: string, note: string, excerpt: string, tags: string[]): Promise<void> {
    const updated = await this.dao.editContent(id, title, note, excerpt, tags);
    if (updated !== undefined) {
      this.notify();
    }
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
    if (this.context !== undefined) {
      SnapshotStore.removeById(this.context, id);
    }
    await this.dao.purge(id);
    this.notify();
  }

  async purgeExpired(): Promise<number> {
    const ids = await this.dao.listExpiredIds(30);
    for (let i = 0; i < ids.length; i++) {
      const bookmark = await this.dao.findById(ids[i]);
      if (bookmark !== undefined) {
        SnapshotStore.remove(bookmark.snapshotPath);
      }
      if (this.context !== undefined) {
        SnapshotStore.removeById(this.context, ids[i]);
      }
      await this.dao.purge(ids[i]);
    }
    if (ids.length > 0) {
      this.notify();
    }
    return ids.length;
  }

  async purgeFromRemote(id: string): Promise<void> {
    const bookmark = await this.dao.findById(id);
    if (bookmark !== undefined) {
      SnapshotStore.remove(bookmark.snapshotPath);
      await this.dao.purgeLocal(id);
    }
    if (this.context !== undefined) {
      SnapshotStore.removeById(this.context, id);
    }
    await this.dao.removeTombstone(id);
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

  async renameTag(id: string, name: string): Promise<boolean> {
    const merged = await this.dao.renameTag(id, name);
    this.notify();
    return merged;
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

  async countConflicts(): Promise<number> {
    return this.dao.countConflicts();
  }

  async listConflicts(): Promise<ConflictRecord[]> {
    return this.dao.listConflicts();
  }

  async resolveConflict(conflictId: string, useLocal: boolean): Promise<boolean> {
    const conflicts = await this.dao.listConflicts();
    let target: ConflictRecord | undefined = undefined;
    for (let i = 0; i < conflicts.length; i++) {
      if (conflicts[i].id === conflictId) {
        target = conflicts[i];
        break;
      }
    }
    if (target === undefined) {
      return false;
    }
    const record = SyncRecord.parse(useLocal ? target.localJson : target.remoteJson);
    const chosen = record.toBookmark();
    if (chosen.urlKey.length === 0) {
      return false;
    }
    const existing = await this.dao.findById(target.bookmarkId);
    if (existing === undefined) {
      const tombstone = await this.dao.findTombstone(target.bookmarkId);
      if (tombstone !== undefined) {
        return false;
      }
      chosen.rev = chosen.rev + 1;
      chosen.updatedAt = Date.now();
      chosen.dirty = true;
      await this.dao.insert(chosen);
    } else {
      this.carryLocalFields(chosen, existing, record.schema >= 2);
      chosen.remoteEtag = existing.remoteEtag;
      chosen.rev = existing.rev + 1;
      chosen.updatedAt = Date.now();
      chosen.dirty = true;
      await this.dao.update(chosen);
    }
    await this.dao.deleteConflict(conflictId);
    this.notify();
    return true;
  }

  async previewHtml(html: string): Promise<ImportPreview> {
    const parsed = BookmarkHtmlParser.parseAll(html);
    const preview = new ImportPreview();
    preview.total = parsed.items.length;
    preview.folderCount = BookmarkHtmlParser.countFolders(parsed.items);
    preview.invalidCount = parsed.invalidCount;
    preview.duplicateCount = parsed.inFileDuplicates;
    const existingKeys = await this.dao.listUrlKeys();
    for (let i = 0; i < parsed.items.length; i++) {
      const normalized = normalizeUrl(parsed.items[i].url);
      if (normalized.length === 0) {
        preview.invalidCount = preview.invalidCount + 1;
        continue;
      }
      if (existingKeys.has(normalized)) {
        preview.duplicateCount = preview.duplicateCount + 1;
        continue;
      }
      preview.importable = preview.importable + 1;
    }
    return preview;
  }

  async importHtml(html: string, options: ImportOptions): Promise<ImportResult> {
    const parsed = BookmarkHtmlParser.parseAll(html);
    const items = parsed.items;
    const result = new ImportResult();
    result.total = items.length;
    result.folderCount = BookmarkHtmlParser.countFolders(items);
    result.failed = parsed.invalidCount;
    for (let i = 0; i < parsed.invalidUrls.length; i++) {
      result.failedUrls.push(parsed.invalidUrls[i]);
    }
    const existingKeys = await this.dao.listUrlKeys();

    let pending: Bookmark[] = [];
    const flush = async (): Promise<void> => {
      if (pending.length === 0) {
        return;
      }
      try {
        await this.dao.insertBatch(pending);
        result.imported = result.imported + pending.length;
      } catch (error) {
        for (let i = 0; i < pending.length; i++) {
          try {
            await this.dao.insert(pending[i]);
            result.imported = result.imported + 1;
          } catch (inner) {
            result.failed = result.failed + 1;
            result.failedUrls.push(pending[i].url);
          }
        }
      }
      pending = [];
    };

    for (let i = 0; i < items.length; i++) {
      if (options.shouldCancel()) {
        result.cancelled = true;
        break;
      }
      const item = items[i];
      const normalized = normalizeUrl(item.url);
      if (normalized.length === 0) {
        result.failed = result.failed + 1;
        result.failedUrls.push(item.url);
        continue;
      }
      if (existingKeys.has(normalized)) {
        result.skipped = result.skipped + 1;
        continue;
      }
      existingKeys.add(normalized);
      const bookmark = Bookmark.create(item.url, item.title, BookmarkSource.IMPORT);
      bookmark.folderPath = item.folderPath;
      bookmark.siteName = domainOf(item.url);
      if (options.keepFolders && item.folderPath.length > 0) {
        bookmark.tags = [item.folderPath];
      }
      bookmark.rebuildSearch();
      pending.push(bookmark);
      if (pending.length >= 250) {
        await flush();
      }
      if (i % 10 === 0) {
        options.onProgress(i + 1, items.length);
      }
    }
    await flush();
    options.onProgress(items.length, items.length);
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
    const all = await this.dao.listAll(true);
    for (let i = 0; i < all.length; i++) {
      SnapshotStore.remove(all[i].snapshotPath);
    }
    if (this.context !== undefined) {
      SnapshotStore.clearAll(this.context);
    }
    await this.dao.clearAll();
    this.notify();
  }
}
