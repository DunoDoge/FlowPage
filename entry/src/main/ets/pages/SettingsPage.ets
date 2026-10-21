import { common, ConfigurationConstant } from '@kit.AbilityKit';
import { preferences } from '@kit.ArkData';
import { picker, fileIo as fs } from '@kit.CoreFileKit';
import { util } from '@kit.ArkTS';
import { LibrarySummary, FlowRepository } from '../repository/FlowRepository';
import { ImportResult } from '../model/ImportResult';
import { AppState } from '../common/AppState';

const SETTINGS_NAME: string = 'flowpage_settings';

@ComponentV2
export struct SettingsPage {
  @Param showBack: boolean = false;
  @Event onBack: () => void = () => {};
  @Local appState: AppState = AppState.shared;
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local themeMode: string = 'system';
  @Local importing: boolean = false;
  @Local progressText: string = '';
  @Local importResult: ImportResult | undefined = undefined;

  aboutToAppear(): void {
    this.readTheme();
    this.loadSummary();
  }

  @Monitor('appState.refreshTick')
  onChanged(): void {
    this.loadSummary();
  }

  private async loadSummary(): Promise<void> {
    this.summary = await FlowRepository.get().summary();
  }

  private readTheme(): void {
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: SETTINGS_NAME });
      const stored = store.getSync('theme_mode', 'system');
      this.themeMode = typeof stored === 'string' ? stored : 'system';
    } catch (error) {
      this.themeMode = 'system';
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

  private readFile(uri: string): string {
    const file = fs.openSync(uri, fs.OpenMode.READ_ONLY);
    const stat = fs.statSync(file.fd);
    const buffer = new ArrayBuffer(stat.size);
    fs.readSync(file.fd, buffer);
    fs.closeSync(file);
    const bytes = new Uint8Array(buffer);
    return new util.TextDecoder('utf-8').decodeToString(bytes);
  }

  private async importBookmarks(): Promise<void> {
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
      const html = this.readFile(uris[0]);
      this.importing = true;
      this.progressText = '正在读入…';
      this.importResult = undefined;
      const result = await FlowRepository.get().importHtml(html, true, (done: number, total: number) => {
        this.progressText = `${done} / ${total}`;
      });
      this.importResult = result;
      this.importing = false;
      AppState.shared.toast(`导入 ${result.imported} 条`);
      this.loadSummary();
    } catch (error) {
      this.importing = false;
      AppState.shared.toast('文件没读懂，请确认是浏览器导出的 HTML');
    }
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

  private confirmClear(): void {
    AlertDialog.show({
      title: '清空所有数据？',
      message: '所有笺、标签与正文快照都会被删除，无法恢复。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '清空',
        fontColor: $r('app.color.danger'),
        action: () => {
          FlowRepository.get().clearAll();
          AppState.shared.toast('都清空了');
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
            .padding({ right: 12, top: 8, bottom: 8 })
            .onClick(() => this.onBack())
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
            this.SectionTitle('数据')
            Text(`${this.summary.total} 条笺 · ${this.summary.unread} 条未读 · ${this.summary.trash} 条在回收站`)
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .width('100%')
            this.ActionRow('导入浏览器书签', 'bookmarks.html', () => this.importBookmarks(), false)
            this.ActionRow('导出为 JSON', '完整字段，可程序读取', () => this.exportJson(), false)
            this.ActionRow('导出为 HTML', '可导入其他浏览器', () => this.exportHtml(), false)
            this.ActionRow('清空所有数据', '不可恢复', () => this.confirmClear(), true)

            if (this.importing) {
              Row({ space: 10 }) {
                Text('导入中')
                  .fontSize(12)
                  .fontColor($r('app.color.ink_secondary'))
                Text(this.progressText)
                  .fontSize(12)
                  .fontColor($r('app.color.ink'))
              }
              .width('100%')
              .padding({ top: 6 })
            }

            if (this.importResult !== undefined) {
              Column({ space: 4 }) {
                Text(`导入完成 · ${this.importResult.imported} 条`)
                  .fontSize(13)
                  .fontColor($r('app.color.ink'))
                Text(`跳过重复 ${this.importResult.skipped} · 失败 ${this.importResult.failed} · 文件夹 ${this.importResult.folderCount}`)
                  .fontSize(11)
                  .fontColor($r('app.color.ink_secondary'))
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
      .padding({ left: 14, right: 14, top: 7, bottom: 7 })
      .onClick(() => this.applyTheme(mode))
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
    .padding({ top: 12, bottom: 12 })
    .border({ width: { bottom: 1 }, color: $r('app.color.line') })
    .onClick(action)
  }
}
