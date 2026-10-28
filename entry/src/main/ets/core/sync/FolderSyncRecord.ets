import { Folder } from '../../model/Folder';

// JSON.parse boundary: raw stays a platform-typed record, same exemption as SyncRecord.parse.
// schema 2 adds kind (browser semantic marker); schema-1 records parse as kind ''.
export class FolderSyncRecord {
  schema: number = 2;
  id: string = '';
  parentId: string = '';
  name: string = '';
  position: number = 0;
  kind: string = '';
  createdAt: number = 0;
  updatedAt: number = 0;
  rev: number = 1;
  deviceId: string = '';

  static fromFolder(folder: Folder): FolderSyncRecord {
    const record = new FolderSyncRecord();
    record.id = folder.id;
    record.parentId = folder.parentId;
    record.name = folder.name;
    record.position = folder.position;
    record.kind = folder.kind;
    record.createdAt = folder.createdAt;
    record.updatedAt = folder.updatedAt;
    record.rev = folder.rev;
    return record;
  }

  static parse(text: string): FolderSyncRecord {
    const raw = JSON.parse(text) as FolderSyncRecord;
    const record = new FolderSyncRecord();
    record.schema = typeof raw.schema === 'number' ? raw.schema : 1;
    record.id = typeof raw.id === 'string' ? raw.id : '';
    record.parentId = typeof raw.parentId === 'string' ? raw.parentId : '';
    record.name = typeof raw.name === 'string' ? raw.name : '';
    record.position = typeof raw.position === 'number' ? raw.position : 0;
    record.kind = typeof raw.kind === 'string' ? raw.kind : '';
    record.createdAt = typeof raw.createdAt === 'number' ? raw.createdAt : 0;
    record.updatedAt = typeof raw.updatedAt === 'number' ? raw.updatedAt : 0;
    record.rev = typeof raw.rev === 'number' ? raw.rev : 1;
    record.deviceId = typeof raw.deviceId === 'string' ? raw.deviceId : '';
    return record;
  }

  toFolder(): Folder {
    const folder = new Folder();
    folder.id = this.id;
    folder.parentId = this.parentId;
    folder.name = this.name;
    folder.position = this.position;
    folder.kind = this.kind;
    folder.createdAt = this.createdAt;
    folder.updatedAt = this.updatedAt;
    folder.rev = this.rev;
    return folder;
  }

  toJson(): string {
    return JSON.stringify(this);
  }
}
