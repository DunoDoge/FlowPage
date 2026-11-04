import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { FolderDao } from '../../../main/ets/core/db/FolderDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { Folder } from '../../../main/ets/model/Folder';
import { SyncRecord } from '../../../main/ets/core/sync/SyncRecord';
import { FolderSyncRecord } from '../../../main/ets/core/sync/FolderSyncRecord';
import { SyncEngine, SyncReport } from '../../../main/ets/core/sync/SyncEngine';
import { SyncErrorText } from '../../../main/ets/core/sync/SyncErrorText';
import { SyncTransport } from '../../../main/ets/core/sync/SyncTransport';
import { WebDavRetryPlanner } from '../../../main/ets/core/sync/WebDavRetryPlanner';
import { RemoteItem, WebDavResponse } from '../../../main/ets/core/sync/WebDavTypes';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource } from '../../../main/ets/common/Constants';

class StoredFile {
  json: string = '';
  etag: string = '';
}

class FakeTransport implements SyncTransport {
  files: Map<string, StoredFile> = new Map<string, StoredFile>();
  folderFiles: Map<string, StoredFile> = new Map<string, StoredFile>();
  tombstones: Set<string> = new Set<string>();
  failDelete: boolean = false;
  // Ordered upload calls across collections: 'folder:<id>' / 'item:<id>'.
  callLog: string[] = [];
  // Emulates the retrying real transport: each put() serves up to this many
  // PUT_429 responses internally before succeeding; a 3rd consecutive 429
  // surfaces as a thrown PUT_429, matching WebDavRetryPlanner.MAX_ATTEMPTS.
  transientPutFailures: number = 0;
  // Emulates the transport throttle circuit: after this many successful
  // puts, every further request throws THROTTLED_ABORT (hardThrottled).
  // -1 disables the circuit.
  abortAfterPuts: number = -1;
  private putsDone: number = 0;
  private seq: number = 0;

  private nextEtag(): string {
    this.seq = this.seq + 1;
    return `"e${this.seq}"`;
  }

  async test(): Promise<number> {
    return 207;
  }

  async ensureBase(): Promise<void> {
  }

  private throttled(): boolean {
    return this.abortAfterPuts >= 0 && this.putsDone >= this.abortAfterPuts;
  }

  private async listMap(map: Map<string, StoredFile>): Promise<RemoteItem[]> {
    const items: RemoteItem[] = [];
    map.forEach((file: StoredFile, name: string) => {
      const item = new RemoteItem();
      item.name = name;
      item.etag = file.etag;
      items.push(item);
    });
    return items;
  }

  async listItems(): Promise<RemoteItem[]> {
    return this.listMap(this.files);
  }

  async listFolders(): Promise<RemoteItem[]> {
    return this.listMap(this.folderFiles);
  }

  async listTombstones(): Promise<string[]> {
    const ids: string[] = [];
    this.tombstones.forEach((id: string) => {
      ids.push(id);
    });
    return ids;
  }

  async putTombstone(id: string): Promise<void> {
    if (this.throttled()) {
      throw new Error('THROTTLED_ABORT');
    }
    this.tombstones.add(id);
  }

  private async readMap(map: Map<string, StoredFile>, name: string): Promise<WebDavResponse> {
    const response = new WebDavResponse();
    const file = map.get(name);
    if (file === undefined) {
      response.status = 404;
      return response;
    }
    response.status = 200;
    response.body = file.json;
    response.etag = file.etag;
    return response;
  }

  async get(name: string): Promise<WebDavResponse> {
    if (this.throttled()) {
      throw new Error('THROTTLED_ABORT');
    }
    return this.readMap(this.files, name);
  }

  async getFolder(name: string): Promise<WebDavResponse> {
    if (this.throttled()) {
      throw new Error('THROTTLED_ABORT');
    }
    return this.readMap(this.folderFiles, name);
  }

  private async writeMap(map: Map<string, StoredFile>, name: string, json: string): Promise<string> {
    const stored = new StoredFile();
    stored.json = json;
    stored.etag = this.nextEtag();
    map.set(name, stored);
    return stored.etag;
  }

  // Shared upload gate + bookkeeping so item and folder puts cannot drift.
  private trackPut(kind: string, name: string): void {
    if (this.throttled()) {
      throw new Error('THROTTLED_ABORT');
    }
    this.callLog.push(`${kind}:${name}`);
  }

  private async commitPut(map: Map<string, StoredFile>, name: string, json: string): Promise<string> {
    const etag = await this.writeMap(map, name, json);
    this.putsDone = this.putsDone + 1;
    return etag;
  }

  async put(name: string, json: string, etag: string): Promise<string> {
    this.trackPut('item', name);
    let attempts = 0;
    while (true) {
      attempts = attempts + 1;
      if (this.transientPutFailures > 0) {
        this.transientPutFailures = this.transientPutFailures - 1;
        if (attempts >= WebDavRetryPlanner.MAX_ATTEMPTS) {
          throw new Error('PUT_429');
        }
        continue;
      }
      return this.commitPut(this.files, name, json);
    }
  }

  async putFolder(name: string, json: string, etag: string): Promise<string> {
    this.trackPut('folder', name);
    return this.commitPut(this.folderFiles, name, json);
  }

  private async removeFromMap(map: Map<string, StoredFile>, name: string): Promise<void> {
    if (this.failDelete) {
      throw new Error('DELETE_403');
    }
    map.delete(name);
  }

  async remove(name: string): Promise<void> {
    await this.removeFromMap(this.files, name);
  }

  async removeFolder(name: string): Promise<void> {
    await this.removeFromMap(this.folderFiles, name);
  }

  seed(name: string, json: string, etag: string): void {
    const stored = new StoredFile();
    stored.json = json;
    stored.etag = etag;
    this.files.set(name, stored);
  }

  seedFolder(name: string, json: string, etag: string): void {
    const stored = new StoredFile();
    stored.json = json;
    stored.etag = etag;
    this.folderFiles.set(name, stored);
  }
}

function remoteRecord(id: string, url: string, title: string, updatedAt: number): SyncRecord {
  const record = new SyncRecord();
  record.id = id;
  record.url = url;
  record.title = title;
  record.createdAt = updatedAt;
  record.updatedAt = updatedAt;
  record.rev = 1;
  return record;
}

function remoteFolder(id: string, name: string, updatedAt: number): FolderSyncRecord {
  const record = new FolderSyncRecord();
  record.id = id;
  record.name = name;
  record.createdAt = updatedAt;
  record.updatedAt = updatedAt;
  record.rev = 1;
  return record;
}

export default function syncEngineTest() {
  describe('SyncEngineTest', () => {
    let context: common.Context | undefined = undefined;

    beforeAll(async () => {
      const ability: UIAbility = await abilityDelegatorRegistry.getAbilityDelegator().getCurrentTopAbility();
      context = ability.context;
      await Database.init(context, 'flowpage_engine_test.db');
      await FlowRepository.get().init(context);
      await Database.reset();
    });

    beforeEach(async () => {
      await Database.reset();
    });

    it('uploadsThenSkipsOnSecondSync', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-upload', '上传', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const transport = new FakeTransport();
      const first: SyncReport = await SyncEngine.run(transport, context);
      expect(first.uploaded).assertEqual(1);
      expect(first.failed).assertEqual(0);
      expect(transport.files.size).assertEqual(1);
      const loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.dirty).assertFalse();
        expect(loaded.remoteEtag.length > 0).assertTrue();
      }
      const second: SyncReport = await SyncEngine.run(transport, context);
      expect(second.uploaded).assertEqual(0);
      expect(second.downloaded).assertEqual(0);
      expect(second.skipped).assertEqual(1);
      expect(second.failed).assertEqual(0);
    });

    it('downloadsNewRemoteItems', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const transport = new FakeTransport();
      transport.seed('remote-one', remoteRecord(
        'remote-one',
        'https://example.com/remote-one',
        '远端一笺',
        Date.now()
      ).toJson(), '"r1"');
      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(1);
      const loaded = await new BookmarkDao().findById('remote-one');
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.title).assertEqual('远端一笺');
        expect(loaded.remoteEtag).assertEqual('"r1"');
      }
    });

    it('deletesRemoteFileForTombstone', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-purge', '彻底删除', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const transport = new FakeTransport();
      transport.seed(bookmark.id, '{}', '"r1"');
      await dao.purge(bookmark.id);
      const report = await SyncEngine.run(transport, context);
      expect(report.deleted).assertEqual(1);
      expect(report.failed).assertEqual(0);
      expect(transport.files.size).assertEqual(0);
      expect(transport.tombstones.has(bookmark.id)).assertTrue();
      expect((await dao.findTombstone(bookmark.id)) === undefined).assertTrue();
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
    });

    it('keepsTombstoneWhenRemoteDeleteFails', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-retry', '重试删除', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const transport = new FakeTransport();
      transport.seed(bookmark.id, '{}', '"r1"');
      transport.failDelete = true;
      await dao.purge(bookmark.id);
      const report = await SyncEngine.run(transport, context);
      expect(report.deleted).assertEqual(0);
      expect(report.failed).assertEqual(1);
      expect(report.firstFailure).assertContain('403');
      expect(transport.tombstones.has(bookmark.id)).assertTrue();
      const tombstone = await dao.findTombstone(bookmark.id);
      expect(tombstone === undefined).assertFalse();
      if (tombstone !== undefined) {
        expect(tombstone.attempts).assertEqual(1);
      }
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
    });

    it('neverRedownloadsTombstonedItem', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-no-resurrect', '不复活', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const transport = new FakeTransport();
      transport.seed(bookmark.id, remoteRecord(
        bookmark.id,
        bookmark.url,
        '远端旧版本',
        bookmark.updatedAt + 10000
      ).toJson(), '"r2"');
      transport.failDelete = true;
      await dao.purge(bookmark.id);
      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(0);
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
    });

    it('purgesLocalWhenRemoteTombstoneArrives', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-peer-purge', '对端删除', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"r1"', bookmark.rev, bookmark.updatedAt);
      const transport = new FakeTransport();
      transport.seed(bookmark.id, remoteRecord(
        bookmark.id,
        bookmark.url,
        bookmark.title,
        bookmark.updatedAt
      ).toJson(), '"r1"');
      transport.tombstones.add(bookmark.id);
      const report: SyncReport = await SyncEngine.run(transport, context);
      expect(report.failed).assertEqual(0);
      expect(report.downloaded).assertEqual(0);
      expect(report.uploaded).assertEqual(0);
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
      expect(transport.files.size).assertEqual(0);
    });

    it('neverReuploadsWhenRemoteFileIsGoneButTombstoneExists', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-peer-gone', '远端已删', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"r1"', bookmark.rev, bookmark.updatedAt);
      const transport = new FakeTransport();
      transport.tombstones.add(bookmark.id);
      const report: SyncReport = await SyncEngine.run(transport, context);
      expect(report.uploaded).assertEqual(0);
      expect(report.downloaded).assertEqual(0);
      expect((await dao.findById(bookmark.id)) === undefined).assertTrue();
      expect(transport.files.size).assertEqual(0);
    });

    it('reuploadsWhenRemoteFileWasRemovedExternally', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/engine-remote-gone', '远端丢了', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"old"', bookmark.rev, bookmark.updatedAt);
      const transport = new FakeTransport();
      const report = await SyncEngine.run(transport, context);
      expect(report.uploaded).assertEqual(1);
      expect(transport.files.size).assertEqual(1);
      expect((await dao.findById(bookmark.id)) === undefined).assertFalse();
    });

    it('tagMergeDoesNotOverwriteRemoteEditOfTargetOnlyBookmark', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const targetOnly = Bookmark.create('https://example.com/merge-sync-target', '本地旧标题', BookmarkSource.MANUAL);
      targetOnly.updatedAt = Date.now() - 10000;
      targetOnly.tags = ['目标组'];
      targetOnly.rebuildSearch();
      await dao.insert(targetOnly);
      await dao.setRemoteEtagIfUnchanged(targetOnly.id, '"r1"', targetOnly.rev, targetOnly.updatedAt);
      const sourceOnly = Bookmark.create('https://example.com/merge-sync-source', '源标签笺', BookmarkSource.MANUAL);
      sourceOnly.tags = ['源组'];
      sourceOnly.rebuildSearch();
      await dao.insert(sourceOnly);

      const transport = new FakeTransport();
      const remote = new SyncRecord();
      remote.id = targetOnly.id;
      remote.url = targetOnly.url;
      remote.title = '远端新修改';
      remote.createdAt = targetOnly.createdAt;
      remote.updatedAt = Date.now() - 5000;
      remote.rev = 2;
      transport.seed(targetOnly.id, remote.toJson(), '"r2"');

      const tags = await dao.listTags();
      let sourceId = '';
      let targetId = '';
      for (let i = 0; i < tags.length; i++) {
        if (tags[i].name === '源组') {
          sourceId = tags[i].id;
        }
        if (tags[i].name === '目标组') {
          targetId = tags[i].id;
        }
      }
      await dao.mergeTags(sourceId, targetId);
      const afterMerge = await dao.findById(targetOnly.id);
      expect(afterMerge === undefined).assertFalse();
      if (afterMerge !== undefined) {
        expect(afterMerge.dirty).assertFalse();
      }

      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(1);
      const after = await dao.findById(targetOnly.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.title).assertEqual('远端新修改');
        expect(after.dirty).assertFalse();
      }
    });

    it('downloadKeepsLocalFolderForLegacyRecord', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const folder = await FlowRepository.get().createFolder('', '工作');
      expect(folder === undefined).assertFalse();
      const local = Bookmark.create('https://example.com/keep-folder', '本地标题', BookmarkSource.IMPORT);
      local.updatedAt = Date.now() - 10000;
      if (folder !== undefined) {
        local.folderId = folder.id;
      }
      await dao.insert(local);
      await dao.setRemoteEtagIfUnchanged(local.id, '"r1"', local.rev, local.updatedAt);

      const transport = new FakeTransport();
      const remote = new SyncRecord();
      remote.schema = 1;
      remote.id = local.id;
      remote.url = local.url;
      remote.title = '远端标题';
      remote.createdAt = local.createdAt;
      remote.updatedAt = Date.now() - 5000;
      remote.rev = 2;
      transport.seed(local.id, remote.toJson(), '"r2"');

      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(1);
      const after = await dao.findById(local.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined && folder !== undefined) {
        expect(after.title).assertEqual('远端标题');
        expect(after.folderId).assertEqual(folder.id);
        expect(after.source).assertEqual(BookmarkSource.IMPORT);
      }
    });

    it('downloadAppliesRemoteFolderFromSchemaThree', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const localFolder = await repo.createFolder('', '本地旧文件夹');
      expect(localFolder === undefined).assertFalse();
      const remoteFolder = await repo.createFolder('', '远端新文件夹');
      const local = Bookmark.create('https://example.com/schema3-folder', '本地标题', BookmarkSource.IMPORT);
      local.updatedAt = Date.now() - 10000;
      if (localFolder !== undefined) {
        local.folderId = localFolder.id;
      }
      await dao.insert(local);
      await dao.setRemoteEtagIfUnchanged(local.id, '"r1"', local.rev, local.updatedAt);

      const transport = new FakeTransport();
      const remote = new SyncRecord();
      remote.id = local.id;
      remote.url = local.url;
      remote.title = '远端标题';
      remote.createdAt = local.createdAt;
      remote.updatedAt = Date.now() - 5000;
      remote.rev = 2;
      remote.source = BookmarkSource.SHARE;
      if (remoteFolder !== undefined) {
        remote.folderId = remoteFolder.id;
      }
      transport.seed(local.id, remote.toJson(), '"r2"');

      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(1);
      const after = await dao.findById(local.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined && remoteFolder !== undefined) {
        expect(after.folderId).assertEqual(remoteFolder.id);
        expect(after.source).assertEqual(BookmarkSource.SHARE);
      }
    });

    it('restoredLocalConflictUploadsOnNextSync', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/restore-upload', '原版', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      await dao.setRemoteEtagIfUnchanged(bookmark.id, '"r1"', bookmark.rev, bookmark.updatedAt);
      const local = SyncRecord.fromBookmark(bookmark);
      local.title = '本地恢复版本';
      const remote = SyncRecord.fromBookmark(bookmark);
      remote.title = '远端旧版本';
      remote.updatedAt = Date.now() - 5000;
      remote.rev = 2;
      await dao.insertConflict(bookmark.id, local.toJson(), remote.toJson(), 'lww-remote-wins');
      const records = await FlowRepository.get().listConflicts();
      expect(records.length).assertEqual(1);
      const restored = await FlowRepository.get().resolveConflict(records[0].id, true);
      expect(restored).assertTrue();

      const transport = new FakeTransport();
      transport.seed(bookmark.id, remote.toJson(), '"r2"');
      const report = await SyncEngine.run(transport, context);
      expect(report.uploaded).assertEqual(1);
      expect(report.downloaded).assertEqual(0);
      const stored = transport.files.get(bookmark.id);
      expect(stored === undefined).assertFalse();
      if (stored !== undefined) {
        expect(stored.json.indexOf('本地恢复版本') >= 0).assertTrue();
      }
    });

    it('folderRenameSyncsAsSingleRecord', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', '开发');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      const bookmark = Bookmark.create('https://example.com/folder-rename', '成员', BookmarkSource.MANUAL);
      bookmark.folderId = folder.id;
      await new BookmarkDao().insert(bookmark);

      const transport = new FakeTransport();
      const first = await SyncEngine.run(transport, context);
      expect(first.uploaded).assertEqual(2);
      expect(first.failed).assertEqual(0);

      const renamed = await repo.renameFolder(folder.id, '工作');
      expect(renamed).assertTrue();
      const second = await SyncEngine.run(transport, context);
      expect(second.uploaded).assertEqual(1);
      expect(second.failed).assertEqual(0);
      const stored = transport.folderFiles.get(folder.id);
      expect(stored === undefined).assertFalse();
      if (stored !== undefined) {
        expect(stored.json.indexOf('工作') >= 0).assertTrue();
      }
      const bookmarkAfter = await new BookmarkDao().findById(bookmark.id);
      expect(bookmarkAfter === undefined).assertFalse();
      if (bookmarkAfter !== undefined) {
        expect(bookmarkAfter.folderId).assertEqual(folder.id);
        expect(bookmarkAfter.dirty).assertFalse();
      }
    });

    it('folderLwwRemoteRenameWins', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', '本地名');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      const folderDao = new FolderDao();
      await folderDao.setFolderEtagIfUnchanged(folder.id, '"r1"', folder.rev, folder.updatedAt);

      const transport = new FakeTransport();
      const remote = remoteFolder(folder.id, '远端名', Date.now());
      transport.seedFolder(folder.id, remote.toJson(), '"r2"');

      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(1);
      const after = await folderDao.findById(folder.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.name).assertEqual('远端名');
        expect(after.dirty).assertFalse();
      }
    });

    it('folderKindSyncsBothWays', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', '书签栏');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      const folderDao = new FolderDao();
      await folderDao.setKind(folder.id, 'toolbar');

      const transport = new FakeTransport();
      await SyncEngine.run(transport, context);
      const stored = transport.folderFiles.get(folder.id);
      expect(stored === undefined).assertFalse();
      if (stored !== undefined) {
        expect(stored.json.indexOf('"kind":"toolbar"') >= 0).assertTrue();
      }

      const remoteOnly = remoteFolder('remote-folder-kind', '其他书签', Date.now());
      remoteOnly.kind = 'unfiled';
      transport.seedFolder('remote-folder-kind', remoteOnly.toJson(), '"rk1"');
      await SyncEngine.run(transport, context);
      const landed = await folderDao.findById('remote-folder-kind');
      expect(landed === undefined).assertFalse();
      if (landed !== undefined) {
        expect(landed.kind).assertEqual('unfiled');
      }
    });

    it('folderTombstoneRemovesRemoteFolderFile', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', '待删除');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      const dao = new BookmarkDao();
      const folderDao = new FolderDao();
      const transport = new FakeTransport();
      const record = FolderSyncRecord.fromFolder(folder);
      transport.seedFolder(folder.id, record.toJson(), '"r1"');
      await dao.addTombstone(folder.id, folder.id);
      await folderDao.purgeLocal(folder.id);

      const report = await SyncEngine.run(transport, context);
      expect(report.deleted).assertEqual(1);
      expect(report.failed).assertEqual(0);
      expect(transport.folderFiles.size).assertEqual(0);
      expect(transport.tombstones.has(folder.id)).assertTrue();
      expect((await dao.findTombstone(folder.id)) === undefined).assertTrue();
    });

    it('bookmarkArrivesBeforeFolderStaysVisible', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const dao = new BookmarkDao();
      const folderId = 'folder-late';
      const record = remoteRecord('bookmark-early', 'https://example.com/early', '先到书签', Date.now());
      record.folderId = folderId;

      const transport = new FakeTransport();
      transport.seed('bookmark-early', record.toJson(), '"b1"');
      const first = await SyncEngine.run(transport, context);
      expect(first.downloaded).assertEqual(1);

      const bookmark = await dao.findById('bookmark-early');
      expect(bookmark === undefined).assertFalse();
      if (bookmark !== undefined) {
        expect(bookmark.folderId).assertEqual(folderId);
      }
      let tree = await repo.folderTree();
      expect(tree.length).assertEqual(0);

      const folderRecord = remoteFolder(folderId, '迟到文件夹', Date.now());
      transport.seedFolder(folderId, folderRecord.toJson(), '"f1"');
      const second = await SyncEngine.run(transport, context);
      expect(second.downloaded).assertEqual(1);
      tree = await repo.folderTree();
      expect(tree.length).assertEqual(1);
      expect(tree[0].folder.name).assertEqual('迟到文件夹');
      expect(tree[0].totalCount).assertEqual(1);
    });

    it('folderUploadsRunBeforeBookmarkUploads', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const repo = FlowRepository.get();
      const folder = await repo.createFolder('', '顺序');
      expect(folder === undefined).assertFalse();
      if (folder === undefined) {
        return;
      }
      const dao = new BookmarkDao();
      for (let i = 0; i < 2; i++) {
        const bookmark = Bookmark.create(
          `https://example.com/order-${i}`,
          `书签${i}`,
          BookmarkSource.MANUAL
        );
        bookmark.folderId = folder.id;
        await dao.insert(bookmark);
      }

      const transport = new FakeTransport();
      const report = await SyncEngine.run(transport, context);
      expect(report.uploaded).assertEqual(3);
      expect(report.failed).assertEqual(0);
      expect(transport.callLog.length).assertEqual(3);
      expect(transport.callLog[0]).assertEqual(`folder:${folder.id}`);
    });

    it('retriedPutSuccessCountsAsUploaded', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/retry-ok', '重试成功', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const transport = new FakeTransport();
      transport.transientPutFailures = 2;
      const report = await SyncEngine.run(transport, context);
      expect(report.uploaded).assertEqual(1);
      expect(report.failed).assertEqual(0);
      const loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.dirty).assertFalse();
        expect(loaded.remoteEtag.length > 0).assertTrue();
      }
    });

    it('exhaustedRetriesKeepDirtyUntilNextRun', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const bookmark = Bookmark.create('https://example.com/retry-exhausted', '重试耗尽', BookmarkSource.MANUAL);
      await dao.insert(bookmark);
      const transport = new FakeTransport();
      transport.transientPutFailures = 3;
      const first = await SyncEngine.run(transport, context);
      expect(first.uploaded).assertEqual(0);
      expect(first.failed).assertEqual(1);
      expect(first.firstFailure).assertEqual(SyncErrorText.describe('PUT_429'));
      expect(SyncErrorText.describe('PUT_429').indexOf('请求过于频繁（429）') >= 0).assertTrue();
      let loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.dirty).assertTrue();
      }

      transport.transientPutFailures = 0;
      const second = await SyncEngine.run(transport, context);
      expect(second.uploaded).assertEqual(1);
      expect(second.failed).assertEqual(0);
      loaded = await dao.findById(bookmark.id);
      expect(loaded === undefined).assertFalse();
      if (loaded !== undefined) {
        expect(loaded.dirty).assertFalse();
      }
    });

    it('throttleAbortEndsRoundAndResumesNextRun', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const ids: string[] = [];
      for (let i = 0; i < 3; i++) {
        const bookmark = Bookmark.create(
          `https://example.com/abort-${i}`,
          `早停${i}`,
          BookmarkSource.MANUAL
        );
        await dao.insert(bookmark);
        ids.push(bookmark.id);
      }

      const transport = new FakeTransport();
      transport.abortAfterPuts = 1;
      const first = await SyncEngine.run(transport, context);
      expect(first.throttled).assertTrue();
      expect(first.uploaded).assertEqual(1);
      expect(first.failed).assertEqual(0);
      expect(first.message.indexOf('提前结束') >= 0).assertTrue();

      let dirtyCount = 0;
      for (let i = 0; i < ids.length; i++) {
        const loaded = await dao.findById(ids[i]);
        expect(loaded === undefined).assertFalse();
        if (loaded !== undefined && loaded.dirty) {
          dirtyCount = dirtyCount + 1;
        }
      }
      expect(dirtyCount).assertEqual(2);

      // Same transport keeps round 1's remote files; only the throttle
      // circuit resets, exactly like a real server that has recovered.
      transport.abortAfterPuts = -1;
      const second = await SyncEngine.run(transport, context);
      expect(second.throttled).assertFalse();
      expect(second.uploaded).assertEqual(2);
      expect(second.failed).assertEqual(0);
      for (let i = 0; i < ids.length; i++) {
        const loaded = await dao.findById(ids[i]);
        expect(loaded === undefined).assertFalse();
        if (loaded !== undefined) {
          expect(loaded.dirty).assertFalse();
        }
      }
    });
  });
}
