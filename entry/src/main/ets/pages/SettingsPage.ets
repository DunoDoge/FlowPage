import { ConfigurationConstant, bundleManager } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { LibrarySummary, FlowRepository, ImportOptions } from '../repository/FlowRepository';
import { ImportPreview } from '../model/ImportPreview';
import { ImportResult } from '../model/ImportResult';
import { AppState } from '../common/AppState';
import { KeyCode } from '@kit.InputKit';
import { PageHeader } from '../components/PageHeader';
import { readTextFileAll } from '../common/FileText';

const SETTINGS_NAME: string = 'flowpage_settings';
const AUTO_SNAPSHOT_KEY: string = 'auto_snapshot';

@ComponentV2
export struct SettingsPage {
  // Extra bottom inset for the floating tab bar; zero when hosted outside
  // the tabs (>=1000vp right pane).
  @Param bottomReserve: number = 0;
  @Local appState: AppState = AppState.shared;
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local themeMode: string = 'system';
  @Local autoSnapshot: boolean = true;
  @Local importing: boolean = false;
  @Local progressText: string = '';
  @Local importResult: ImportResult | undefined = undefined;
  @Local preview: ImportPreview | undefined = undefined;
  @Local mergeFolders: boolean = false;
  @Local versionName: string = '';
  private pendingHtml: string = '';
  private cancelRequested: boolean = false;

  aboutToAppear(): void {
    this.readSettings();
    this.readVersionName();
    this.loadSummary();
    this.consumePendingImport();
  }

  private readVersionName(): void {
    // Empty string hides the label; never fall back to a hardcoded version.
    try {
      this.versionName = bundleManager.getBundleInfoForSelfSync(
        bundleManager.BundleFlag.GET_BUNDLE_INFO_DEFAULT).versionName;
    } catch (error) {
      this.versionName = '';
    }
  }

  @Monitor('appState.refreshTick')
  onChanged(): void {
    this.loadSummary();
  }

  @Monitor('appState.pendingImportHtml')
  onPendingImport(): void {
    this.consumePendingImport();
  }

  @Monitor('appState.libraryReady')
  onLibraryReady(): void {
    // Cold-start handoffs arrive before repository init finished; retry then.
    this.consumePendingImport();
  }

  // Consumes an HTML handoff from the share extension or an open-with want
  // into the regular import preview. Defers (keeping the stash) until the
  // repository is ready and any in-flight import settles.
  private consumePendingImport(): void {
    if (this.importing || this.appState.pendingImportHtml.length === 0) {
      return;
    }
    if (!this.appState.libraryReady) {
      return;
    }
    const html = this.appState.pendingImportHtml;
    this.appState.pendingImportHtml = '';
    this.previewBookmarkHtml(html);
  }

  private async previewBookmarkHtml(html: string): Promise<void> {
    this.importResult = undefined;
    this.preview = undefined;
    this.progressText = '正在解析…';
    try {
      const preview = await FlowRepository.get().previewHtml(html);
      if (preview.total === 0) {
        this.progressText = '';
        AppState.shared.toast('没读到书签，请确认是浏览器导出的 HTML');
        return;
      }
      this.pendingHtml = html;
      this.preview = preview;
      this.progressText = '';
    } catch (error) {
      this.progressText = '';
      AppState.shared.toast('文件没读懂，请确认是浏览器导出的 HTML');
    }
  }

  private async loadSummary(): Promise<void> {
    try {
      this.summary = await FlowRepository.get().summary();
    } catch (error) {
      AppState.shared.toast('没有读到数据统计');
    }
  }

  private readSettings(): void {
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: SETTINGS_NAME });
      const stored = store.getSync('theme_mode', 'system');
      this.themeMode = typeof stored === 'string' ? stored : 'system';
      const snapshot = store.getSync(AUTO_SNAPSHOT_KEY, true);
      this.autoSnapshot = typeof snapshot === 'boolean' ? snapshot : true;
    } catch (error) {
      this.themeMode = 'system';
      this.autoSnapshot = true;
    }
  }

  private applyTheme(mode: string): void {
    this.themeMode = mode;
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: SETTINGS_NAME });
      store.putSync('theme_mode', mode);
      store.flush().catch(() => {});
      const context = getContext(this);
      if (mode === 'light') {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_LIGHT);
      } else if (mode === 'dark') {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_DARK);
      } else {
        context.getApplicationContext().setColorMode(ConfigurationConstant.ColorMode.COLOR_MODE_NOT_SET);
      }
    } catch (error) {
      AppState.shared.toast('没切换成功');
    }
  }

  private toggleAutoSnapshot(enabled: boolean): void {
    this.autoSnapshot = enabled;
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: SETTINGS_NAME });
      store.putSync(AUTO_SNAPSHOT_KEY, enabled);
      store.flush().catch(() => {});
    } catch (error) {
      AppState.shared.toast('没能保存这个开关');
    }
  }

  private async pickImportFile(): Promise<void> {
    if (this.importing) {
      return;
    }
    try {
      const options = new picker.DocumentSelectOptions();
      options.fileSuffixFilters = ['.html', '.htm'];
      const uris = await new picker.DocumentViewPicker().select(options);
      if (uris.length === 0) {
        return;
      }
      this.importResult = undefined;
      this.preview = undefined;
      this.progressText = '正在读取…';
      const html = await readTextFileAll(uris[0], (percent: number) => {
        this.progressText = `正在读取 ${percent}%`;
      });
      this.progressText = '正在解析…';
      const preview = await FlowRepository.get().previewHtml(html);
      this.pendingHtml = html;
      this.preview = preview;
      this.progressText = '';
    } catch (error) {
      this.progressText = '';
      AppState.shared.toast('文件没读懂，请确认是浏览器导出的 HTML');
    }
  }

  private cancelPreview(): void {
    this.preview = undefined;
    this.pendingHtml = '';
    this.mergeFolders = false;
    this.progressText = '';
  }

  private async startImport(): Promise<void> {
    if (this.importing || this.pendingHtml.length === 0) {
      return;
    }
    this.importing = true;
    this.cancelRequested = false;
    this.progressText = '正在写入…';
    this.importResult = undefined;
    try {
      const options = new ImportOptions();
      options.onProgress = (done: number, total: number) => {
        this.progressText = `${done} / ${total}`;
      };
      options.shouldCancel = () => this.cancelRequested;
      options.mergeFolders = this.mergeFolders;
      const result = await FlowRepository.get().importHtml(this.pendingHtml, options);
      this.importResult = result;
      this.preview = undefined;
      this.pendingHtml = '';
      this.mergeFolders = false;
      this.progressText = '';
      if (result.cancelled) {
        AppState.shared.toast(`已取消，导入 ${result.imported} 条`);
      } else {
        AppState.shared.toast(`导入 ${result.imported} 条`);
      }
      this.loadSummary();
    } catch (error) {
      this.progressText = '';
      AppState.shared.toast('导入失败，本地数据没有变化');
    } finally {
      this.importing = false;
      // A handoff that arrived mid-import was deferred; pick it up now.
      this.consumePendingImport();
    }
  }

  private requestCancelImport(): void {
    this.cancelRequested = true;
    this.progressText = '正在取消…';
  }

  private async saveText(fileName: string, content: string, doneToast: string = '已导出'): Promise<void> {
    try {
      const options = new picker.DocumentSaveOptions();
      options.newFileNames = [fileName];
      const uris = await new picker.DocumentViewPicker().save(options);
      if (uris.length === 0) {
        return;
      }
      const file = fs.openSync(uris[0], fs.OpenMode.READ_WRITE | fs.OpenMode.CREATE | fs.OpenMode.TRUNC);
      fs.writeSync(file.fd, content);
      fs.closeSync(file);
      AppState.shared.toast(doneToast);
    } catch (error) {
      AppState.shared.toast('导出失败');
    }
  }

  private async exportJson(): Promise<void> {
    const content = await FlowRepository.get().exportJson();
    await this.saveText('flowpage-bookmarks.json', content);
  }

  private async exportHtml(): Promise<void> {
    const content = await FlowRepository.get().exportHtml();
    await this.saveText(`flowpage-bookmarks-${this.dateStamp()}.html`, content, '已导出，可在浏览器书签导入中使用');
  }

  private dateStamp(): string {
    const now = new Date();
    const month = now.getMonth() + 1;
    const day = now.getDate();
    const pad = (value: number): string => value < 10 ? `0${value}` : `${value}`;
    return `${now.getFullYear()}${pad(month)}${pad(day)}`;
  }

  private async exportFailures(): Promise<void> {
    if (this.importResult === undefined || this.importResult.failedUrls.length === 0) {
      return;
    }
    await this.saveText('flowpage-import-failures.txt', this.importResult.failedUrls.join('\n'));
  }

  private confirmClear(): void {
    AlertDialog.show({
      title: '清空本机数据？',
      message: '所有笺、标签、冲突记录与正文快照都会从这台设备删除，无法撤销。云端数据会保留，下次同步时会重新下载回来。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空本机',
        fontColor: $r('app.color.danger'),
        action: () => {
          FlowRepository.get().clearAll().then(() => {
            AppState.shared.toast('本机数据已清空，云端保留');
          }).catch(() => {
            AppState.shared.toast('清空失败，请稍后再试');
          });
        }
      }
    });
  }

  @Builder
  HeaderTrailing() {
    if (this.versionName.length > 0) {
      Text(`v${this.versionName}`)
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
    }
  }

  build() {
    Column() {
      PageHeader({
        trailing: () => {
          this.HeaderTrailing()
        }
      })

      Text('设置')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 14 })

      Scroll() {
        Column({ space: 26 }) {
          Column({ space: 10 }) {
            this.SectionTitle('外观')
            Row({ space: 8 }) {
              this.ThemeChip('跟随系统', 'system')
              this.ThemeChip('浅色', 'light')
              this.ThemeChip('深色', 'dark')
            }
            .width('100%')
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            this.SectionTitle('阅读与快照')
            Row() {
              Column({ space: 3 }) {
                Text('自动保存正文快照')
                  .fontSize(15)
                  .fontColor($r('app.color.ink'))
                Text('关闭后，新收的笺只保存链接与元数据。')
                  .fontSize(11)
                  .fontColor($r('app.color.ink_tertiary'))
              }
              .alignItems(HorizontalAlign.Start)
              .layoutWeight(1)
              Toggle({ type: ToggleType.Switch, isOn: this.autoSnapshot })
                .selectedColor($r('app.color.ink'))
                .onChange((isOn: boolean) => {
                  this.toggleAutoSnapshot(isOn);
                })
            }
            .width('100%')
            .constraintSize({ minHeight: 44 })
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            this.SectionTitle('数据')
            Text(`${this.summary.total} 条笺 · ${this.summary.unread} 条未读 · ${this.summary.archived} 条归档 · ${this.summary.trash} 条在回收站`)
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .width('100%')
            this.ActionRow('导入浏览器书签', '先预览，再写入', () => this.pickImportFile(), false)
            this.ActionRow('导出为 JSON', '完整字段，可程序读取', () => this.exportJson(), false)
            this.ActionRow('导出为 HTML', '可导入其他浏览器', () => this.exportHtml(), false)
            this.ActionRow('清空本机数据', '云端保留，下次同步会恢复', () => this.confirmClear(), true)

            if (this.importing) {
              Row({ space: 10 }) {
                Text('导入中')
                  .fontSize(12)
                  .fontColor($r('app.color.ink_secondary'))
                Text(this.progressText)
                  .fontSize(12)
                  .fontColor($r('app.color.ink'))
                  .layoutWeight(1)
                if (!this.cancelRequested) {
                  Text('取消')
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .height(44)
                    .padding({ left: 10, right: 10 })
                    .accessibilityText('取消导入')
                    .onClick(() => this.requestCancelImport())
                }
              }
              .width('100%')
              .padding({ top: 6 })
            }

            if (this.preview !== undefined) {
              Column({ space: 6 }) {
                Text('导入预览')
                  .fontSize(13)
                  .fontColor($r('app.color.ink'))
                Text(`共 ${this.preview.total} 条 · 可导入 ${this.preview.importable} 条`)
                  .fontSize(11)
                  .fontColor($r('app.color.ink_secondary'))
                Text(`重复 ${this.preview.duplicateCount} · 无法识别 ${this.preview.invalidCount} · 文件夹 ${this.preview.folderCount}`)
                  .fontSize(11)
                  .fontColor($r('app.color.ink_secondary'))
                if (this.preview.mergeableCount > 0) {
                  Row() {
                    Column({ space: 3 }) {
                      Text('按文件同步文件夹归属')
                        .fontSize(13)
                        .fontColor($r('app.color.ink'))
                      Text(`浏览器导入的 ${this.preview.mergeableCount} 条会跟随文件中的文件夹；手工收进的不动`)
                        .fontSize(11)
                        .fontColor($r('app.color.ink_tertiary'))
                    }
                    .alignItems(HorizontalAlign.Start)
                    .layoutWeight(1)
                    Toggle({ type: ToggleType.Switch, isOn: this.mergeFolders })
                      .selectedColor($r('app.color.ink'))
                      .onChange((isOn: boolean) => {
                        this.mergeFolders = isOn;
                      })
                  }
                  .width('100%')
                  .constraintSize({ minHeight: 44 })
                }
                Row({ space: 14 }) {
                  Text('开始导入')
                    .fontSize(13)
                    .fontColor($r('app.color.inverse_ink'))
                    .backgroundColor($r('app.color.ink'))
                    .borderRadius(6)
                    .height(44)
                    .padding({ left: 16, right: 16 })
                    .accessibilityText('开始导入')
                    .onClick(() => this.startImport())
                  Text('取消')
                    .fontSize(13)
                    .fontColor($r('app.color.ink_secondary'))
                    .height(44)
                    .padding({ left: 12, right: 12 })
                    .accessibilityText('取消导入')
                    .onClick(() => this.cancelPreview())
                }
                .margin({ top: 4 })
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(8)
              .alignItems(HorizontalAlign.Start)
            }

            if (this.importResult !== undefined) {
              Column({ space: 4 }) {
                Text(`导入完成 · ${this.importResult.imported} 条`)
                  .fontSize(13)
                  .fontColor($r('app.color.ink'))
                Text(`跳过重复 ${this.importResult.skipped} · 失败 ${this.importResult.failed} · 文件夹 ${this.importResult.folderCount}` +
                  (this.importResult.moved > 0 ? ` · 搬迁 ${this.importResult.moved}` : ''))
                  .fontSize(11)
                  .fontColor($r('app.color.ink_secondary'))
                if (this.importResult.failedUrls.length > 0) {
                  Text('导出失败清单')
                    .fontSize(12)
                    .fontColor($r('app.color.danger'))
                    .height(44)
                    .padding({ left: 0, right: 12 })
                    .accessibilityText('导出失败清单')
                    .onClick(() => this.exportFailures())
                }
              }
              .width('100%')
              .padding(12)
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(8)
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            this.SectionTitle('关于')
            Text('流笺 FlowPage')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
            Text('流笺不读取其他浏览器的书签数据库；书签迁移通过 HTML 导入与分享收笺完成。')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .lineHeight(20)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 20, right: 20, top: 18, bottom: 40 + this.bottomReserve })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  @Builder
  SectionTitle(title: string) {
    Text(title)
      .fontSize(11)
      .fontColor($r('app.color.ink_tertiary'))
      .letterSpacing(2)
      .width('100%')
  }

  @Builder
  ThemeChip(label: string, mode: string) {
    Text(label)
      .fontSize(12)
      .fontColor(this.themeMode === mode ? $r('app.color.inverse_ink') : $r('app.color.ink_secondary'))
      .backgroundColor(this.themeMode === mode ? $r('app.color.ink') : Color.Transparent)
      .border({
        width: 1,
        color: this.themeMode === mode ? $r('app.color.ink') : $r('app.color.line_strong')
      })
      .borderRadius(999)
      .height(44)
      .padding({ left: 14, right: 14 })
      .textAlign(TextAlign.Center)
      .accessibilityText(`外观：${label}`)
      .focusable(true)
      .onClick(() => this.applyTheme(mode))
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Down &&
          (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
          this.applyTheme(mode);
        }
      })
  }

  @Builder
  ActionRow(title: string, hint: string, action: () => void, danger: boolean) {
    Row() {
      Column({ space: 3 }) {
        Text(title)
          .fontSize(15)
          .fontColor(danger ? $r('app.color.danger') : $r('app.color.ink'))
        Text(hint)
          .fontSize(11)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .layoutWeight(1)
      Text('›')
        .fontSize(18)
        .fontColor($r('app.color.ink_tertiary'))
    }
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: $r('app.color.line') })
    .accessibilityText(title)
    .focusable(true)
    .onClick(action)
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down &&
        (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
        action();
      }
    })
  }
}
