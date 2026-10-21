import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LibrarySummary, FlowRepository, ImportOptions } from '../repository/FlowRepository';
import { ImportPreview } from '../model/ImportPreview';
import { ImportResult } from '../model/ImportResult';
import { AppState } from '../common/AppState';
import { KeyCode } from '@kit.InputKit';

const SETTINGS_NAME: string = 'flowpage_settings';
const AUTO_SNAPSHOT_KEY: string = 'auto_snapshot';
const READ_CHUNK: number = 262144;

@ComponentV2
export struct SettingsPage {
  @Param showBack: boolean = false;
  @Event onBack: () => void = () => {};
  @Local appState: AppState = AppState.shared;
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local themeMode: string = 'system';
  @Local autoSnapshot: boolean = true;
  @Local importing: boolean = false;
  @Local progressText: string = '';
  @Local importResult: ImportResult | undefined = undefined;
  @Local preview: ImportPreview | undefined = undefined;
  private pendingHtml: string = '';
  private cancelRequested: boolean = false;

  aboutToAppear(): void {
    this.readSettings();
    this.loadSummary();
  }

  @Monitor('appState.refreshTick')
  onChanged(): void {
    this.loadSummary();
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
      const context = getContext(this) as common.UIAbilityContext;
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

  private async readFileChunked(uri: string): Promise<string> {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    try {
      const stat = fs.statSync(file.fd);
      const total = stat.size;
      const buffer = new ArrayBuffer(READ_CHUNK);
      const bytes = new Uint8Array(total);
      let offset = 0;
      while (offset < total) {
        const remaining = total - offset;
        const toRead = remaining < READ_CHUNK ? remaining : READ_CHUNK;
        const read = await fs.read(file.fd, buffer, { offset: offset, length: toRead });
        if (read <= 0) {
          break;
        }
        bytes.set(new Uint8Array(buffer.slice(0, read)), offset);
        offset = offset + read;
        this.progressText = `正在读取 ${Math.floor(offset * 100 / total)}%`;
      }
      return new util.TextDecoder('utf-8').decodeToString(bytes.subarray(0, offset));
    } finally {
      fs.closeSync(file);
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
      const html = await this.readFileChunked(uris[0]);
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
      options.keepFolders = true;
      options.onProgress = (done: number, total: number) => {
        this.progressText = `${done} / ${total}`;
      };
      options.shouldCancel = () => this.cancelRequested;
      const result = await FlowRepository.get().importHtml(this.pendingHtml, options);
      this.importResult = result;
      this.preview = undefined;
      this.pendingHtml = '';
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
    }
  }

  private requestCancelImport(): void {
    this.cancelRequested = true;
    this.progressText = '正在取消…';
  }

  private async saveText(fileName: string, content: string): Promise<void> {
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
      AppState.shared.toast('已导出');
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
    await this.saveText('flowpage-bookmarks.html', content);
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

  build() {
    Column() {
      Row() {
        if (this.showBack) {
          Text('返回')
            .fontSize(13)
            .fontColor($r('app.color.ink_secondary'))
            .height(44)
            .padding({ right: 12 })
            .accessibilityText('返回')
            .focusable(true)
            .onClick(() => this.onBack())
            .onKeyEvent((event: KeyEvent) => {
              if (event.type === KeyType.Down &&
                (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
                this.onBack();
              }
            })
        }
        Blank()
        Text('v1.0.0')
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12 })

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
                Text(`跳过重复 ${this.importResult.skipped} · 失败 ${this.importResult.failed} · 文件夹 ${this.importResult.folderCount}`)
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
            Text('本地优先的链接收笺工具。没有账号、没有推荐、没有埋点。')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .lineHeight(20)
            Text('流笺不读取其他浏览器的书签数据库；书签迁移通过 HTML 导入与分享收笺完成。')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .lineHeight(20)
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 20, right: 20, top: 18, bottom: 40 })
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
