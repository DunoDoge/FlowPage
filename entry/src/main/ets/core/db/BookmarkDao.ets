import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Bookmark } from '../../model/Bookmark';
import { BookmarkQuery } from '../../model/BookmarkQuery';
import { ConflictRecord } from '../../model/Conflict';
import { LibraryCounts } from '../../model/LibraryCounts';
import { TagCount } from '../../model/Tag';
import { Tombstone } from '../../model/Tombstone';
import { StreamFilter } from '../../common/Constants';
import { domainOf } from '../../common/UrlUtil';
import { Database } from './Database';

class WhereClause {
  sql: string = '';
  args: relationalStore.ValueType[] = [];
}

function escapeLike(value: string): string {
  let text = value.split('\\').join('\\\\');
  text = text.split('%').join('\\%');
  text = text.split('_').join('\\_');
  return text;
}

export class BookmarkDao {
  private toBucket(bookmark: Bookmark): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': bookmark.id,
      'url': bookmark.url,
      'url_key': bookmark.urlKey,
      'domain': domainOf(bookmark.url),
      'title': bookmark.title,
      'description': bookmark.description,
      'site_name': bookmark.siteName,
      'favicon_url': bookmark.faviconUrl,
      'cover_url': bookmark.coverUrl,
      'note': bookmark.note,
      'excerpt': bookmark.excerpt,
      'snapshot_path': bookmark.snapshotPath,
      'snapshot_status': bookmark.snapshotStatus,
      'snapshot_at': bookmark.snapshotAt,
      'search_text': bookmark.searchText,
      'source': bookmark.source,
      'folder_path': bookmark.folderPath,
      'read_state': bookmark.readState,
      'starred': bookmark.starred ? 1 : 0,
      'archived': bookmark.archived ? 1 : 0,
      'deleted': bookmark.deleted ? 1 : 0,
      'created_at': bookmark.createdAt,
      'updated_at': bookmark.updatedAt,
      'read_at': bookmark.readAt,
      'rev': bookmark.rev,
      'remote_etag': bookmark.remoteEtag,
      'dirty': bookmark.dirty ? 1 : 0,
      'link_status': bookmark.linkStatus,
      'link_checked_at': bookmark.linkCheckedAt,
      'device_id': bookmark.deviceId
    };
    return bucket;
  }

  private readRow(rs: relationalStore.ResultSet): Bookmark {
    const bookmark = new Bookmark();
    bookmark.id = rs.getString(rs.getColumnIndex('id'));
    bookmark.url = rs.getString(rs.getColumnIndex('url'));
    bookmark.urlKey = rs.getString(rs.getColumnIndex('url_key'));
    bookmark.title = rs.getString(rs.getColumnIndex('title'));
    bookmark.description = rs.getString(rs.getColumnIndex('description'));
    bookmark.siteName = rs.getString(rs.getColumnIndex('site_name'));
    bookmark.faviconUrl = rs.getString(rs.getColumnIndex('favicon_url'));
    bookmark.coverUrl = rs.getString(rs.getColumnIndex('cover_url'));
    bookmark.note = rs.getString(rs.getColumnIndex('note'));
    bookmark.excerpt = rs.getString(rs.getColumnIndex('excerpt'));
    bookmark.snapshotPath = rs.getString(rs.getColumnIndex('snapshot_path'));
    bookmark.snapshotStatus = rs.getLong(rs.getColumnIndex('snapshot_status'));
    bookmark.snapshotAt = rs.getLong(rs.getColumnIndex('snapshot_at'));
    bookmark.searchText = rs.getString(rs.getColumnIndex('search_text'));
    bookmark.source = rs.getLong(rs.getColumnIndex('source'));
    bookmark.folderPath = rs.getString(rs.getColumnIndex('folder_path'));
    bookmark.readState = rs.getLong(rs.getColumnIndex('read_state'));
    bookmark.starred = rs.getLong(rs.getColumnIndex('starred')) === 1;
    bookmark.archived = rs.getLong(rs.getColumnIndex('archived')) === 1;
    bookmark.deleted = rs.getLong(rs.getColumnIndex('deleted')) === 1;
    bookmark.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    bookmark.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    bookmark.readAt = rs.getLong(rs.getColumnIndex('read_at'));
    bookmark.rev = rs.getLong(rs.getColumnIndex('rev'));
    bookmark.remoteEtag = rs.getString(rs.getColumnIndex('remote_etag'));
    bookmark.dirty = rs.getLong(rs.getColumnIndex('dirty')) === 1;
    bookmark.linkStatus = rs.getLong(rs.getColumnIndex('link_status'));
    bookmark.linkCheckedAt = rs.getLong(rs.getColumnIndex('link_checked_at'));
    bookmark.deviceId = rs.getString(rs.getColumnIndex('device_id'));
    return bookmark;
  }

  async insert(bookmark: Bookmark): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await store.insert('bookmark', this.toBucket(bookmark));
      await this.syncTags(bookmark.id, bookmark.tags);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }

  async update(bookmark: Bookmark): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await this.writeRow(bookmark);
      await this.syncTags(bookmark.id, bookmark.tags);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }

  private async writeRow(bookmark: Bookmark): Promise<void> {
    const store = Database.getStore();
    const predicates = new relationalStore.RdbPredicates('bookmark');
    predicates.equalTo('id', bookmark.id);
    await store.update(this.toBucket(bookmark), predicates);
  }

  private async syncTags(bookmarkId: string, tags: string[], cache?: Map<string, string>): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM bookmark_tag WHERE bookmark_id = ?', [bookmarkId]);
    for (let i = 0; i < tags.length; i++) {
      const name = tags[i].trim();
      if (name.length === 0) {
        continue;
      }
      const tagId = await this.ensureTag(name, cache);
      await store.executeSql(
        'INSERT OR IGNORE INTO bookmark_tag (bookmark_id, tag_id) VALUES (?, ?)',
        [bookmarkId, tagId]
      );
    }
  }

  private async syncNewTags(bookmarkId: string, tags: string[], cache?: Map<string, string>): Promise<void> {
    const store = Database.getStore();
    for (let i = 0; i < tags.length; i++) {
      const name = tags[i].trim();
      if (name.length === 0) {
        continue;
      }
      const tagId = await this.ensureTag(name, cache);
      await store.executeSql(
        'INSERT OR IGNORE INTO bookmark_tag (bookmark_id, tag_id) VALUES (?, ?)',
        [bookmarkId, tagId]
      );
    }
  }

  private async ensureTag(name: string, cache?: Map<string, string>): Promise<string> {
    const store = Database.getStore();
    const nameKey = name.toLowerCase();
    if (cache !== undefined) {
      const cached = cache.get(nameKey);
      if (cached !== undefined) {
        return cached;
      }
    }
    const resultSet = await store.querySql('SELECT id FROM tag WHERE name_key = ?', [nameKey]);
    if (resultSet.goToFirstRow()) {
      const id = resultSet.getString(0);
      resultSet.close();
      if (cache !== undefined) {
        cache.set(nameKey, id);
      }
      return id;
    }
    resultSet.close();
    const id = util.generateRandomUUID(true);
    await store.executeSql(
      'INSERT INTO tag (id, name, name_key, created_at) VALUES (?, ?, ?, ?)',
      [id, name, nameKey, Date.now()]
    );
    if (cache !== undefined) {
      cache.set(nameKey, id);
    }
    return id;
  }

  private async loadTags(bookmarkId: string): Promise<string[]> {
    const store = Database.getStore();
    const tags: string[] = [];
    const resultSet = await store.querySql(
      'SELECT t.name AS name FROM bookmark_tag bt JOIN tag t ON t.id = bt.tag_id ' +
      'WHERE bt.bookmark_id = ? ORDER BY t.name',
      [bookmarkId]
    );
    while (resultSet.goToNextRow()) {
      tags.push(resultSet.getString(resultSet.getColumnIndex('name')));
    }
    resultSet.close();
    return tags;
  }

  private async fillTags(bookmarks: Bookmark[]): Promise<void> {
    if (bookmarks.length === 0) {
      return;
    }
    const store = Database.getStore();
    const map = new Map<string, string[]>();
    const chunk = 400;
    for (let start = 0; start < bookmarks.length; start = start + chunk) {
      const end = start + chunk < bookmarks.length ? start + chunk : bookmarks.length;
      const placeholders: string[] = [];
      const args: relationalStore.ValueType[] = [];
      for (let i = start; i < end; i++) {
        placeholders.push('?');
        args.push(bookmarks[i].id);
      }
      const resultSet = await store.querySql(
        'SELECT bt.bookmark_id AS bid, t.name AS name FROM bookmark_tag bt ' +
        `JOIN tag t ON t.id = bt.tag_id WHERE bt.bookmark_id IN (${placeholders.join(',')}) ` +
        'ORDER BY t.name',
        args
      );
      while (resultSet.goToNextRow()) {
        const bid = resultSet.getString(resultSet.getColumnIndex('bid'));
        const name = resultSet.getString(resultSet.getColumnIndex('name'));
        const existing = map.get(bid);
        if (existing === undefined) {
          map.set(bid, [name]);
        } else {
          existing.push(name);
        }
      }
      resultSet.close();
    }
    for (let i = 0; i < bookmarks.length; i++) {
      const item = bookmarks[i];
      const tags = map.get(item.id);
      item.tags = tags !== undefined ? tags : [];
      item.rebuildSearch();
    }
  }

  async listAll(includeDeleted: boolean): Promise<Bookmark[]> {
    const store = Database.getStore();
    const sql = includeDeleted
      ? 'SELECT * FROM bookmark ORDER BY created_at DESC'
      : 'SELECT * FROM bookmark WHERE deleted = 0 ORDER BY created_at DESC';
    const resultSet = await store.querySql(sql, []);
    const bookmarks: Bookmark[] = [];
    while (resultSet.goToNextRow()) {
      bookmarks.push(this.readRow(resultSet));
    }
    resultSet.close();
    await this.fillTags(bookmarks);
    return bookmarks;
  }

  private buildWhere(query: BookmarkQuery): WhereClause {
    const where = new WhereClause();
    const parts: string[] = [];
    if (query.filter === StreamFilter.TRASH) {
      parts.push('deleted = 1');
    } else {
      parts.push('deleted = 0');
      if (query.filter === StreamFilter.ARCHIVED) {
        parts.push('archived = 1');
      } else {
        parts.push('archived = 0');
        if (query.filter === StreamFilter.UNREAD) {
          parts.push('read_state = 0');
        }
        if (query.filter === StreamFilter.STARRED) {
          parts.push('starred = 1');
        }
      }
    }
    if (query.tag.length > 0) {
      parts.push(
        'EXISTS (SELECT 1 FROM bookmark_tag bt JOIN tag t ON t.id = bt.tag_id ' +
        'WHERE bt.bookmark_id = bookmark.id AND t.name = ?)'
      );
      where.args.push(query.tag);
    }
    const keyword = query.keyword.trim().toLowerCase();
    if (keyword.length > 0) {
      parts.push('search_text LIKE ? ESCAPE \'\\\'');
      where.args.push(`%${escapeLike(keyword)}%`);
    }
    where.sql = parts.join(' AND ');
    return where;
  }

  async queryPage(query: BookmarkQuery, offset: number, limit: number): Promise<Bookmark[]> {
    const store = Database.getStore();
    const where = this.buildWhere(query);
    const order = query.sort === 1 ? 'domain ASC, created_at DESC' : 'created_at DESC';
    const args: relationalStore.ValueType[] = [];
    for (let i = 0; i < where.args.length; i++) {
      args.push(where.args[i]);
    }
    args.push(limit + 1);
    args.push(offset);
    const resultSet = await store.querySql(
      `SELECT * FROM bookmark WHERE ${where.sql} ORDER BY ${order} LIMIT ? OFFSET ?`,
      args
    );
    const bookmarks: Bookmark[] = [];
    while (resultSet.goToNextRow()) {
      bookmarks.push(this.readRow(resultSet));
    }
    resultSet.close();
    await this.fillTags(bookmarks);
    return bookmarks;
  }

  async listForCard(limit: number): Promise<Bookmark[]> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT * FROM bookmark WHERE deleted = 0 AND archived = 0 ORDER BY created_at DESC LIMIT ?',
      [limit]
    );
    const bookmarks: Bookmark[] = [];
    while (resultSet.goToNextRow()) {
      bookmarks.push(this.readRow(resultSet));
    }
    resultSet.close();
    return bookmarks;
  }

  async summaryCounts(): Promise<LibraryCounts> {
    const store = Database.getStore();
    const counts = new LibraryCounts();
    const resultSet = await store.querySql(
      'SELECT ' +
      'COALESCE(SUM(CASE WHEN deleted = 0 AND archived = 0 THEN 1 ELSE 0 END), 0) AS total, ' +
      'COALESCE(SUM(CASE WHEN deleted = 0 AND archived = 0 AND read_state = 0 THEN 1 ELSE 0 END), 0) AS unread, ' +
      'COALESCE(SUM(CASE WHEN deleted = 0 AND archived = 0 AND starred = 1 THEN 1 ELSE 0 END), 0) AS starred, ' +
      'COALESCE(SUM(CASE WHEN deleted = 0 AND archived = 1 THEN 1 ELSE 0 END), 0) AS archived, ' +
      'COALESCE(SUM(CASE WHEN deleted = 1 THEN 1 ELSE 0 END), 0) AS trash ' +
      'FROM bookmark',
      []
    );
    if (resultSet.goToFirstRow()) {
      counts.total = resultSet.getLong(resultSet.getColumnIndex('total'));
      counts.unread = resultSet.getLong(resultSet.getColumnIndex('unread'));
      counts.starred = resultSet.getLong(resultSet.getColumnIndex('starred'));
      counts.archived = resultSet.getLong(resultSet.getColumnIndex('archived'));
      counts.trash = resultSet.getLong(resultSet.getColumnIndex('trash'));
    }
    resultSet.close();
    return counts;
  }

  async listUrlKeys(): Promise<Set<string>> {
    const store = Database.getStore();
    const keys = new Set<string>();
    const resultSet = await store.querySql('SELECT url_key FROM bookmark', []);
    while (resultSet.goToNextRow()) {
      keys.add(resultSet.getString(0));
    }
    resultSet.close();
    return keys;
  }

  async countCreatedSince(since: number): Promise<number> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT COUNT(*) AS cnt FROM bookmark WHERE deleted = 0 AND created_at >= ?',
      [since]
    );
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(0);
    }
    resultSet.close();
    return count;
  }

  async countConflicts(): Promise<number> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT COUNT(*) AS cnt FROM conflict', []);
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(0);
    }
    resultSet.close();
    return count;
  }

  async listConflicts(): Promise<ConflictRecord[]> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT * FROM conflict ORDER BY created_at DESC', []);
    const records: ConflictRecord[] = [];
    while (resultSet.goToNextRow()) {
      const record = new ConflictRecord();
      record.id = resultSet.getString(resultSet.getColumnIndex('id'));
      record.bookmarkId = resultSet.getString(resultSet.getColumnIndex('bookmark_id'));
      record.localJson = resultSet.getString(resultSet.getColumnIndex('local_json'));
      record.remoteJson = resultSet.getString(resultSet.getColumnIndex('remote_json'));
      record.reason = resultSet.getString(resultSet.getColumnIndex('reason'));
      record.createdAt = resultSet.getLong(resultSet.getColumnIndex('created_at'));
      records.push(record);
    }
    resultSet.close();
    return records;
  }

  async deleteConflict(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM conflict WHERE id = ?', [id]);
  }

  async clearConflicts(): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM conflict');
  }

  async findById(id: string): Promise<Bookmark | undefined> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT * FROM bookmark WHERE id = ?', [id]);
    let bookmark: Bookmark | undefined = undefined;
    if (resultSet.goToFirstRow()) {
      bookmark = this.readRow(resultSet);
    }
    resultSet.close();
    if (bookmark !== undefined) {
      bookmark.tags = await this.loadTags(bookmark.id);
      bookmark.rebuildSearch();
    }
    return bookmark;
  }

  async findByUrlKey(urlKey: string): Promise<Bookmark | undefined> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT * FROM bookmark WHERE url_key = ?', [urlKey]);
    let bookmark: Bookmark | undefined = undefined;
    if (resultSet.goToFirstRow()) {
      bookmark = this.readRow(resultSet);
    }
    resultSet.close();
    if (bookmark !== undefined) {
      bookmark.tags = await this.loadTags(bookmark.id);
    }
    return bookmark;
  }

  async setLinkStatus(id: string, status: number, checkedAt: number): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET link_status = ?, link_checked_at = ? WHERE id = ?',
      [status, checkedAt, id]
    );
  }

  async setRemoteEtagIfUnchanged(
    id: string,
    etag: string,
    expectedRev: number,
    expectedUpdatedAt: number
  ): Promise<boolean> {
    const store = Database.getStore();
    const values: relationalStore.ValuesBucket = {
      'remote_etag': etag,
      'dirty': 0
    };
    const predicates = new relationalStore.RdbPredicates('bookmark');
    predicates.equalTo('id', id);
    predicates.and();
    predicates.equalTo('rev', expectedRev);
    predicates.and();
    predicates.equalTo('updated_at', expectedUpdatedAt);
    const rows = await store.update(values, predicates);
    return rows > 0;
  }

  async clearRemoteEtags(): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('UPDATE bookmark SET remote_etag = \'\'', []);
  }

  async insertConflict(bookmarkId: string, localJson: string, remoteJson: string, reason: string): Promise<void> {
    const store = Database.getStore();
    const values: relationalStore.ValuesBucket = {
      'id': util.generateRandomUUID(true),
      'bookmark_id': bookmarkId,
      'local_json': localJson,
      'remote_json': remoteJson,
      'reason': reason,
      'created_at': Date.now()
    };
    await store.insert('conflict', values);
  }

  async setStarred(id: string, starred: boolean): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET starred = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [starred ? 1 : 0, Date.now(), id]
    );
  }

  async setArchived(id: string, archived: boolean): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET archived = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [archived ? 1 : 0, Date.now(), id]
    );
  }

  async setReadState(id: string, readState: number): Promise<void> {
    const store = Database.getStore();
    const readAt = readState === 2 ? Date.now() : 0;
    await store.executeSql(
      'UPDATE bookmark SET read_state = ?, read_at = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [readState, readAt, Date.now(), id]
    );
  }

  // column is a fixed literal from the three callers below, never user input.
  private async setSearchField(id: string, column: string, value: string): Promise<void> {
    const store = Database.getStore();
    const now = Date.now();
    store.beginTransaction();
    try {
      await store.executeSql(
        `UPDATE bookmark SET ${column} = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?`,
        [value, now, id]
      );
      const bookmark = await this.findById(id);
      if (bookmark !== undefined) {
        bookmark.rebuildSearch();
        await store.executeSql(
          'UPDATE bookmark SET search_text = ? WHERE id = ?',
          [bookmark.searchText, id]
        );
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }

  async setNote(id: string, note: string): Promise<void> {
    await this.setSearchField(id, 'note', note);
  }

  async setExcerpt(id: string, excerpt: string): Promise<void> {
    await this.setSearchField(id, 'excerpt', excerpt);
  }

  async setTitle(id: string, title: string): Promise<void> {
    await this.setSearchField(id, 'title', title);
  }

  async editContent(id: string, title: string, note: string, excerpt: string, tags: string[]): Promise<Bookmark | undefined> {
    const bookmark = await this.findById(id);
    if (bookmark === undefined) {
      return undefined;
    }
    bookmark.title = title;
    bookmark.note = note;
    bookmark.excerpt = excerpt;
    bookmark.tags = tags;
    bookmark.updatedAt = Date.now();
    bookmark.rev = bookmark.rev + 1;
    bookmark.dirty = true;
    bookmark.rebuildSearch();
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await this.writeRow(bookmark);
      await this.syncTags(bookmark.id, tags);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
    return bookmark;
  }

  async softDelete(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET deleted = 1, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [Date.now(), id]
    );
  }

  async restore(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET deleted = 0, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [Date.now(), id]
    );
  }

  async purge(id: string): Promise<void> {
    await this.addTombstone(id, id);
    await this.purgeLocal(id);
  }

  async purgeLocal(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM bookmark_tag WHERE bookmark_id = ?', [id]);
    await store.executeSql('DELETE FROM bookmark WHERE id = ?', [id]);
  }

  async addTombstone(id: string, remoteId: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'INSERT OR REPLACE INTO tombstone (id, remote_id, deleted_at, attempts, last_error) VALUES (?, ?, ?, 0, \'\')',
      [id, remoteId, Date.now()]
    );
  }

  async findTombstone(id: string): Promise<Tombstone | undefined> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT * FROM tombstone WHERE id = ?', [id]);
    let tombstone: Tombstone | undefined = undefined;
    if (resultSet.goToFirstRow()) {
      tombstone = this.readTombstone(resultSet);
    }
    resultSet.close();
    return tombstone;
  }

  async listTombstones(): Promise<Tombstone[]> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT * FROM tombstone ORDER BY deleted_at ASC', []);
    const tombstones: Tombstone[] = [];
    while (resultSet.goToNextRow()) {
      tombstones.push(this.readTombstone(resultSet));
    }
    resultSet.close();
    return tombstones;
  }

  async removeTombstone(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM tombstone WHERE id = ?', [id]);
  }

  async markTombstoneFailed(id: string, lastError: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE tombstone SET attempts = attempts + 1, last_error = ? WHERE id = ?',
      [lastError, id]
    );
  }

  private readTombstone(rs: relationalStore.ResultSet): Tombstone {
    const tombstone = new Tombstone();
    tombstone.id = rs.getString(rs.getColumnIndex('id'));
    tombstone.remoteId = rs.getString(rs.getColumnIndex('remote_id'));
    tombstone.deletedAt = rs.getLong(rs.getColumnIndex('deleted_at'));
    tombstone.attempts = rs.getLong(rs.getColumnIndex('attempts'));
    tombstone.lastError = rs.getString(rs.getColumnIndex('last_error'));
    return tombstone;
  }

  async purgeExpired(days: number): Promise<number> {
    const ids = await this.listExpiredIds(days);
    for (let i = 0; i < ids.length; i++) {
      await this.purge(ids[i]);
    }
    return ids.length;
  }

  async listExpiredIds(days: number): Promise<string[]> {
    const cutoff = Date.now() - days * 86400000;
    return this.listTrashBefore(cutoff);
  }

  private async listTrashBefore(cutoff: number): Promise<string[]> {
    const store = Database.getStore();
    const ids: string[] = [];
    const resultSet = await store.querySql(
      'SELECT id FROM bookmark WHERE deleted = 1 AND updated_at < ?',
      [cutoff]
    );
    while (resultSet.goToNextRow()) {
      ids.push(resultSet.getString(0));
    }
    resultSet.close();
    return ids;
  }

  async listTags(): Promise<TagCount[]> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT t.id AS id, t.name AS name, COUNT(b.id) AS cnt ' +
      'FROM tag t ' +
      'LEFT JOIN bookmark_tag bt ON bt.tag_id = t.id ' +
      'LEFT JOIN bookmark b ON b.id = bt.bookmark_id AND b.deleted = 0 ' +
      'GROUP BY t.id HAVING cnt > 0 ORDER BY cnt DESC, t.name ASC',
      []
    );
    const tags: TagCount[] = [];
    while (resultSet.goToNextRow()) {
      const tag = new TagCount();
      tag.id = resultSet.getString(resultSet.getColumnIndex('id'));
      tag.name = resultSet.getString(resultSet.getColumnIndex('name'));
      tag.count = resultSet.getLong(resultSet.getColumnIndex('cnt'));
      tags.push(tag);
    }
    resultSet.close();
    return tags;
  }

  private async findTagIdByNameKey(nameKey: string): Promise<string> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT id FROM tag WHERE name_key = ?', [nameKey]);
    let id = '';
    if (resultSet.goToFirstRow()) {
      id = resultSet.getString(0);
    }
    resultSet.close();
    return id;
  }

  private async listBookmarkIdsByTag(tagId: string): Promise<string[]> {
    const store = Database.getStore();
    const ids: string[] = [];
    const resultSet = await store.querySql(
      'SELECT bookmark_id FROM bookmark_tag WHERE tag_id = ?',
      [tagId]
    );
    while (resultSet.goToNextRow()) {
      ids.push(resultSet.getString(0));
    }
    resultSet.close();
    return ids;
  }

  private async tagNameOf(tagId: string): Promise<string> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT name FROM tag WHERE id = ?', [tagId]);
    let name = '';
    if (resultSet.goToFirstRow()) {
      name = resultSet.getString(0);
    }
    resultSet.close();
    return name;
  }

  // Snapshot the affected rows before mutating tag links: reads inside the transaction
  // see the pre-change tag set, so search_text must be computed from these copies.
  private async loadBookmarksByTag(tagId: string): Promise<Bookmark[]> {
    const ids = await this.listBookmarkIdsByTag(tagId);
    const bookmarks: Bookmark[] = [];
    for (let i = 0; i < ids.length; i++) {
      const bookmark = await this.findById(ids[i]);
      if (bookmark !== undefined) {
        bookmarks.push(bookmark);
      }
    }
    return bookmarks;
  }

  private dedupeTags(tags: string[]): string[] {
    const seen = new Set<string>();
    const result: string[] = [];
    for (let i = 0; i < tags.length; i++) {
      const key = tags[i].toLowerCase();
      if (!seen.has(key)) {
        seen.add(key);
        result.push(tags[i]);
      }
    }
    return result;
  }

  private remapTag(bookmarks: Bookmark[], fromName: string, toName: string): void {
    const from = fromName.toLowerCase();
    for (let i = 0; i < bookmarks.length; i++) {
      const next: string[] = [];
      const tags = bookmarks[i].tags;
      for (let j = 0; j < tags.length; j++) {
        if (tags[j].toLowerCase() !== from) {
          next.push(tags[j]);
        } else if (toName.length > 0) {
          next.push(toName);
        }
      }
      bookmarks[i].tags = this.dedupeTags(next);
    }
  }

  private async writeTagChange(bookmarks: Bookmark[]): Promise<void> {
    const store = Database.getStore();
    const now = Date.now();
    for (let i = 0; i < bookmarks.length; i++) {
      const bookmark = bookmarks[i];
      bookmark.rebuildSearch();
      await store.executeSql(
        'UPDATE bookmark SET updated_at = ?, rev = rev + 1, dirty = 1, search_text = ? WHERE id = ?',
        [now, bookmark.searchText, bookmark.id]
      );
    }
  }

  async renameTag(id: string, name: string): Promise<boolean> {
    const targetId = await this.findTagIdByNameKey(name.toLowerCase());
    if (targetId.length > 0 && targetId !== id) {
      await this.mergeTags(id, targetId);
      return true;
    }
    const store = Database.getStore();
    store.beginTransaction();
    try {
      const oldName = await this.tagNameOf(id);
      const affected = await this.loadBookmarksByTag(id);
      await store.executeSql(
        'UPDATE tag SET name = ?, name_key = ? WHERE id = ?',
        [name, name.toLowerCase(), id]
      );
      this.remapTag(affected, oldName, name);
      await this.writeTagChange(affected);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
    return false;
  }

  async deleteTag(id: string): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      const name = await this.tagNameOf(id);
      const affected = await this.loadBookmarksByTag(id);
      await store.executeSql('DELETE FROM bookmark_tag WHERE tag_id = ?', [id]);
      await store.executeSql('DELETE FROM tag WHERE id = ?', [id]);
      this.remapTag(affected, name, '');
      await this.writeTagChange(affected);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }

  async mergeTags(sourceId: string, targetId: string): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      const sourceName = await this.tagNameOf(sourceId);
      const targetName = await this.tagNameOf(targetId);
      const affected = await this.loadBookmarksByTag(sourceId);
      await store.executeSql(
        'INSERT OR IGNORE INTO bookmark_tag (bookmark_id, tag_id) ' +
        'SELECT bookmark_id, ? FROM bookmark_tag WHERE tag_id = ?',
        [targetId, sourceId]
      );
      await store.executeSql('DELETE FROM bookmark_tag WHERE tag_id = ?', [sourceId]);
      await store.executeSql('DELETE FROM tag WHERE id = ?', [sourceId]);
      this.remapTag(affected, sourceName, targetName);
      await this.writeTagChange(affected);
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }

  async insertBatch(bookmarks: Bookmark[]): Promise<void> {
    const store = Database.getStore();
    const tagCache = new Map<string, string>();
    store.beginTransaction();
    try {
      for (let i = 0; i < bookmarks.length; i++) {
        await store.insert('bookmark', this.toBucket(bookmarks[i]));
        await this.syncNewTags(bookmarks[i].id, bookmarks[i].tags, tagCache);
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }

  async backfillDomains(): Promise<number> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT id, url FROM bookmark WHERE domain = \'\'',
      []
    );
    const ids: string[] = [];
    const urls: string[] = [];
    while (resultSet.goToNextRow()) {
      ids.push(resultSet.getString(0));
      urls.push(resultSet.getString(1));
    }
    resultSet.close();
    for (let i = 0; i < ids.length; i++) {
      await store.executeSql('UPDATE bookmark SET domain = ? WHERE id = ?', [domainOf(urls[i]), ids[i]]);
    }
    return ids.length;
  }

  async clearAll(): Promise<void> {
    const store = Database.getStore();
    store.beginTransaction();
    try {
      await store.executeSql('DELETE FROM bookmark');
      await store.executeSql('DELETE FROM tag');
      await store.executeSql('DELETE FROM bookmark_tag');
      await store.executeSql('DELETE FROM conflict');
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
  }
}
