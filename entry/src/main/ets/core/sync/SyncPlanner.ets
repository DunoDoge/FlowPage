export enum SyncAction {
  SKIP = 0,
  UPLOAD = 1,
  FETCH = 2,
  DOWNLOAD = 3,
  ADOPT_ETAG = 4
}

export class SyncPlanner {
  static planForExisting(localDirty: boolean, localEtag: string, remoteEtag: string): SyncAction {
    if (remoteEtag.length === 0 || localEtag === remoteEtag) {
      return localDirty ? SyncAction.UPLOAD : SyncAction.SKIP;
    }
    return SyncAction.FETCH;
  }

  static planAfterFetch(
    localDirty: boolean,
    localEtag: string,
    localUpdatedAt: number,
    remoteUpdatedAt: number
  ): SyncAction {
    if (remoteUpdatedAt > localUpdatedAt) {
      return SyncAction.DOWNLOAD;
    }
    if (localDirty) {
      return SyncAction.UPLOAD;
    }
    if (localEtag.length === 0) {
      return SyncAction.ADOPT_ETAG;
    }
    return SyncAction.UPLOAD;
  }

  static planForLocalOnly(localDirty: boolean, remoteKnown: boolean): SyncAction {
    if (!localDirty && remoteKnown) {
      return SyncAction.SKIP;
    }
    return SyncAction.UPLOAD;
  }
}
