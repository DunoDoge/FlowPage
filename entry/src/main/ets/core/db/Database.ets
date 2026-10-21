import { relationalStore } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const DB_NAME: string = 'flowpage.db';

const SQL_BOOKMARK: string =
  'CREATE TABLE IF NOT EXISTS bookmark (' +
  'id TEXT PRIMARY KEY, ' +
  'url TEXT NOT NULL, ' +
  'url_key TEXT NOT NULL, ' +
  'domain TEXT NOT NULL DEFAULT \'\', ' +
  'title TEXT NOT NULL DEFAULT \'\', ' +
  'description TEXT NOT NULL DEFAULT \'\', ' +
  'site_name TEXT NOT NULL DEFAULT \'\', ' +
  'favicon_url TEXT NOT NULL DEFAULT \'\', ' +
  'cover_url TEXT NOT NULL DEFAULT \'\', ' +
  'note TEXT NOT NULL DEFAULT \'\', ' +
  'excerpt TEXT NOT NULL DEFAULT \'\', ' +
  'snapshot_path TEXT NOT NULL DEFAULT \'\', ' +
  'snapshot_status INTEGER NOT NULL DEFAULT 0, ' +
  'snapshot_at INTEGER NOT NULL DEFAULT 0, ' +
  'search_text TEXT NOT NULL DEFAULT \'\', ' +
  'source INTEGER NOT NULL DEFAULT 0, ' +
  'folder_path TEXT NOT NULL DEFAULT \'\', ' +
  'read_state INTEGER NOT NULL DEFAULT 0, ' +
  'starred INTEGER NOT NULL DEFAULT 0, ' +
  'archived INTEGER NOT NULL DEFAULT 0, ' +
  'deleted INTEGER NOT NULL DEFAULT 0, ' +
  'created_at INTEGER NOT NULL, ' +
  'updated_at INTEGER NOT NULL, ' +
  'read_at INTEGER NOT NULL DEFAULT 0, ' +
  'rev INTEGER NOT NULL DEFAULT 1, ' +
  'remote_etag TEXT NOT NULL DEFAULT \'\', ' +
  'dirty INTEGER NOT NULL DEFAULT 1, ' +
  'link_status INTEGER NOT NULL DEFAULT 0, ' +
  'link_checked_at INTEGER NOT NULL DEFAULT 0, ' +
  'device_id TEXT NOT NULL DEFAULT \'\'' +
  ')';

const SQL_TAG: string =
  'CREATE TABLE IF NOT EXISTS tag (' +
  'id TEXT PRIMARY KEY, ' +
  'name TEXT NOT NULL, ' +
  'name_key TEXT NOT NULL, ' +
  'created_at INTEGER NOT NULL' +
  ')';

const SQL_BOOKMARK_TAG: string =
  'CREATE TABLE IF NOT EXISTS bookmark_tag (' +
  'bookmark_id TEXT NOT NULL, ' +
  'tag_id TEXT NOT NULL, ' +
  'PRIMARY KEY (bookmark_id, tag_id)' +
  ')';

const SQL_CONFLICT: string =
  'CREATE TABLE IF NOT EXISTS conflict (' +
  'id TEXT PRIMARY KEY, ' +
  'bookmark_id TEXT NOT NULL, ' +
  'local_json TEXT NOT NULL, ' +
  'remote_json TEXT NOT NULL, ' +
  'reason TEXT NOT NULL, ' +
  'created_at INTEGER NOT NULL' +
  ')';

const SQL_SYNC_STATE: string =
  'CREATE TABLE IF NOT EXISTS sync_state (' +
  'key TEXT PRIMARY KEY, ' +
  'value TEXT NOT NULL' +
  ')';

const SQL_TOMBSTONE: string =
  'CREATE TABLE IF NOT EXISTS tombstone (' +
  'id TEXT PRIMARY KEY, ' +
  'remote_id TEXT NOT NULL DEFAULT \'\', ' +
  'deleted_at INTEGER NOT NULL, ' +
  'attempts INTEGER NOT NULL DEFAULT 0, ' +
  'last_error TEXT NOT NULL DEFAULT \'\'' +
  ')';

const SQL_INDEXES: string[] = [
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_bookmark_url_key ON bookmark(url_key)',
  'CREATE INDEX IF NOT EXISTS idx_bookmark_stream ON bookmark(deleted, archived, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_bookmark_starred ON bookmark(deleted, starred, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_bookmark_read ON bookmark(deleted, read_state, created_at DESC)',
  'CREATE INDEX IF NOT EXISTS idx_bookmark_domain ON bookmark(deleted, domain)',
  'CREATE UNIQUE INDEX IF NOT EXISTS idx_tag_name_key ON tag(name_key)',
  'CREATE INDEX IF NOT EXISTS idx_bookmark_tag_tag ON bookmark_tag(tag_id)'
];

export class Database {
  private static store: relationalStore.RdbStore | undefined = undefined;

  static async init(context: common.Context, name: string = DB_NAME): Promise<relationalStore.RdbStore> {
    if (Database.store !== undefined) {
      return Database.store;
    }
    const config: relationalStore.StoreConfig = {
      name: name,
      securityLevel: relationalStore.SecurityLevel.S1
    };
    const store = await relationalStore.getRdbStore(context, config);
    await Database.applySchema(store);
    Database.store = store;
    return store;
  }

  // Idempotent: safe for both a fresh store and an existing one missing later columns.
  static async applySchema(store: relationalStore.RdbStore): Promise<void> {
    await store.executeSql(SQL_BOOKMARK);
    await store.executeSql(SQL_TAG);
    await store.executeSql(SQL_BOOKMARK_TAG);
    await store.executeSql(SQL_CONFLICT);
    await store.executeSql(SQL_SYNC_STATE);
    await store.executeSql(SQL_TOMBSTONE);
    await Database.addColumn(store, 'dirty INTEGER NOT NULL DEFAULT 1');
    await Database.addColumn(store, 'link_status INTEGER NOT NULL DEFAULT 0');
    await Database.addColumn(store, 'link_checked_at INTEGER NOT NULL DEFAULT 0');
    await Database.addColumn(store, 'domain TEXT NOT NULL DEFAULT \'\'');
    for (let i = 0; i < SQL_INDEXES.length; i++) {
      await store.executeSql(SQL_INDEXES[i]);
    }
  }

  private static async addColumn(store: relationalStore.RdbStore, definition: string): Promise<void> {
    try {
      await store.executeSql(`ALTER TABLE bookmark ADD COLUMN ${definition}`);
    } catch (error) {
    }
  }

  static getStore(): relationalStore.RdbStore {
    if (Database.store === undefined) {
      throw new Error('Database is not initialized');
    }
    return Database.store;
  }

  static async reset(): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM bookmark');
    await store.executeSql('DELETE FROM tag');
    await store.executeSql('DELETE FROM bookmark_tag');
    await store.executeSql('DELETE FROM conflict');
    await store.executeSql('DELETE FROM sync_state');
    await store.executeSql('DELETE FROM tombstone');
  }
}
