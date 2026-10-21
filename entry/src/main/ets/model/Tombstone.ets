export class Tombstone {
  id: string = '';
  remoteId: string = '';
  deletedAt: number = 0;
  attempts: number = 0;
  lastError: string = '';

  remoteName(): string {
    return this.remoteId.length > 0 ? this.remoteId : this.id;
  }
}
