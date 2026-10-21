import { describe, beforeAll, beforeEach, it, expect } from '@ohos/hypium';
import { abilityDelegatorRegistry } from '@kit.TestKit';
import { common, UIAbility } from '@kit.AbilityKit';
import { Database } from '../../../main/ets/core/db/Database';
import { BookmarkDao } from '../../../main/ets/core/db/BookmarkDao';
import { Bookmark } from '../../../main/ets/model/Bookmark';
import { SyncRecord } from '../../../main/ets/core/sync/SyncRecord';
import { SyncEngine, SyncReport } from '../../../main/ets/core/sync/SyncEngine';
import { SyncTransport } from '../../../main/ets/core/sync/SyncTransport';
import { RemoteItem, WebDavResponse } from '../../../main/ets/core/sync/WebDavTypes';
import { FlowRepository } from '../../../main/ets/repository/FlowRepository';
import { BookmarkSource } from '../../../main/ets/common/Constants';

class StoredFile {
  json: string = '';
  etag: string = '';
}

class FakeTransport implements SyncTransport {
  files: Map<string, StoredFile> = new Map<string, StoredFile>();
  tombstones: Set<string> = new Set<string>();
  failDelete: boolean = false;
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

  async listItems(): Promise<RemoteItem[]> {
    const items: RemoteItem[] = [];
    this.files.forEach((file: StoredFile, name: string) => {
      const item = new RemoteItem();
      item.name = name;
      item.etag = file.etag;
      items.push(item);
    });
    return items;
  }

  async listTombstones(): Promise<string[]> {
    const ids: string[] = [];
    this.tombstones.forEach((id: string) => {
      ids.push(id);
    });
    return ids;
  }

  async putTombstone(id: string): Promise<void> {
    this.tombstones.add(id);
  }

  async get(name: string): Promise<WebDavResponse> {
    const response = new WebDavResponse();
    const file = this.files.get(name);
    if (file === undefined) {
      response.status = 404;
      return response;
    }
    response.status = 200;
    response.body = file.json;
    response.etag = file.etag;
    return response;
  }

  async put(name: string, json: string, etag: string): Promise<string> {
    const stored = new StoredFile();
    stored.json = json;
    stored.etag = this.nextEtag();
    this.files.set(name, stored);
    return stored.etag;
  }

  async remove(name: string): Promise<void> {
    if (this.failDelete) {
      throw new Error('DELETE_403');
    }
    this.files.delete(name);
  }

  seed(name: string, json: string, etag: string): void {
    const stored = new StoredFile();
    stored.json = json;
    stored.etag = etag;
    this.files.set(name, stored);
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

    it('downloadKeepsLocalFoldersForLegacyRecord', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const local = Bookmark.create('https://example.com/keep-folder', '本地标题', BookmarkSource.IMPORT);
      local.folderPath = '工作/工具';
      local.updatedAt = Date.now() - 10000;
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
      if (after !== undefined) {
        expect(after.title).assertEqual('远端标题');
        expect(after.folderPath).assertEqual('工作/工具');
        expect(after.source).assertEqual(BookmarkSource.IMPORT);
      }
    });

    it('downloadAppliesRemoteFoldersFromSchemaTwo', 0, async () => {
      if (context === undefined) {
        expect(context === undefined).assertFalse();
        return;
      }
      const dao = new BookmarkDao();
      const local = Bookmark.create('https://example.com/schema2-folder', '本地标题', BookmarkSource.IMPORT);
      local.folderPath = '本地/旧';
      local.updatedAt = Date.now() - 10000;
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
      remote.folderPath = '远端/新';
      remote.source = BookmarkSource.SHARE;
      transport.seed(local.id, remote.toJson(), '"r2"');

      const report = await SyncEngine.run(transport, context);
      expect(report.downloaded).assertEqual(1);
      const after = await dao.findById(local.id);
      expect(after === undefined).assertFalse();
      if (after !== undefined) {
        expect(after.folderPath).assertEqual('远端/新');
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
  });
}
