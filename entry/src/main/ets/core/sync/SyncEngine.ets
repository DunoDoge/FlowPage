import { common } from '@kit.AbilityKit';
import { Bookmark } from '../../model/Bookmark';
import { Tombstone } from '../../model/Tombstone';
import { FlowRepository } from '../../repository/FlowRepository';
import { SyncConfigStore } from './SyncConfigStore';
import { SyncAction, SyncPlanner } from './SyncPlanner';
import { SyncRecord } from './SyncRecord';
import { RemoteItem, WebDavTransport } from './WebDavTransport';

export class SyncReport {
  uploaded: number = 0;
  downloaded: number = 0;
  skipped: number = 0;
  deleted: number = 0;
  failed: number = 0;
  firstFailure: string = '';
  message: string = '';
}

export class SyncEngine {
  private static running: boolean = false;

  private static async upload(
    transport: WebDavTransport,
    repo: FlowRepository,
    bookmark: Bookmark,
    remoteEtag: string,
    report: SyncReport
  ): Promise<void> {
    const expectedRev = bookmark.rev;
    const expectedUpdatedAt = bookmark.updatedAt;
    try {
      const json = SyncRecord.fromBookmark(bookmark).toJson();
      const etag = await transport.put(bookmark.id, json, remoteEtag);
      await repo.setRemoteEtagIfUnchanged(bookmark.id, etag, expectedRev, expectedUpdatedAt);
      report.uploaded = report.uploaded + 1;
    } catch (error) {
      report.failed = report.failed + 1;
      if (report.firstFailure.length === 0) {
        report.firstFailure = error instanceof Error ? error.message : 'UNKNOWN';
      }
    }
  }

  private static async deleteRemote(
    transport: WebDavTransport,
    repo: FlowRepository,
    tombstone: Tombstone,
    report: SyncReport
  ): Promise<void> {
    try {
      await transport.remove(tombstone.remoteName());
      await repo.removeTombstone(tombstone.id);
      report.deleted = report.deleted + 1;
    } catch (error) {
      report.failed = report.failed + 1;
      const message = error instanceof Error ? error.message : 'UNKNOWN';
      await repo.markTombstoneFailed(tombstone.id, message);
      if (report.firstFailure.length === 0) {
        report.firstFailure = message;
      }
    }
  }

  static async sync(context: common.Context): Promise<SyncReport> {
    if (SyncEngine.running) {
      throw new Error('BUSY');
    }
    const config = await SyncConfigStore.load(context);
    if (config === undefined) {
      throw new Error('NO_CONFIG');
    }
    if (config.credentialInvalid || config.password.length === 0) {
      throw new Error('NO_CREDENTIAL');
    }
    SyncEngine.running = true;
    const report = new SyncReport();
    try {
      const transport = new WebDavTransport(config);
      await transport.test();
      await transport.ensureBase();
      const remoteItems = await transport.listItems();
      const remoteMap = new Map<string, RemoteItem>();
      for (let i = 0; i < remoteItems.length; i++) {
        remoteMap.set(remoteItems[i].name, remoteItems[i]);
      }

      const repo = FlowRepository.get();
      const localAll = await repo.listAll(true);
      const localMap = new Map<string, Bookmark>();
      for (let i = 0; i < localAll.length; i++) {
        localMap.set(localAll[i].id, localAll[i]);
      }
      const tombstones = await repo.listTombstones();
      const tombstoneMap = new Map<string, Tombstone>();
      for (let i = 0; i < tombstones.length; i++) {
        tombstoneMap.set(tombstones[i].remoteName(), tombstones[i]);
        tombstoneMap.set(tombstones[i].id, tombstones[i]);
      }
      const handled = new Set<string>();

      for (let i = 0; i < remoteItems.length; i++) {
        const remote = remoteItems[i];
        if (remote.name.length === 0) {
          continue;
        }
        handled.add(remote.name);
        const tombstone = tombstoneMap.get(remote.name);
        if (tombstone !== undefined) {
          await SyncEngine.deleteRemote(transport, repo, tombstone, report);
          continue;
        }
        const local = localMap.get(remote.name);

        if (local === undefined) {
          try {
            const response = await transport.get(remote.name);
            if (response.status === 200) {
              const record = SyncRecord.parse(response.body);
              const applied = await repo.upsertFromRemote(record, remote.etag);
              if (applied) {
                report.downloaded = report.downloaded + 1;
              } else {
                report.skipped = report.skipped + 1;
              }
            } else {
              report.failed = report.failed + 1;
            }
          } catch (error) {
            report.failed = report.failed + 1;
          }
          continue;
        }

        const action = SyncPlanner.planForExisting(local.dirty, local.remoteEtag, remote.etag);
        if (action === SyncAction.UPLOAD) {
          await SyncEngine.upload(transport, repo, local, remote.etag, report);
          continue;
        }
        if (action === SyncAction.SKIP) {
          report.skipped = report.skipped + 1;
          continue;
        }

        try {
          const response = await transport.get(remote.name);
          if (response.status !== 200) {
            report.failed = report.failed + 1;
            continue;
          }
          const record = SyncRecord.parse(response.body);
          const next = SyncPlanner.planAfterFetch(
            local.dirty,
            local.remoteEtag,
            local.updatedAt,
            record.updatedAt
          );
          if (next === SyncAction.DOWNLOAD) {
            const applied = await repo.upsertFromRemote(record, remote.etag);
            if (applied) {
              report.downloaded = report.downloaded + 1;
            } else {
              report.skipped = report.skipped + 1;
            }
          } else if (next === SyncAction.ADOPT_ETAG) {
            const applied = await repo.setRemoteEtagIfUnchanged(
              local.id,
              remote.etag,
              local.rev,
              local.updatedAt
            );
            if (applied) {
              report.skipped = report.skipped + 1;
            } else {
              await SyncEngine.upload(transport, repo, local, remote.etag, report);
            }
          } else {
            await SyncEngine.upload(transport, repo, local, remote.etag, report);
          }
        } catch (error) {
          report.failed = report.failed + 1;
        }
      }

      for (let i = 0; i < localAll.length; i++) {
        const local = localAll[i];
        if (handled.has(local.id) || tombstoneMap.get(local.id) !== undefined) {
          continue;
        }
        const known = remoteMap.get(local.id);
        if (SyncPlanner.planForLocalOnly(local.dirty, known !== undefined) === SyncAction.SKIP) {
          continue;
        }
        await SyncEngine.upload(transport, repo, local, known === undefined ? '' : known.etag, report);
      }

      for (let i = 0; i < tombstones.length; i++) {
        const tombstone = tombstones[i];
        if (handled.has(tombstone.remoteName())) {
          continue;
        }
        await repo.removeTombstone(tombstone.id);
      }

      SyncConfigStore.setLastSync(context, Date.now());
      repo.afterSync();
      report.message = `上传 ${report.uploaded} · 下载 ${report.downloaded} · 跳过 ${report.skipped}`;
      if (report.deleted > 0) {
        report.message += ` · 删除 ${report.deleted}`;
      }
      if (report.failed > 0) {
        report.message += ` · 失败 ${report.failed}`;
        if (report.firstFailure.length > 0) {
          report.message += `（${report.firstFailure}）`;
        }
      }
      return report;
    } finally {
      SyncEngine.running = false;
    }
  }
}
