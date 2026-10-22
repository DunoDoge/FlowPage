import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const READER_NAME: string = 'flowpage_reader';
const POSITION_PREFIX: string = 'pos_';

export class ReaderPrefs {
  static readPosition(context: common.Context, id: string): number {
    if (id.length === 0) {
      return 0;
    }
    try {
      const store = preferences.getPreferencesSync(context, { name: READER_NAME });
      const value = store.getSync(`${POSITION_PREFIX}${id}`, 0);
      return typeof value === 'number' && value > 0 ? Math.floor(value) : 0;
    } catch (error) {
      return 0;
    }
  }

  static writePosition(context: common.Context, id: string, index: number): void {
    if (id.length === 0) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(context, { name: READER_NAME });
      store.putSync(`${POSITION_PREFIX}${id}`, index < 0 ? 0 : index);
      store.flush().catch(() => {});
    } catch (error) {
      return;
    }
  }

  static clearPosition(context: common.Context, id: string): void {
    if (id.length === 0) {
      return;
    }
    try {
      const store = preferences.getPreferencesSync(context, { name: READER_NAME });
      store.deleteSync(`${POSITION_PREFIX}${id}`);
      store.flush().catch(() => {});
    } catch (error) {
      return;
    }
  }
}
