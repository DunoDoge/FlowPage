import { common } from '@kit.AbilityKit';
import { Bookmark } from '../../model/Bookmark';
import { Folder } from '../../model/Folder';
import { Tombstone } from '../../model/Tombstone';
import { FlowRepository } from '../../repository/FlowRepository';
import { SyncConfigStore } from './SyncConfigStore';
import { SyncErrorText } from './SyncErrorText';
import { SyncAction, SyncPlanner } from './SyncPlanner';
import { SyncRecord } from './SyncRecord';
import { FolderSyncRecord } from './FolderSyncRecord';
import { SyncTransport } from './SyncTransport';
import { RemoteItem } from './WebDavTypes';
import { WebDavTransport } from './WebDavTransport';

export class SyncReport {
  uploaded: number = 0;
  downloaded: number = 0;
  skipped: number = 0;
  deleted: number = 0;
  failed: number = 0;
  firstFailure: string = '';
  message: string = '';
  // True when sustained throttling ended the round early; unprocessed items
  // keep their pending state and resume on the next sync.
  throttled: boolean = false;
}

// Minimal per-entity view the generic loop needs; both Bookmark and Folder map onto it.
class SyncEntityRow {
  id: string = '';
  rev: number = 1;
  updatedAt: number = 0;
  dirty: boolean = true;
  remoteEtag: string = '';
}

// One entity type (bookmarks or folders) injected as closures over transport + repository.
class EntityHooks {
  fetchRemote: () => Promise<RemoteItem[]> = (): Promise<RemoteItem[]> => {
    return Promise.resolve([]);
  };
  fetchLocal: () => Promise<SyncEntityRow[]> = (): Promise<SyncEntityRow[]> => {
    return Promise.resolve([]);
  };
  fetchBody: (name: string) => Promise<string> = (name: string): Promise<string> => {
    throw new Error('NOT WIRED');
  };
  updatedAtOf: (body: string) => number = (body: string): number => {
    return 0;
  };
  applyRemote: (body: string, etag: string) => Promise<boolean> = (body: string, etag: string): Promise<boolean> => {
    return Promise.resolve(false);
  };
  serialize: (id: string) => Promise<string | undefined> = (id: string): Promise<string | undefined> => {
    return Promise.resolve(undefined);
  };
  put: (name: string, json: string, etag: string) => Promise<string> =
    (name: string, json: string, etag: string): Promise<string> => {
      return Promise.resolve('');
    };
  adoptEtag: (row: SyncEntityRow, etag: string) => Promise<boolean> =
    (row: SyncEntityRow, etag: string): Promise<boolean> => {
      return Promise.resolve(false);
    };
}

function bookmarkRow(bookmark: Bookmark): SyncEntityRow {
  const row = new SyncEntityRow();
  row.id = bookmark.id;
  row.rev = bookmark.rev;
  row.updatedAt = bookmark.updatedAt;
  row.dirty = bookmark.dirty;
  row.remoteEtag = bookmark.remoteEtag;
  return row;
}

function folderRow(folder: Folder): SyncEntityRow {
  const row = new SyncEntityRow();
  row.id = folder.id;
  row.rev = folder.rev;
  row.updatedAt = folder.updatedAt;
  row.dirty = folder.dirty;
  row.remoteEtag = folder.remoteEtag;
  return row;
}

export class SyncEngine {
  private static running: boolean = false;

  private static fail(report: SyncReport, error: Object): void {
    report.failed = report.failed + 1;
    if (report.firstFailure.length === 0) {
      report.firstFailure = SyncErrorText.describeError(error);
    }
  }

  // Transport-level throttle circuit verdict; unwinds loops without counting
  // the unprocessed remainder as failures.
  private static isThrottleAbort(error: Object): boolean {
    return error instanceof Error && error.message === 'THROTTLED_ABORT';
  }

  private static rethrowThrottleAbort(error: Object): void {
    if (error instanceof Error && error.message === 'THROTTLED_ABORT') {
      throw error;
    }
  }

  private static rethrowAsError(error: Object): void {
    if (error instanceof Error) {
      throw error;
    }
    throw new Error('SYNC_PHASE_FAILED');
  }

  private static async uploadOne(
    hooks: EntityHooks,
    row: SyncEntityRow,
    remoteEtag: string,
    report: SyncReport
  ): Promise<void> {
    try {
      const json = await hooks.serialize(row.id);
      if (json === undefined) {
        return;
      }
      const etag = await hooks.put(row.id, json, remoteEtag);
      const applied = await hooks.adoptEtag(row, etag);
      if (applied) {
        report.uploaded = report.uploaded + 1;
      } else {
        report.skipped = report.skipped + 1;
      }
    } catch (error) {
      SyncEngine.rethrowThrottleAbort(error);
      SyncEngine.fail(report, error);
    }
  }

  // The same three-phase per-entity loop bookmarks always ran, now shared with folders:
  // remote items plan -> upload/download -> local-only upload. Tombstone sets gate revives.
  private static async syncCollection(
    hooks: EntityHooks,
    remoteTombstoneSet: Set<string>,
    localTombstoneSet: Set<string>,
    report: SyncReport
  ): Promise<void> {
    const remoteItems = await hooks.fetchRemote();
    const remoteMap = new Map<string, RemoteItem>();
    for (let i = 0; i < remoteItems.length; i++) {
      remoteMap.set(remoteItems[i].name, remoteItems[i]);
    }
    const localRows = await hooks.fetchLocal();
    const localMap = new Map<string, SyncEntityRow>();
    for (let i = 0; i < localRows.length; i++) {
      localMap.set(localRows[i].id, localRows[i]);
    }

    for (let i = 0; i < remoteItems.length; i++) {
      const remote = remoteItems[i];
      if (remote.name.length === 0) {
        continue;
      }
      if (remoteTombstoneSet.has(remote.name) || localTombstoneSet.has(remote.name)) {
        continue;
      }
      const local = localMap.get(remote.name);

      if (local === undefined) {
        try {
          const body = await hooks.fetchBody(remote.name);
          const applied = await hooks.applyRemote(body, remote.etag);
          if (applied) {
            report.downloaded = report.downloaded + 1;
          } else {
            report.skipped = report.skipped + 1;
          }
        } catch (error) {
          SyncEngine.rethrowThrottleAbort(error);
          SyncEngine.fail(report, error);
        }
        continue;
      }

      const action = SyncPlanner.planForExisting(local.dirty, local.remoteEtag, remote.etag);
      if (action === SyncAction.UPLOAD) {
        await SyncEngine.uploadOne(hooks, local, remote.etag, report);
        continue;
      }
      if (action === SyncAction.SKIP) {
        report.skipped = report.skipped + 1;
        continue;
      }

      try {
        const body = await hooks.fetchBody(remote.name);
        const next = SyncPlanner.planAfterFetch(
          local.dirty,
          local.remoteEtag,
          local.updatedAt,
          hooks.updatedAtOf(body)
        );
        if (next === SyncAction.DOWNLOAD) {
          const applied = await hooks.applyRemote(body, remote.etag);
          if (applied) {
            report.downloaded = report.downloaded + 1;
          } else {
            report.skipped = report.skipped + 1;
          }
        } else if (next === SyncAction.ADOPT_ETAG) {
          const applied = await hooks.adoptEtag(local, remote.etag);
          if (applied) {
            report.skipped = report.skipped + 1;
          } else {
            await SyncEngine.uploadOne(hooks, local, remote.etag, report);
          }
        } else {
          await SyncEngine.uploadOne(hooks, local, remote.etag, report);
        }
      } catch (error) {
        SyncEngine.rethrowThrottleAbort(error);
        SyncEngine.fail(report, error);
      }
    }

    for (let i = 0; i < localRows.length; i++) {
      const row = localRows[i];
      // remoteTombstoneSet: a remote tombstone outranks any stale local row snapshot.
      if (remoteMap.has(row.id) || localTombstoneSet.has(row.id) || remoteTombstoneSet.has(row.id)) {
        continue;
      }
      if (SyncPlanner.planForLocalOnly(row.dirty, false) === SyncAction.SKIP) {
        continue;
      }
      await SyncEngine.uploadOne(hooks, row, '', report);
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
    try {
      const transport: SyncTransport = new WebDavTransport(config);
      return await SyncEngine.run(transport, context);
    } finally {
      SyncEngine.running = false;
    }
  }

  static async run(transport: SyncTransport, context: common.Context): Promise<SyncReport> {
    const report = new SyncReport();
    await transport.test();
    await transport.ensureBase();
    const remoteItems = await transport.listItems();
    const remoteFolders = await transport.listFolders();
    const remoteTombstoneIds = await transport.listTombstones();
    const remoteTombstoneSet = new Set<string>();
    for (let i = 0; i < remoteTombstoneIds.length; i++) {
      remoteTombstoneSet.add(remoteTombstoneIds[i]);
    }
    const remoteMap = new Map<string, RemoteItem>();
    for (let i = 0; i < remoteItems.length; i++) {
      remoteMap.set(remoteItems[i].name, remoteItems[i]);
    }
    const remoteFolderMap = new Map<string, RemoteItem>();
    for (let i = 0; i < remoteFolders.length; i++) {
      remoteFolderMap.set(remoteFolders[i].name, remoteFolders[i]);
    }

    const repo = FlowRepository.get();
    const localAll = await repo.listAll(true);
    const localMap = new Map<string, Bookmark>();
    for (let i = 0; i < localAll.length; i++) {
      localMap.set(localAll[i].id, localAll[i]);
    }
    const localFolders = await repo.listAllFolders();
    const localFolderMap = new Map<string, Folder>();
    for (let i = 0; i < localFolders.length; i++) {
      localFolderMap.set(localFolders[i].id, localFolders[i]);
    }
    const tombstones = await repo.listTombstones();
    const tombstoneMap = new Map<string, Tombstone>();
    const localTombstoneSet = new Set<string>();
    for (let i = 0; i < tombstones.length; i++) {
      tombstoneMap.set(tombstones[i].remoteName(), tombstones[i]);
      tombstoneMap.set(tombstones[i].id, tombstones[i]);
      localTombstoneSet.add(tombstones[i].remoteName());
      localTombstoneSet.add(tombstones[i].id);
    }

    // Tombstone reconciliation covers both entity types; uuids cannot collide.
    let throttled = false;
    try {
      for (let i = 0; i < remoteTombstoneIds.length; i++) {
        const id = remoteTombstoneIds[i];
        if (id.length === 0) {
          continue;
        }
        if (localMap.get(id) !== undefined) {
          await repo.purgeFromRemote(id);
        } else if (localFolderMap.get(id) !== undefined) {
          await repo.purgeFolderFromRemote(id);
        } else if (tombstoneMap.get(id) !== undefined) {
          await repo.removeTombstone(id);
        }
        if (remoteMap.get(id) !== undefined) {
          try {
            await transport.remove(id);
            report.deleted = report.deleted + 1;
          } catch (error) {
            SyncEngine.rethrowThrottleAbort(error);
            SyncEngine.fail(report, error);
          }
        }
        if (remoteFolderMap.get(id) !== undefined) {
          try {
            await transport.removeFolder(id);
            report.deleted = report.deleted + 1;
          } catch (error) {
            SyncEngine.rethrowThrottleAbort(error);
            SyncEngine.fail(report, error);
          }
        }
      }
    } catch (error) {
      if (!SyncEngine.isThrottleAbort(error)) {
        SyncEngine.rethrowAsError(error);
      }
      throttled = true;
    }

    // Folders upload before bookmarks: under provider rate limiting a large
    // bookmark backlog would otherwise starve the (much smaller) folder phase
    // every round, keeping the remote folders directory empty.
    const folderHooks = new EntityHooks();
    folderHooks.fetchRemote = (): Promise<RemoteItem[]> => {
      return Promise.resolve(remoteFolders);
    };
    folderHooks.fetchLocal = (): Promise<SyncEntityRow[]> => {
      const rows: SyncEntityRow[] = [];
      for (let i = 0; i < localFolders.length; i++) {
        rows.push(folderRow(localFolders[i]));
      }
      return Promise.resolve(rows);
    };
    folderHooks.fetchBody = async (name: string): Promise<string> => {
      const response = await transport.getFolder(name);
      if (response.status !== 200) {
        throw new Error(`GET_${response.status}`);
      }
      return response.body;
    };
    folderHooks.updatedAtOf = (body: string): number => {
      return FolderSyncRecord.parse(body).updatedAt;
    };
    folderHooks.applyRemote = async (body: string, etag: string): Promise<boolean> => {
      return repo.upsertFolderFromRemote(FolderSyncRecord.parse(body), etag);
    };
    folderHooks.serialize = async (id: string): Promise<string | undefined> => {
      const folder = await repo.getFolder(id);
      if (folder === undefined) {
        return undefined;
      }
      return FolderSyncRecord.fromFolder(folder).toJson();
    };
    folderHooks.put = (name: string, json: string, etag: string): Promise<string> => {
      return transport.putFolder(name, json, etag);
    };
    folderHooks.adoptEtag = (row: SyncEntityRow, etag: string): Promise<boolean> => {
      return repo.setFolderEtagIfUnchanged(row.id, etag, row.rev, row.updatedAt);
    };
    try {
      await SyncEngine.syncCollection(folderHooks, remoteTombstoneSet, localTombstoneSet, report);
    } catch (error) {
      if (!SyncEngine.isThrottleAbort(error)) {
        SyncEngine.rethrowAsError(error);
      }
      throttled = true;
    }

    if (!throttled) {
      const bookmarkHooks = new EntityHooks();
      bookmarkHooks.fetchRemote = (): Promise<RemoteItem[]> => {
        return Promise.resolve(remoteItems);
      };
      bookmarkHooks.fetchLocal = (): Promise<SyncEntityRow[]> => {
        const rows: SyncEntityRow[] = [];
        for (let i = 0; i < localAll.length; i++) {
          rows.push(bookmarkRow(localAll[i]));
        }
        return Promise.resolve(rows);
      };
      bookmarkHooks.fetchBody = async (name: string): Promise<string> => {
        const response = await transport.get(name);
        if (response.status !== 200) {
          throw new Error(`GET_${response.status}`);
        }
        return response.body;
      };
      bookmarkHooks.updatedAtOf = (body: string): number => {
        return SyncRecord.parse(body).updatedAt;
      };
      bookmarkHooks.applyRemote = async (body: string, etag: string): Promise<boolean> => {
        return repo.upsertFromRemote(SyncRecord.parse(body), etag);
      };
      bookmarkHooks.serialize = async (id: string): Promise<string | undefined> => {
        const bookmark = await repo.get(id);
        if (bookmark === undefined) {
          return undefined;
        }
        return SyncRecord.fromBookmark(bookmark).toJson();
      };
      bookmarkHooks.put = (name: string, json: string, etag: string): Promise<string> => {
        return transport.put(name, json, etag);
      };
      bookmarkHooks.adoptEtag = (row: SyncEntityRow, etag: string): Promise<boolean> => {
        return repo.setRemoteEtagIfUnchanged(row.id, etag, row.rev, row.updatedAt);
      };
      try {
        await SyncEngine.syncCollection(bookmarkHooks, remoteTombstoneSet, localTombstoneSet, report);
      } catch (error) {
        if (!SyncEngine.isThrottleAbort(error)) {
          SyncEngine.rethrowAsError(error);
        }
        throttled = true;
      }
    }

    if (!throttled) {
      try {
        for (let i = 0; i < tombstones.length; i++) {
          const tombstone = tombstones[i];
          const id = tombstone.remoteName();
          if (remoteTombstoneSet.has(id)) {
            continue;
          }
          try {
            await transport.putTombstone(id);
          } catch (error) {
            SyncEngine.rethrowThrottleAbort(error);
            await repo.markTombstoneFailed(tombstone.id, SyncErrorText.describeError(error));
            SyncEngine.fail(report, error);
            continue;
          }
          if (remoteMap.get(id) !== undefined) {
            try {
              await transport.remove(id);
              report.deleted = report.deleted + 1;
            } catch (error) {
              SyncEngine.rethrowThrottleAbort(error);
              await repo.markTombstoneFailed(tombstone.id, SyncErrorText.describeError(error));
              SyncEngine.fail(report, error);
              continue;
            }
          }
          if (remoteFolderMap.get(id) !== undefined) {
            try {
              await transport.removeFolder(id);
              report.deleted = report.deleted + 1;
            } catch (error) {
              SyncEngine.rethrowThrottleAbort(error);
              await repo.markTombstoneFailed(tombstone.id, SyncErrorText.describeError(error));
              SyncEngine.fail(report, error);
              continue;
            }
          }
          await repo.removeTombstone(tombstone.id);
        }
      } catch (error) {
        if (!SyncEngine.isThrottleAbort(error)) {
          SyncEngine.rethrowAsError(error);
        }
        throttled = true;
      }
    }

    SyncConfigStore.setLastSync(context, Date.now());
    repo.afterSync();
    report.throttled = throttled;
    report.message = throttled ? '服务器限流，本轮提前结束，剩余条目下次同步继续 · ' : '';
    report.message += `上传 ${report.uploaded} · 下载 ${report.downloaded} · 跳过 ${report.skipped}`;
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
  }
}
