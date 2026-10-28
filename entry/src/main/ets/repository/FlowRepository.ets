import { common } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Bookmark } from '../model/Bookmark';
import { BookmarkPage, BookmarkQuery, BookmarkSort } from '../model/BookmarkQuery';
import { ArticleDocument } from '../model/Article';
import { classifyMetadataWrite, MetadataApplyResult } from '../model/MetadataResult';
import { ConflictRecord } from '../model/Conflict';
import { ImportPreview } from '../model/ImportPreview';
import { ImportResult } from '../model/ImportResult';
import { Folder, FolderNode } from '../model/Folder';
import { TagCount } from '../model/Tag';
import { Tombstone } from '../model/Tombstone';
import { BookmarkDao } from '../core/db/BookmarkDao';
import { FolderDao, buildFolderTree } from '../core/db/FolderDao';
import { Database } from '../core/db/Database';
import { MetadataService } from '../core/service/MetadataService';
import { SnapshotStore } from '../core/service/SnapshotStore';
import { BookmarkHtmlParser } from '../core/parser/BookmarkHtmlParser';
import { FolderSyncRecord } from '../core/sync/FolderSyncRecord';
import { SyncRecord } from '../core/sync/SyncRecord';
import { AppState } from '../common/AppState';
import { BookmarkSource, SnapshotStatus } from '../common/Constants';
import { ReaderPrefs } from '../common/ReaderPrefs';
import { ArticleSignature } from '../common/ArticleSignature';
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
  onProgress: (done: number, total: number) => void = (done: number, total: number) => {};
  shouldCancel: () => boolean = () => false;
}

export class BatchOutcome {
  done: number = 0;
  skipped: number = 0;
}

export class BatchImpact {
  folders: number = 0;
  looseBooks: number = 0;
  subtreeBooks: number = 0;
}

class ExportFolder {
  id: string = '';
  parentId: string = '';
  name: string = '';
  position: number = 0;
  kind: string = '';
  createdAt: number = 0;
}

// Plain DTO: @ObservedV2 / @Trace instances do not JSON.stringify their
// fields, so bookmarks must be copied into a plain shape before export.
class ExportBookmark {
  id: string = '';
  url: string = '';
  title: string = '';
  description: string = '';
  siteName: string = '';
  note: string = '';
  excerpt: string = '';
  tags: string[] = [];
  folderId: string = '';
  source: number = 0;
  createdAt: number = 0;
  updatedAt: number = 0;
  readState: number = 0;
  readAt: number = 0;
  starred: boolean = false;
  archived: boolean = false;
  deleted: boolean = false;
}

class ExportDocument {
  schema: number = 2;
  exportedAt: number = 0;
  items: ExportBookmark[] = [];
  folders: ExportFolder[] = [];
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
  private folderDao: FolderDao = new FolderDao();
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

  // A remote-wins overwrite keeps local-only snapshot fields. Schema 1 records
  // predate folderId/source, schema 2 predate folderId; those stay local until
  // the peer upgrades.
  private carryLocalFields(target: Bookmark, existing: Bookmark, schema: number): void {
    target.snapshotPath = existing.snapshotPath;
    target.snapshotStatus = existing.snapshotStatus;
    target.snapshotAt = existing.snapshotAt;
    if (schema < 2) {
      target.source = existing.source;
    }
    if (schema < 3) {
      target.folderId = existing.folderId;
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
      this.carryLocalFields(bookmark, existing, record.schema);
      bookmark.rev = existing.rev + 1;
      await this.dao.update(bookmark);
    } else {
      await this.dao.insert(bookmark);
    }
    // A remote record that lands a bookmark live (peer restore, or an edit
    // newer than a local cascade delete) must also un-dangle its folder
    // chain, or the revived bookmark hides forever under a soft-deleted
    // folder. No notify(): sync methods refresh once via afterSync().
    if (!bookmark.deleted && bookmark.folderId.length > 0) {
      await this.folderDao.restoreChain(bookmark.folderId);
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
    await this.folderDao.clearRemoteEtags();
  }

  async listAllFolders(): Promise<Folder[]> {
    return this.folderDao.listAll(true);
  }

  async getFolder(id: string): Promise<Folder | undefined> {
    return this.folderDao.findById(id);
  }

  async folderTree(): Promise<FolderNode[]> {
    const folders = await this.folderDao.listAll(false);
    const counts = await this.folderDao.countByFolder();
    return buildFolderTree(folders, counts);
  }

  async createFolder(parentId: string, name: string): Promise<Folder | undefined> {
    const folder = await this.folderDao.create(parentId, name);
    if (folder !== undefined) {
      this.notify();
    }
    return folder;
  }

  async renameFolder(id: string, name: string): Promise<boolean> {
    const renamed = await this.folderDao.rename(id, name);
    if (renamed) {
      this.notify();
    }
    return renamed;
  }

  async moveFolder(id: string, newParentId: string): Promise<boolean> {
    const moved = await this.folderDao.move(id, newParentId);
    if (moved) {
      this.notify();
    }
    return moved;
  }

  async deleteFolderCascade(id: string): Promise<number> {
    const affected = await this.folderDao.cascadeSoftDelete(id);
    this.notify();
    return affected;
  }

  async setBookmarkFolder(id: string, folderId: string): Promise<void> {
    await this.dao.setFolder(id, folderId);
    this.notify();
  }

  // Folder subtree as a filter id set: the folder itself plus live descendants.
  async subtreeFolderIds(id: string): Promise<string[]> {
    return [id].concat(await this.folderDao.descendantIds(id));
  }

  async countFolderBookmarks(id: string): Promise<number> {
    const ids = await this.subtreeFolderIds(id);
    const counts = await this.folderDao.countByFolder();
    let total = 0;
    for (let i = 0; i < ids.length; i++) {
      const count = counts.get(ids[i]);
      total = total + (count !== undefined ? count : 0);
    }
    return total;
  }

  // Direct members of one folder ('' = root), browser order via ADD_DATE-kept createdAt.
  async bookmarksInFolder(folderId: string): Promise<Bookmark[]> {
    const query = new BookmarkQuery();
    query.folderId = folderId;
    query.sort = BookmarkSort.CREATED_ASC;
    return this.dao.queryPage(query, 0, 500);
  }

  // Batch operations for the folder page multi-select mode: DAO calls loop
  // here and notify() fires once, so the UI and cards refresh a single time.
  async batchMove(bookmarkIds: string[], folderIds: string[], targetFolderId: string): Promise<BatchOutcome> {
    const outcome = new BatchOutcome();
    for (let i = 0; i < bookmarkIds.length; i++) {
      await this.dao.setFolder(bookmarkIds[i], targetFolderId);
      outcome.done = outcome.done + 1;
    }
    for (let i = 0; i < folderIds.length; i++) {
      const moved = await this.folderDao.move(folderIds[i], targetFolderId, true);
      if (moved) {
        outcome.done = outcome.done + 1;
      } else {
        outcome.skipped = outcome.skipped + 1;
      }
    }
    if (outcome.done > 0) {
      this.notify();
    }
    return outcome;
  }

  // One level up for every selected item: a bookmark lands in its folder's
  // parent, a folder in its parent's parent. Root-level items are skipped.
  async batchMoveOut(bookmarkIds: string[], folderIds: string[]): Promise<BatchOutcome> {
    const outcome = new BatchOutcome();
    for (let i = 0; i < bookmarkIds.length; i++) {
      const bookmark = await this.dao.findById(bookmarkIds[i]);
      if (bookmark === undefined || bookmark.deleted || bookmark.folderId.length === 0) {
        outcome.skipped = outcome.skipped + 1;
        continue;
      }
      const folder = await this.folderDao.findById(bookmark.folderId);
      if (folder === undefined || folder.deleted) {
        outcome.skipped = outcome.skipped + 1;
        continue;
      }
      await this.dao.setFolder(bookmark.id, folder.parentId);
      outcome.done = outcome.done + 1;
    }
    for (let i = 0; i < folderIds.length; i++) {
      const folder = await this.folderDao.findById(folderIds[i]);
      if (folder === undefined || folder.deleted || folder.parentId.length === 0) {
        outcome.skipped = outcome.skipped + 1;
        continue;
      }
      const parent = await this.folderDao.findById(folder.parentId);
      if (parent === undefined || parent.deleted) {
        outcome.skipped = outcome.skipped + 1;
        continue;
      }
      const moved = await this.folderDao.move(folder.id, parent.parentId, true);
      if (moved) {
        outcome.done = outcome.done + 1;
      } else {
        outcome.skipped = outcome.skipped + 1;
      }
    }
    if (outcome.done > 0) {
      this.notify();
    }
    return outcome;
  }

  // Impact summary for the mixed-selection delete confirmation: loose books
  // sitting inside a selected subtree are counted once, with the subtree.
  async batchDeleteImpact(bookmarkIds: string[], folderIds: string[]): Promise<BatchImpact> {
    const impact = new BatchImpact();
    impact.folders = folderIds.length;
    const subtreeIds = new Set<string>();
    for (let i = 0; i < folderIds.length; i++) {
      const ids = await this.subtreeFolderIds(folderIds[i]);
      for (let j = 0; j < ids.length; j++) {
        subtreeIds.add(ids[j]);
      }
    }
    const counts = await this.folderDao.countByFolder();
    let subtreeBooks = 0;
    subtreeIds.forEach((folderId: string): void => {
      const count = counts.get(folderId);
      subtreeBooks = subtreeBooks + (count !== undefined ? count : 0);
    });
    let looseBooks = 0;
    for (let i = 0; i < bookmarkIds.length; i++) {
      const bookmark = await this.dao.findById(bookmarkIds[i]);
      if (bookmark !== undefined && bookmark.folderId.length > 0 && subtreeIds.has(bookmark.folderId)) {
        continue;
      }
      looseBooks = looseBooks + 1;
    }
    impact.looseBooks = looseBooks;
    impact.subtreeBooks = subtreeBooks;
    return impact;
  }

  // Soft delete only, trash + purge-tombstone semantics unchanged: folders
  // cascade through FolderDao, bookmarks reuse softDeleteMany.
  async batchDelete(bookmarkIds: string[], folderIds: string[]): Promise<BatchOutcome> {
    const outcome = new BatchOutcome();
    if (bookmarkIds.length > 0) {
      await this.dao.softDeleteMany(bookmarkIds);
      outcome.done = outcome.done + bookmarkIds.length;
    }
    for (let i = 0; i < folderIds.length; i++) {
      const folder = await this.folderDao.findById(folderIds[i]);
      if (folder === undefined || folder.deleted) {
        outcome.skipped = outcome.skipped + 1;
        continue;
      }
      await this.folderDao.cascadeSoftDelete(folderIds[i]);
      outcome.done = outcome.done + 1;
    }
    if (outcome.done > 0) {
      this.notify();
    }
    return outcome;
  }

  async setFolderEtagIfUnchanged(
    id: string,
    etag: string,
    expectedRev: number,
    expectedUpdatedAt: number
  ): Promise<boolean> {
    return this.folderDao.setFolderEtagIfUnchanged(id, etag, expectedRev, expectedUpdatedAt);
  }

  // Folders resolve LWW without conflict records: the bookmark conflict UI has
  // no folder shape, and a lost rename is recoverable by renaming again.
  async upsertFolderFromRemote(record: FolderSyncRecord, etag: string): Promise<boolean> {
    const tombstone = await this.dao.findTombstone(record.id);
    if (tombstone !== undefined) {
      return false;
    }
    const folder = record.toFolder();
    if (folder.name.length === 0) {
      return false;
    }
    folder.remoteEtag = etag;
    folder.dirty = false;
    // Two devices (or two imports of the same HTML) can create same-name
    // siblings with different ids; land the loser under a deduped name
    // instead of tripping the partial unique index on every sync.
    folder.name = await this.folderDao.dedupedName(folder.parentId, folder.name, folder.id);
    const existing = await this.folderDao.findById(folder.id);
    if (existing !== undefined) {
      folder.rev = existing.rev + 1;
      await this.folderDao.update(folder);
    } else {
      await this.folderDao.insert(folder);
    }
    return true;
  }

  async purgeFolderFromRemote(id: string): Promise<void> {
    await this.folderDao.purgeLocal(id);
    await this.dao.removeTombstone(id);
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

  async applyMetadata(id: string): Promise<MetadataApplyResult> {
    const bookmark = await this.dao.findById(id);
    if (bookmark === undefined) {
      return MetadataApplyResult.FAILED;
    }
    const autoSnapshot = this.autoSnapshotEnabled();
    const metadata = await MetadataService.fetch(bookmark.url, autoSnapshot, true);
    if (!metadata.success) {
      return MetadataApplyResult.FAILED;
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
    const hadSnapshot = SnapshotStore.isReadable(bookmark.snapshotPath);
    const outcome = classifyMetadataWrite(
      true,
      autoSnapshot,
      hadSnapshot,
      metadata.article.blocks.length > 0
    );
    if (outcome === MetadataApplyResult.WROTE_SNAPSHOT) {
      const previous = hadSnapshot ? SnapshotStore.readArticle(bookmark.snapshotPath) : new ArticleDocument();
      const path = SnapshotStore.saveArticle(this.requireContext(), bookmark.id, metadata.article);
      bookmark.snapshotPath = path;
      bookmark.snapshotStatus = SnapshotStatus.DONE;
      bookmark.snapshotAt = Date.now();
      if (ArticleSignature.differs(previous, metadata.article)) {
        ReaderPrefs.clearPosition(this.requireContext(), bookmark.id);
      }
    } else if (outcome === MetadataApplyResult.KEPT_OLD) {
      bookmark.snapshotStatus = SnapshotStatus.DONE;
    } else if (outcome === MetadataApplyResult.EMPTY) {
      bookmark.snapshotStatus = autoSnapshot ? SnapshotStatus.FAILED : SnapshotStatus.OFF;
    }
    bookmark.updatedAt = Date.now();
    bookmark.rev = bookmark.rev + 1;
    bookmark.dirty = true;
    bookmark.rebuildSearch();
    await this.dao.update(bookmark);
    this.notify();
    return outcome;
  }

  async loadArticle(bookmark: Bookmark): Promise<ArticleDocument> {
    if (bookmark.snapshotPath.length === 0) {
      return new ArticleDocument();
    }
    return SnapshotStore.readArticle(bookmark.snapshotPath);
  }

  async setStarred(id: string, starred: boolean): Promise<void> {
    await this.dao.setStarred(id, starred);
    this.notify();
  }

  async setStarredMany(ids: string[], starred: boolean): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.dao.setStarredMany(ids, starred);
    this.notify();
  }

  async setArchived(id: string, archived: boolean): Promise<void> {
    await this.dao.setArchived(id, archived);
    this.notify();
  }

  async setArchivedMany(ids: string[], archived: boolean): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.dao.setArchivedMany(ids, archived);
    this.notify();
  }

  async setRead(id: string, state: number): Promise<void> {
    await this.dao.setReadState(id, state);
    this.notify();
  }

  async setReadMany(ids: string[], state: number): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.dao.setReadStateMany(ids, state);
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

  async appendExcerpt(id: string, text: string): Promise<string> {
    const next = await this.dao.appendExcerpt(id, text);
    if (next.length > 0) {
      this.notify();
    }
    return next;
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

  async deleteMany(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.dao.softDeleteMany(ids);
    this.notify();
  }

  async restore(id: string): Promise<void> {
    await this.restoreWithFolderChains([id]);
    this.notify();
  }

  async restoreMany(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    await this.restoreWithFolderChains(ids);
    this.notify();
  }

  // Folder ids are read before the bookmark flip (it never touches
  // folder_id, but reading first keeps that an implementation detail) and
  // each distinct chain is revived once; restoreChain is idempotent for
  // already-live folders.
  private async restoreWithFolderChains(ids: string[]): Promise<void> {
    const folderIds = new Set<string>();
    for (let i = 0; i < ids.length; i++) {
      const bookmark = await this.dao.findById(ids[i]);
      if (bookmark !== undefined && bookmark.folderId.length > 0) {
        folderIds.add(bookmark.folderId);
      }
    }
    await this.dao.restoreMany(ids);
    const chains: string[] = [];
    folderIds.forEach((folderId: string): void => {
      chains.push(folderId);
    });
    for (let i = 0; i < chains.length; i++) {
      await this.folderDao.restoreChain(chains[i]);
    }
  }

  private async purgeOne(id: string): Promise<void> {
    const bookmark = await this.dao.findById(id);
    if (bookmark !== undefined) {
      SnapshotStore.remove(bookmark.snapshotPath);
    }
    if (this.context !== undefined) {
      SnapshotStore.removeById(this.context, id);
      ReaderPrefs.clearPosition(this.context, id);
    }
    await this.dao.purge(id);
  }

  async purge(id: string): Promise<void> {
    await this.purgeOne(id);
    this.notify();
  }

  async purgeMany(ids: string[]): Promise<void> {
    if (ids.length === 0) {
      return;
    }
    for (let i = 0; i < ids.length; i++) {
      await this.purgeOne(ids[i]);
    }
    this.notify();
  }

  async purgeExpired(): Promise<number> {
    const ids = await this.dao.listExpiredIds(30);
    for (let i = 0; i < ids.length; i++) {
      await this.purgeOne(ids[i]);
    }
    // Folder rows leave after their bookmarks: tombstone first so the delete
    // cannot resurrect on a peer.
    const folderIds = await this.folderDao.listExpiredFolderIds(30);
    for (let i = 0; i < folderIds.length; i++) {
      await this.dao.addTombstone(folderIds[i], folderIds[i]);
      await this.folderDao.purgeLocal(folderIds[i]);
    }
    if (ids.length > 0 || folderIds.length > 0) {
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
      ReaderPrefs.clearPosition(this.context, id);
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
      this.carryLocalFields(chosen, existing, record.schema);
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

  // Resolves one imported path into a folder chain, creating missing levels.
  // Shared cache keys make an import batch O(distinct paths) in DB round trips.
  private async resolveFolderChain(segments: string[], cache: Map<string, string>): Promise<string> {
    let parentId = '';
    for (let i = 0; i < segments.length; i++) {
      if (segments[i].length === 0) {
        continue;
      }
      parentId = await this.folderDao.findOrCreate(parentId, segments[i], cache);
    }
    return parentId;
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
    const folderCache = new Map<string, string>();
    const markedFolderIds = new Set<string>();

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
      bookmark.siteName = domainOf(item.url);
      if (item.segments.length > 0) {
        bookmark.folderId = await this.resolveFolderChain(item.segments, folderCache);
        // Apply the browser semantic marker once per top folder (D13);
        // setKind is idempotent, repeated imports stay sync-silent.
        const kind = parsed.topMarks.get(item.segments[0]);
        if (kind !== undefined) {
          const top = await this.folderDao.findByParentAndName('', item.segments[0]);
          if (top !== undefined && !markedFolderIds.has(top.id)) {
            markedFolderIds.add(top.id);
            await this.folderDao.setKind(top.id, kind);
          }
        }
      }
      if (item.addedAt > 0) {
        bookmark.createdAt = item.addedAt;
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
    const folders = await this.folderDao.listAll(false);
    const document = new ExportDocument();
    document.exportedAt = Date.now();
    for (let i = 0; i < all.length; i++) {
      const exported = new ExportBookmark();
      exported.id = all[i].id;
      exported.url = all[i].url;
      exported.title = all[i].title;
      exported.description = all[i].description;
      exported.siteName = all[i].siteName;
      exported.note = all[i].note;
      exported.excerpt = all[i].excerpt;
      exported.tags = all[i].tags.slice();
      exported.folderId = all[i].folderId;
      exported.source = all[i].source;
      exported.createdAt = all[i].createdAt;
      exported.updatedAt = all[i].updatedAt;
      exported.readState = all[i].readState;
      exported.readAt = all[i].readAt;
      exported.starred = all[i].starred;
      exported.archived = all[i].archived;
      exported.deleted = all[i].deleted;
      document.items.push(exported);
    }
    for (let i = 0; i < folders.length; i++) {
      const exported = new ExportFolder();
      exported.id = folders[i].id;
      exported.parentId = folders[i].parentId;
      exported.name = folders[i].name;
      exported.position = folders[i].position;
      exported.kind = folders[i].kind;
      exported.createdAt = folders[i].createdAt;
      document.folders.push(exported);
    }
    return JSON.stringify(document, null, 2);
  }

  async exportHtml(): Promise<string> {
    const all = await this.dao.listAll(false);
    const folders = await this.folderDao.listAll(false);
    const roots = buildFolderTree(folders, new Map<string, number>());

    // Bookmarks filed under a live folder id; anything else (root or dangling
    // after eventual-consistency gaps) exports at root so nothing is lost.
    const liveIds = new Set<string>();
    for (let i = 0; i < folders.length; i++) {
      liveIds.add(folders[i].id);
    }
    const byFolder = new Map<string, Bookmark[]>();
    const rootBookmarks: Bookmark[] = [];
    for (let i = 0; i < all.length; i++) {
      const item = all[i];
      if (item.folderId.length > 0 && liveIds.has(item.folderId)) {
        const list = byFolder.get(item.folderId);
        if (list === undefined) {
          byFolder.set(item.folderId, [item]);
        } else {
          list.push(item);
        }
      } else {
        rootBookmarks.push(item);
      }
    }

    let html = '<!DOCTYPE NETSCAPE-Bookmark-file-1>\n';
    html += '<META HTTP-EQUIV="Content-Type" CONTENT="text/html; charset=UTF-8">\n';
    html += '<TITLE>流笺 Bookmarks</TITLE>\n<H1>流笺</H1>\n<DL><p>\n';
    rootBookmarks.sort(FlowRepository.byCreatedAtAsc);
    for (let i = 0; i < rootBookmarks.length; i++) {
      html += FlowRepository.anchorLine(rootBookmarks[i], '    ');
    }
    for (let i = 0; i < roots.length; i++) {
      html += FlowRepository.emitFolder(roots[i], 1, byFolder);
    }
    html += '</DL><p>\n';
    return html;
  }

  private static byCreatedAtAsc(a: Bookmark, b: Bookmark): number {
    if (a.createdAt !== b.createdAt) {
      return a.createdAt - b.createdAt;
    }
    return a.id < b.id ? -1 : 1;
  }

  private static emitFolder(node: FolderNode, depth: number, byFolder: Map<string, Bookmark[]>): string {
    const indent = '    '.repeat(depth);
    const seconds = Math.floor(node.folder.createdAt / 1000);
    // Browser semantic markers travel back out so marker-honoring importers
    // map the folder onto their own bar/unfiled roots instead of nesting a
    // duplicate (D13).
    const marker = node.folder.kind === 'toolbar' ? ' PERSONAL_TOOLBAR_FOLDER="true"'
      : node.folder.kind === 'unfiled' ? ' UNFILED_BOOKMARKS_FOLDER="true"' : '';
    let html = `${indent}<DT><H3 ADD_DATE="${seconds}"${marker}>${escapeHtml(node.folder.name)}</H3>\n`;
    html += `${indent}<DL><p>\n`;
    const items = byFolder.get(node.folder.id);
    if (items !== undefined) {
      items.sort(FlowRepository.byCreatedAtAsc);
      for (let i = 0; i < items.length; i++) {
        html += FlowRepository.anchorLine(items[i], `${indent}    `);
      }
    }
    for (let i = 0; i < node.children.length; i++) {
      html += FlowRepository.emitFolder(node.children[i], depth + 1, byFolder);
    }
    html += `${indent}</DL><p>\n`;
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
      if (this.context !== undefined) {
        ReaderPrefs.clearPosition(this.context, all[i].id);
      }
    }
    if (this.context !== undefined) {
      SnapshotStore.clearAll(this.context);
    }
    await this.dao.clearAll();
    this.notify();
  }
}
