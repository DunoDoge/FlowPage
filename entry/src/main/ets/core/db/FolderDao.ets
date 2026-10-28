import { relationalStore } from '@kit.ArkData';
import { util } from '@kit.ArkTS';
import { hilog } from '@kit.PerformanceAnalysisKit';
import { Folder, FolderNode } from '../../model/Folder';
import { Database } from './Database';

// Sort siblings by position, then name for stable order across sync.
function sortNodes(nodes: FolderNode[]): void {
  nodes.sort((a: FolderNode, b: FolderNode): number => {
    if (a.folder.position !== b.folder.position) {
      return a.folder.position - b.folder.position;
    }
    if (a.folder.name !== b.folder.name) {
      return a.folder.name < b.folder.name ? -1 : 1;
    }
    return a.folder.id < b.folder.id ? -1 : 1;
  });
}

// Builds a display tree from flat rows. Defensive by contract: folders whose
// parent chain hits a cycle get the newest-updated member re-attached to root
// (edge dropped); folders with a missing parent stay hidden (dangling).
export function buildFolderTree(folders: Folder[], counts: Map<string, number>): FolderNode[] {
  const byId = new Map<string, Folder>();
  for (let i = 0; i < folders.length; i++) {
    if (!folders[i].deleted) {
      byId.set(folders[i].id, folders[i]);
    }
  }

  const cycleBreakers = new Set<string>();
  const ids: string[] = [];
  byId.forEach((folder: Folder) => {
    ids.push(folder.id);
  });
  for (let i = 0; i < ids.length; i++) {
    const start = byId.get(ids[i]);
    if (start === undefined) {
      continue;
    }
    const visited = new Set<string>([start.id]);
    let cur = start.parentId;
    while (cur.length > 0 && byId.has(cur)) {
      if (visited.has(cur)) {
        const members: string[] = [];
        let walker = cur;
        for (let guard = 0; guard <= byId.size; guard++) {
          if (members.indexOf(walker) >= 0) {
            break;
          }
          members.push(walker);
          const member = byId.get(walker);
          walker = member !== undefined ? member.parentId : '';
          if (walker.length === 0 || !byId.has(walker)) {
            break;
          }
        }
        let newest = '';
        let newestAt = -1;
        for (let m = 0; m < members.length; m++) {
          const member = byId.get(members[m]);
          if (member === undefined) {
            continue;
          }
          if (member.updatedAt > newestAt || (member.updatedAt === newestAt && member.id > newest)) {
            newestAt = member.updatedAt;
            newest = member.id;
          }
        }
        if (newest.length > 0) {
          cycleBreakers.add(newest);
          hilog.warn(0x0000, 'flowpage', 'folder cycle detected, dropping parent edge of %{public}s', newest);
        }
        break;
      }
      visited.add(cur);
      const next = byId.get(cur);
      cur = next !== undefined ? next.parentId : '';
    }
  }

  const nodes = new Map<string, FolderNode>();
  const roots: FolderNode[] = [];
  for (let i = 0; i < ids.length; i++) {
    const folder = byId.get(ids[i]);
    if (folder === undefined) {
      continue;
    }
    const node = new FolderNode();
    node.folder = folder;
    nodes.set(folder.id, node);
  }
  const nodeIds: string[] = [];
  nodes.forEach((node: FolderNode) => {
    nodeIds.push(node.folder.id);
  });
  for (let i = 0; i < nodeIds.length; i++) {
    const node = nodes.get(nodeIds[i]);
    const folder = byId.get(nodeIds[i]);
    if (node === undefined || folder === undefined) {
      continue;
    }
    const parentId = cycleBreakers.has(folder.id) ? '' : folder.parentId;
    const parent = parentId.length > 0 ? nodes.get(parentId) : undefined;
    if (parent !== undefined) {
      parent.children.push(node);
    } else if (parentId.length === 0) {
      roots.push(node);
    }
    // Missing parent and not a breaker: stays unattached, hidden from the tree.
  }

  const aggregate = (node: FolderNode, parentPath: string): number => {
    node.path = parentPath.length > 0 ? `${parentPath}/${node.folder.name}` : node.folder.name;
    const direct = counts.get(node.folder.id);
    node.directCount = direct !== undefined ? direct : 0;
    sortNodes(node.children);
    let total = node.directCount;
    for (let i = 0; i < node.children.length; i++) {
      total = total + aggregate(node.children[i], node.path);
    }
    node.totalCount = total;
    return total;
  };
  sortNodes(roots);
  for (let i = 0; i < roots.length; i++) {
    aggregate(roots[i], '');
  }
  return roots;
}

export class FolderDao {
  private toBucket(folder: Folder): relationalStore.ValuesBucket {
    const bucket: relationalStore.ValuesBucket = {
      'id': folder.id,
      'parent_id': folder.parentId,
      'name': folder.name,
      'position': folder.position,
      'kind': folder.kind,
      'created_at': folder.createdAt,
      'updated_at': folder.updatedAt,
      'rev': folder.rev,
      'dirty': folder.dirty ? 1 : 0,
      'remote_etag': folder.remoteEtag,
      'deleted': folder.deleted ? 1 : 0
    };
    return bucket;
  }

  private readRow(rs: relationalStore.ResultSet): Folder {
    const folder = new Folder();
    folder.id = rs.getString(rs.getColumnIndex('id'));
    folder.parentId = rs.getString(rs.getColumnIndex('parent_id'));
    folder.name = rs.getString(rs.getColumnIndex('name'));
    folder.position = rs.getLong(rs.getColumnIndex('position'));
    folder.kind = rs.getString(rs.getColumnIndex('kind'));
    folder.createdAt = rs.getLong(rs.getColumnIndex('created_at'));
    folder.updatedAt = rs.getLong(rs.getColumnIndex('updated_at'));
    folder.rev = rs.getLong(rs.getColumnIndex('rev'));
    folder.dirty = rs.getLong(rs.getColumnIndex('dirty')) === 1;
    folder.remoteEtag = rs.getString(rs.getColumnIndex('remote_etag'));
    folder.deleted = rs.getLong(rs.getColumnIndex('deleted')) === 1;
    return folder;
  }

  async insert(folder: Folder): Promise<void> {
    const store = Database.getStore();
    await store.insert('folder', this.toBucket(folder));
  }

  async update(folder: Folder): Promise<void> {
    const store = Database.getStore();
    const predicates = new relationalStore.RdbPredicates('folder');
    predicates.equalTo('id', folder.id);
    await store.update(this.toBucket(folder), predicates);
  }

  async findById(id: string): Promise<Folder | undefined> {
    const store = Database.getStore();
    const resultSet = await store.querySql('SELECT * FROM folder WHERE id = ?', [id]);
    let folder: Folder | undefined = undefined;
    if (resultSet.goToFirstRow()) {
      folder = this.readRow(resultSet);
    }
    resultSet.close();
    return folder;
  }

  async findByParentAndName(parentId: string, name: string): Promise<Folder | undefined> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT * FROM folder WHERE parent_id = ? AND name = ? AND deleted = 0',
      [parentId, name]
    );
    let folder: Folder | undefined = undefined;
    if (resultSet.goToFirstRow()) {
      folder = this.readRow(resultSet);
    }
    resultSet.close();
    return folder;
  }

  async listAll(includeDeleted: boolean): Promise<Folder[]> {
    const store = Database.getStore();
    const sql = includeDeleted
      ? 'SELECT * FROM folder ORDER BY position ASC, name ASC'
      : 'SELECT * FROM folder WHERE deleted = 0 ORDER BY position ASC, name ASC';
    const resultSet = await store.querySql(sql, []);
    const folders: Folder[] = [];
    while (resultSet.goToNextRow()) {
      folders.push(this.readRow(resultSet));
    }
    resultSet.close();
    return folders;
  }

  private async nextPosition(parentId: string): Promise<number> {
    const store = Database.getStore();
    const resultSet = await store.querySql(
      'SELECT COALESCE(MAX(position), -1) AS maxPos FROM folder WHERE parent_id = ?',
      [parentId]
    );
    let next = 0;
    if (resultSet.goToFirstRow()) {
      next = resultSet.getLong(resultSet.getColumnIndex('maxPos')) + 1;
    }
    resultSet.close();
    return next;
  }

  // cache key is `${parentId}\u0000${name}`; shared across one import batch.
  async findOrCreate(parentId: string, name: string, cache?: Map<string, string>): Promise<string> {
    const cacheKey = `${parentId}\u0000${name}`;
    if (cache !== undefined) {
      const cached = cache.get(cacheKey);
      if (cached !== undefined) {
        return cached;
      }
    }
    const existing = await this.findByParentAndName(parentId, name);
    if (existing !== undefined) {
      if (cache !== undefined) {
        cache.set(cacheKey, existing.id);
      }
      return existing.id;
    }
    const now = Date.now();
    const folder = new Folder();
    folder.id = util.generateRandomUUID(true);
    folder.parentId = parentId;
    folder.name = name;
    folder.position = await this.nextPosition(parentId);
    folder.createdAt = now;
    folder.updatedAt = now;
    folder.rev = 1;
    folder.dirty = true;
    await this.insert(folder);
    if (cache !== undefined) {
      cache.set(cacheKey, folder.id);
    }
    return folder.id;
  }

  async create(parentId: string, name: string): Promise<Folder | undefined> {
    const existing = await this.findByParentAndName(parentId, name);
    if (existing !== undefined) {
      return undefined;
    }
    const now = Date.now();
    const folder = new Folder();
    folder.id = util.generateRandomUUID(true);
    folder.parentId = parentId;
    folder.name = name;
    folder.position = await this.nextPosition(parentId);
    folder.createdAt = now;
    folder.updatedAt = now;
    folder.rev = 1;
    folder.dirty = true;
    await this.insert(folder);
    return folder;
  }

  // Idempotent browser-marker assignment (D13): an unchanged kind must not
  // bump rev/updatedAt/dirty, so re-importing the same file creates zero
  // folder sync uploads.
  async setKind(id: string, kind: string): Promise<void> {
    const folder = await this.findById(id);
    if (folder === undefined || folder.kind === kind) {
      return;
    }
    folder.kind = kind;
    folder.updatedAt = Date.now();
    folder.rev = folder.rev + 1;
    folder.dirty = true;
    await this.update(folder);
  }

  // false when a live sibling already owns the name.
  async rename(id: string, name: string): Promise<boolean> {
    const folder = await this.findById(id);
    if (folder === undefined) {
      return false;
    }
    const clash = await this.findByParentAndName(folder.parentId, name);
    if (clash !== undefined && clash.id !== id) {
      return false;
    }
    folder.name = name;
    folder.updatedAt = Date.now();
    folder.rev = folder.rev + 1;
    folder.dirty = true;
    await this.update(folder);
    return true;
  }

  // All folder ids living below `id` (excluding `id`), from live rows.
  async descendantIds(id: string): Promise<string[]> {
    const all = await this.listAll(false);
    const childrenOf = new Map<string, string[]>();
    for (let i = 0; i < all.length; i++) {
      const list = childrenOf.get(all[i].parentId);
      if (list === undefined) {
        childrenOf.set(all[i].parentId, [all[i].id]);
      } else {
        list.push(all[i].id);
      }
    }
    const ids: string[] = [];
    const queue: string[] = [id];
    while (queue.length > 0) {
      const shifted = queue.shift();
      if (shifted === undefined) {
        continue;
      }
      const current = shifted;
      const kids = childrenOf.get(current);
      if (kids === undefined) {
        continue;
      }
      for (let i = 0; i < kids.length; i++) {
        ids.push(kids[i]);
        queue.push(kids[i]);
      }
    }
    return ids;
  }

  // false when the target is the folder itself, one of its descendants, or a
  // live sibling of the target already owns the folder's name (the partial
  // unique index would reject the row and break the batch mid-way).
  // keepPosition: drag/batch moves only change the parent (D6) and must not
  // rewrite the sibling order; the row keeps its old position value.
  async move(id: string, newParentId: string, keepPosition: boolean = false): Promise<boolean> {
    if (id === newParentId) {
      return false;
    }
    if (newParentId.length > 0) {
      const below = await this.descendantIds(id);
      if (below.indexOf(newParentId) >= 0) {
        return false;
      }
      const target = await this.findById(newParentId);
      if (target === undefined || target.deleted) {
        return false;
      }
    }
    const folder = await this.findById(id);
    if (folder === undefined) {
      return false;
    }
    const clash = await this.findByParentAndName(newParentId, folder.name);
    if (clash !== undefined && clash.id !== id) {
      return false;
    }
    folder.parentId = newParentId;
    if (!keepPosition) {
      folder.position = await this.nextPosition(newParentId);
    }
    folder.updatedAt = Date.now();
    folder.rev = folder.rev + 1;
    folder.dirty = true;
    await this.update(folder);
    return true;
  }

  // Soft-deletes the folder subtree and every bookmark filed inside it.
  // Returns the number of affected bookmarks for the confirm dialog.
  async cascadeSoftDelete(id: string): Promise<number> {
    const store = Database.getStore();
    const ids = [id].concat(await this.descendantIds(id));
    let affected = 0;
    const resultSet = await store.querySql(
      `SELECT COUNT(*) AS cnt FROM bookmark WHERE deleted = 0 AND folder_id IN (${ids.map((one: string): string => '?').join(',')})`,
      ids
    );
    if (resultSet.goToFirstRow()) {
      affected = resultSet.getLong(resultSet.getColumnIndex('cnt'));
    }
    resultSet.close();
    const now = Date.now();
    store.beginTransaction();
    try {
      for (let i = 0; i < ids.length; i++) {
        await store.executeSql(
          'UPDATE folder SET deleted = 1, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
          [now, ids[i]]
        );
      }
      const chunk = 200;
      for (let start = 0; start < ids.length; start = start + chunk) {
        const end = start + chunk < ids.length ? start + chunk : ids.length;
        const placeholders: string[] = [];
        const args: relationalStore.ValueType[] = [now];
        for (let i = start; i < end; i++) {
          placeholders.push('?');
          args.push(ids[i]);
        }
        await store.executeSql(
          `UPDATE bookmark SET deleted = 1, updated_at = ?, rev = rev + 1, dirty = 1 ` +
          `WHERE folder_id IN (${placeholders.join(',')}) AND deleted = 0`,
          args
        );
      }
      store.commit();
    } catch (error) {
      store.rollBack();
      throw new Error('DB_WRITE_FAILED');
    }
    return affected;
  }

  // Revives this folder plus every soft-deleted ancestor so a bookmark
  // restored from the trash returns to its tree position (D5): the trash
  // lists bookmarks only, so without this the folder chain is unreachable
  // and dies with the 30-day purge. A live sibling holding the same
  // (parent, name) — creatable while this folder sat in the trash — forces
  // a deduped name; the partial unique index forbids a bare undelete.
  // Unknown or purged rows stop the walk: the bookmark stays dangling (D9).
  async restoreChain(id: string): Promise<number> {
    const seen = new Set<string>();
    let revived = 0;
    let current = id;
    while (current.length > 0 && !seen.has(current)) {
      seen.add(current);
      const folder = await this.findById(current);
      if (folder === undefined) {
        break;
      }
      if (folder.deleted) {
        const name = await this.freeReviveName(folder.parentId, folder.name);
        await Database.getStore().executeSql(
          'UPDATE folder SET deleted = 0, name = ?, updated_at = ?, rev = rev + 1, dirty = 1 WHERE id = ?',
          [name, Date.now(), folder.id]
        );
        revived = revived + 1;
      }
      current = folder.parentId;
    }
    return revived;
  }

  private async freeReviveName(parentId: string, name: string): Promise<string> {
    let candidate = name;
    for (let suffix = 2; suffix < 100; suffix++) {
      const clash = await this.findByParentAndName(parentId, candidate);
      if (clash === undefined) {
        return candidate;
      }
      candidate = `${name} (${suffix})`;
    }
    return `${name} ${Date.now()}`;
  }

  // Returns `name`, or a suffixed variant when a live sibling other than
  // `selfId` already owns it: remote landings must stay inside the partial
  // unique index, and a hard failure would retry (and fail) on every sync.
  async dedupedName(parentId: string, name: string, selfId: string): Promise<string> {
    const clash = await this.findByParentAndName(parentId, name);
    if (clash === undefined || clash.id === selfId) {
      return name;
    }
    return await this.freeReviveName(parentId, name);
  }

  // Counts used by the tree view: live bookmarks grouped by folder_id.
  async countByFolder(): Promise<Map<string, number>> {
    const store = Database.getStore();
    const map = new Map<string, number>();
    const resultSet = await store.querySql(
      'SELECT folder_id, COUNT(*) AS cnt FROM bookmark WHERE deleted = 0 AND folder_id <> \'\' GROUP BY folder_id',
      []
    );
    while (resultSet.goToNextRow()) {
      map.set(resultSet.getString(0), resultSet.getLong(1));
    }
    resultSet.close();
    return map;
  }

  async setFolderEtagIfUnchanged(
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
    const predicates = new relationalStore.RdbPredicates('folder');
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
    await store.executeSql('UPDATE folder SET remote_etag = \'\'', []);
  }

  async purgeLocal(id: string): Promise<void> {
    const store = Database.getStore();
    await store.executeSql('DELETE FROM folder WHERE id = ?', [id]);
  }

  async listExpiredFolderIds(days: number): Promise<string[]> {
    const store = Database.getStore();
    const cutoff = Date.now() - days * 86400000;
    const resultSet = await store.querySql(
      'SELECT id FROM folder WHERE deleted = 1 AND updated_at < ?',
      [cutoff]
    );
    const ids: string[] = [];
    while (resultSet.goToNextRow()) {
      ids.push(resultSet.getString(0));
    }
    resultSet.close();
    return ids;
  }
}
