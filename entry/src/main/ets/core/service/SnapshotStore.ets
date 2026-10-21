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
}
