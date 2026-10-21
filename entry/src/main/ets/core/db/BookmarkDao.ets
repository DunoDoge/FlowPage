import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { Bookmark } from '../../model/Bookmark';
import { TagCount } from '../../model/Tag';
import { Tombstone } from '../../model/Tombstone';
import { Database } from './Database';

export class BookmarkDao {
  private toBucket(bookmark: Bookmark): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': bookmark.id,
      'url': bookmark.url,
      'url_key': bookmark.urlKey,
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
    await store.insert('bookmark', this.toBucket(bookmark));
    await this.syncTags(bookmark.id, bookmark.tags);
  }

  async update(bookmark: Bookmark): Promise<void> {
    const store = Database.getStore();
    const predicates = new relationalStore.RdbPredicates('bookmark');
    predicates.equalTo('id', bookmark.id);
    await store.update(this.toBucket(bookmark), predicates);
    await this.syncTags(bookmark.id, bookmark.tags);
  }

  private async syncTags(bookmarkId: string, tags: string[]): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM bookmark_tag WHERE bookmark_id = ?', [bookmarkId]);
    for (let i = 0; i < tags.length; i++) {
      const name = tags[i].trim();
      if (name.length === 0) {
        continue;
      }
      const tagId = await this.ensureTag(name);
      await store.executeSql(
        'INSERT OR IGNORE INTO bookmark_tag (bookmark_id, tag_id) VALUES (?, ?)',
        [bookmarkId, tagId]
      );
    }
  }

  private async ensureTag(name: string): Promise<string> {
    const store = Database.getStore();
    const nameKey = name.toLowerCase();
    const resultSet = await store.querySql('SELECT id FROM tag WHERE name_key = ?', [nameKey]);
    if (resultSet.goToFirstRow()) {
      const id = resultSet.getString(0);
      resultSet.close();
      return id;
    }
    resultSet.close();
    const id = util.generateRandomUUID(true);
    await store.executeSql(
      'INSERT INTO tag (id, name, name_key, created_at) VALUES (?, ?, ?, ?)',
      [id, name, nameKey, Date.now()]
    );
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
    const store = Database.getStore();
    const map = new Map<string, string[]>();
    const resultSet = await store.querySql(
      'SELECT bt.bookmark_id AS bid, t.name AS name FROM bookmark_tag bt ' +
      'JOIN tag t ON t.id = bt.tag_id ORDER BY t.name',
      []
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

  async updateFields(
    id: string,
    title: string,
    description: string,
    siteName: string,
    faviconUrl: string,
    coverUrl: string,
    snapshotPath: string,
    snapshotStatus: number,
    snapshotAt: number,
    searchText: string
  ): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET title = ?, description = ?, site_name = ?, favicon_url = ?, ' +
      'cover_url = ?, snapshot_path = ?, snapshot_status = ?, snapshot_at = ?, ' +
      'search_text = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [title, description, siteName, faviconUrl, coverUrl, snapshotPath,
        snapshotStatus, snapshotAt, searchText, Date.now(), id]
    );
  }

  async setLinkStatus(id: string, status: number, checkedAt: number): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE bookmark SET link_status = ?, link_checked_at = ? WHERE id = ?',
      [status, checkedAt, id]
    );
  }

  async setRemoteEtag(id: string, etag: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('UPDATE bookmark SET remote_etag = ?, dirty = 0 WHERE id = ?', [etag, id]);
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

  async setNote(id: string, note: string): Promise<void> {
    const store = Database.getStore();
    const now = Date.now();
    await store.executeSql(
      'UPDATE bookmark SET note = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [note, now, id]
    );
    const bookmark = await this.findById(id);
    if (bookmark !== undefined) {
      bookmark.rebuildSearch();
      await store.executeSql(
        'UPDATE bookmark SET search_text = ? WHERE id = ?',
        [bookmark.searchText, id]
      );
    }
  }

  async setExcerpt(id: string, excerpt: string): Promise<void> {
    const store = Database.getStore();
    const now = Date.now();
    await store.executeSql(
      'UPDATE bookmark SET excerpt = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [excerpt, now, id]
    );
    const bookmark = await this.findById(id);
    if (bookmark !== undefined) {
      bookmark.rebuildSearch();
      await store.executeSql(
        'UPDATE bookmark SET search_text = ? WHERE id = ?',
        [bookmark.searchText, id]
      );
    }
  }

  async setTitle(id: string, title: string): Promise<void> {
    const store = Database.getStore();
    const now = Date.now();
    await store.executeSql(
      'UPDATE bookmark SET title = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
      [title, now, id]
    );
    const bookmark = await this.findById(id);
    if (bookmark !== undefined) {
      bookmark.rebuildSearch();
      await store.executeSql(
        'UPDATE bookmark SET search_text = ? WHERE id = ?',
        [bookmark.searchText, id]
      );
    }
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
    const store = Database.getStore();
    await this.addTombstone(id, id);
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
    const store = Database.getStore();
    const cutoff = Date.now() - days * 86400000;
    const expired = await this.listTrashBefore(cutoff);
    for (let i = 0; i < expired.length; i++) {
      await this.purge(expired[i]);
    }
    return expired.length;
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
      'SELECT t.id AS id, t.name AS name, COUNT(bt.bookmark_id) AS cnt ' +
      'FROM tag t LEFT JOIN bookmark_tag bt ON bt.tag_id = t.id ' +
      'GROUP BY t.id ORDER BY cnt DESC, t.name ASC',
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

  async renameTag(id: string, name: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql(
      'UPDATE tag SET name = ?, name_key = ? WHERE id = ?',
      [name, name.toLowerCase(), id]
    );
  }

  async deleteTag(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM bookmark_tag WHERE tag_id = ?', [id]);
    await store.executeSql('DELETE FROM tag WHERE id = ?', [id]);
  }

  async mergeTags(sourceId: string, targetId: string): Promise<void> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT bookmark_id FROM bookmark_tag WHERE tag_id = ?',
      [sourceId]
    );
    const bookmarkIds: string[] = [];
    while (resultSet.goToNextRow()) {
      bookmarkIds.push(resultSet.getString(0));
    }
    resultSet.close();
    for (let i = 0; i < bookmarkIds.length; i++) {
      await store.executeSql(
        'INSERT OR IGNORE INTO bookmark_tag (bookmark_id, tag_id) VALUES (?, ?)',
        [bookmarkIds[i], targetId]
      );
    }
    await this.deleteTag(sourceId);
  }

  async count(): Promise<number> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT COUNT(*) AS cnt FROM bookmark WHERE deleted = 0', []);
    let count = 0;
    if (resultSet.goToFirstRow()) {
      count = resultSet.getLong(0);
    }
    resultSet.close();
    return count;
  }

  async clearAll(): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM bookmark');
    await store.executeSql('DELETE FROM tag');
    await store.executeSql('DELETE FROM bookmark_tag');
    await store.executeSql('DELETE FROM tombstone');
  }
}
