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
  });
}
