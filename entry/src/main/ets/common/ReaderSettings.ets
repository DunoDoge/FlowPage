import { preferences } from '@kit.ArkData';
import { common } from '@kit.AbilityKit';

const SETTINGS_NAME: string = 'flowpage_settings';

@ObservedV2
export class ReaderSettings {
  private static instance: ReaderSettings | undefined = undefined;

  static get shared(): ReaderSettings {
    if (ReaderSettings.instance === undefined) {
      ReaderSettings.instance = new ReaderSettings();
    }
    return ReaderSettings.instance;
  }

  @Trace size: number = 17;
  @Trace lineIndex: number = 1;
  @Trace paraIndex: number = 1;
  private loaded: boolean = false;

  load(context: common.Context): void {
    if (this.loaded) {
      return;
    }
    this.loaded = true;
    try {
      const store = preferences.getPreferencesSync(context, { name: SETTINGS_NAME });
      const size = store.getSync('reading_size', 17);
      const line = store.getSync('reading_line', 1);
      const para = store.getSync('reading_para', 1);
      this.size = ReaderSettings.clampSize(typeof size === 'number' ? size : 17);
      this.lineIndex = ReaderSettings.clampIndex(typeof line === 'number' ? line : 1);
      this.paraIndex = ReaderSettings.clampIndex(typeof para === 'number' ? para : 1);
    } catch (error) {
      this.size = 17;
      this.lineIndex = 1;
      this.paraIndex = 1;
    }
  }

  setSize(context: common.Context, size: number): void {
    this.size = ReaderSettings.clampSize(size);
    this.persist(context);
  }

  setLine(context: common.Context, index: number): void {
    this.lineIndex = ReaderSettings.clampIndex(index);
    this.persist(context);
  }

  setPara(context: common.Context, index: number): void {
    this.paraIndex = ReaderSettings.clampIndex(index);
    this.persist(context);
  }

  lineHeight(): number {
    const factor = this.lineIndex === 0 ? 1.45 : (this.lineIndex === 2 ? 1.95 : 1.7);
    return Math.round(this.size * factor);
  }

  paragraphSpacing(): number {
    if (this.paraIndex === 0) {
      return 10;
    }
    if (this.paraIndex === 2) {
      return 24;
    }
    return 16;
  }

  private persist(context: common.Context): void {
    try {
      const store = preferences.getPreferencesSync(context, { name: SETTINGS_NAME });
      store.putSync('reading_size', this.size);
      store.putSync('reading_line', this.lineIndex);
      store.putSync('reading_para', this.paraIndex);
      store.flush().catch(() => {});
    } catch (error) {
      return;
    }
  }

  private static clampSize(size: number): number {
    if (size < 15) {
      return 15;
    }
    if (size > 23) {
      return 23;
    }
    return Math.round(size);
  }

  private static clampIndex(index: number): number {
    if (index < 0) {
      return 0;
    }
    if (index > 2) {
      return 2;
    }
    return Math.round(index);
  }
}
