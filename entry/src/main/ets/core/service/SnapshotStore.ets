import { fileIo as fs } from '@kit.CoreFileKit';
import { common } from '@kit.AbilityKit';

export class SnapshotStore {
  private static ensureDir(context: common.Context): string {
    const dir = `${context.filesDir}/snapshots`;
    if (!fs.accessSync(dir)) {
      fs.mkdirSync(dir, true);
    }
    return dir;
  }

  private static dirOf(context: common.Context): string {
    return `${context.filesDir}/snapshots`;
  }

  static pathFor(context: common.Context, id: string): string {
    return `${SnapshotStore.dirOf(context)}/${id}.txt`;
  }

  static save(context: common.Context, id: string, text: string): string {
    const dir = SnapshotStore.ensureDir(context);
    const path = `${dir}/${id}.txt`;
    const file = fs.openSync(path, fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
    fs.writeSync(file.fd, text);
    fs.closeSync(file);
    return path;
  }

  static read(path: string): string {
    if (path.length === 0) {
      return '';
    }
    if (!fs.accessSync(path)) {
      return '';
    }
    try {
      return fs.readTextSync(path);
    } catch (error) {
      return '';
    }
  }

  static remove(path: string): void {
    if (path.length === 0) {
      return;
    }
    try {
      if (fs.accessSync(path)) {
        fs.unlinkSync(path);
      }
    } catch (error) {
      return;
    }
  }

  static removeById(context: common.Context, id: string): void {
    SnapshotStore.remove(SnapshotStore.pathFor(context, id));
  }

  static clearAll(context: common.Context): number {
    const dir = SnapshotStore.dirOf(context);
    let removed = 0;
    try {
      if (!fs.accessSync(dir)) {
        return 0;
      }
      const names = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].endsWith('.txt')) {
          SnapshotStore.remove(`${dir}/${names[i]}`);
          removed = removed + 1;
        }
      }
    } catch (error) {
      return removed;
    }
    return removed;
  }

  static count(context: common.Context): number {
    const dir = SnapshotStore.dirForRead(context);
    if (dir.length === 0) {
      return 0;
    }
    let count = 0;
    try {
      const names = fs.listFileSync(dir);
      for (let i = 0; i < names.length; i++) {
        if (names[i].endsWith('.txt')) {
          count = count + 1;
        }
      }
    } catch (error) {
      return 0;
    }
    return count;
  }

  private static dirForRead(context: common.Context): string {
    const dir = SnapshotStore.dirOf(context);
    if (!fs.accessSync(dir)) {
      return '';
    }
    return dir;
  }
}
