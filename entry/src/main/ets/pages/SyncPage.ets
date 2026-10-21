import { common } from '@kit.AbilityKit';
import { LibrarySummary, FlowRepository } from '../repository/FlowRepository';
import { AppState } from '../common/AppState';
import { formatRelative } from '../common/DateUtil';
import { WebDavConfig, WebDavTransport } from '../core/sync/WebDavTransport';
import { SyncConfigStore } from '../core/sync/SyncConfigStore';
import { SyncEngine, SyncReport } from '../core/sync/SyncEngine';
import { SyncErrorText } from '../core/sync/SyncErrorText';

@ComponentV2
export struct SyncPage {
  @Param showBack: boolean = false;
  @Event onBack: () => void = () => {};
  @Local appState: AppState = AppState.shared;
  @Local summary: LibrarySummary = new LibrarySummary();
  @Local configUrl: string = '';
  @Local configUser: string = '';
  @Local configPassword: string = '';
  @Local configured: boolean = false;
  @Local syncing: boolean = false;
  @Local testing: boolean = false;
  @Local credentialInvalid: boolean = false;
  @Local status: string = '';
  @Local lastSync: number = 0;

  aboutToAppear(): void {
    this.load();
  }

  @Monitor('appState.refreshTick')
  onChanged(): void {
    this.loadSummary();
  }

  private async load(): Promise<void> {
    await this.loadSummary();
    const context = getContext(this) as common.Context;
    const config = await SyncConfigStore.load(context);
    if (config !== undefined) {
      this.configUrl = config.url;
      this.configUser = config.user;
      this.credentialInvalid = config.credentialInvalid;
      if (config.credentialInvalid) {
        this.configured = false;
        this.configPassword = '';
        this.status = '凭据需要重新输入。请填写应用密码后再同步。';
      } else {
        this.configured = true;
        this.configPassword = config.password;
      }
    }
    this.lastSync = SyncConfigStore.lastSync(context);
  }

  private async loadSummary(): Promise<void> {
    this.summary = await FlowRepository.get().summary();
  }

  private async runSync(): Promise<void> {
    if (this.syncing) {
      return;
    }
    if (this.configUrl.trim().length === 0) {
      AppState.shared.toast('先填一个 WebDAV 地址');
      return;
    }
    if (this.configUser.trim().length === 0 || this.configPassword.length === 0) {
      this.status = '请填写账号和应用密码。';
      return;
    }
    this.syncing = true;
    this.status = '正在同步…';
    try {
      const context = getContext(this) as common.Context;
      const config = this.currentConfig();
      const serverChanged = await SyncConfigStore.save(context, config);
      if (serverChanged) {
        await FlowRepository.get().clearRemoteEtags();
      }
      this.configured = true;
      this.credentialInvalid = false;
      const report: SyncReport = await SyncEngine.sync(context);
      this.status = report.message;
      this.lastSync = SyncConfigStore.lastSync(context);
      if (report.failed > 0) {
        AppState.shared.toast(`同步完成，但有 ${report.failed} 条失败`);
      } else {
        AppState.shared.toast('同步完成');
      }
    } catch (error) {
      this.status = this.errorText(error);
    } finally {
      this.syncing = false;
    }
  }

  private currentConfig(): WebDavConfig {
    const config = new WebDavConfig();
    config.url = this.configUrl.trim();
    config.user = this.configUser.trim();
    config.password = this.configPassword;
    return config;
  }

  private errorText(error: Object): string {
    return SyncErrorText.describeError(error);
  }

  private async testConnection(): Promise<void> {
    if (this.testing || this.syncing) {
      return;
    }
    if (this.configUrl.trim().length === 0) {
      this.status = '请填写 WebDAV 地址。';
      return;
    }
    if (this.configUser.trim().length === 0 || this.configPassword.length === 0) {
      this.status = '请填写账号和应用密码。';
      return;
    }
    this.testing = true;
    this.status = '正在测试连接…';
    try {
      const transport = new WebDavTransport(this.currentConfig());
      const status = await transport.test();
      this.status = `连接成功（HTTP ${status}）。`;
    } catch (error) {
      this.status = this.errorText(error);
    } finally {
      this.testing = false;
    }
  }

  private disconnect(): void {
    const context = getContext(this) as common.Context;
    SyncConfigStore.clear(context);
    this.configured = false;
    this.credentialInvalid = false;
    this.configUrl = '';
    this.configUser = '';
    this.configPassword = '';
    this.lastSync = 0;
    this.status = '已断开。数据仍在这台设备上。';
  }

  private lastSyncText(): string {
    if (this.lastSync <= 0) {
      return '还没有同步过';
    }
    return `上次同步 ${formatRelative(this.lastSync)}`;
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
        Text(this.configured ? '已连接' : '本地模式')
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 12 })

      Text('同步')
        .fontSize(34)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 14 })

      Text(this.configured ? this.lastSyncText() : '数据只在这台设备上。')
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
        .width('100%')
        .padding({ left: 20, right: 20, top: 6, bottom: 20 })

      Scroll() {
        Column({ space: 16 }) {
          Column({ space: 8 }) {
            Text(`${this.summary.total} 条笺 · ${this.summary.unread} 条未读 · ${this.summary.starred} 条星标`)
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .width('100%')
            Text('本地数据库是唯一事实源。同步只上传链接与标签，不上传正文快照。')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .lineHeight(19)
              .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.surface'))
          .border({ width: 1, color: $r('app.color.line') })
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 10 }) {
            Text('WebDAV')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
              .width('100%')
            Text('支持坚果云、群晖、Alist 等。建议使用应用密码。')
              .fontSize(11)
              .fontColor($r('app.color.ink_tertiary'))
              .width('100%')

            TextInput({ text: this.configUrl, placeholder: 'https://dav.jianguoyun.com/dav/' })
              .fontSize(13)
              .fontColor($r('app.color.ink'))
              .placeholderColor($r('app.color.ink_tertiary'))
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(6)
              .height(42)
              .onChange((value: string) => {
                this.configUrl = value;
              })

            Row({ space: 8 }) {
              TextInput({ text: this.configUser, placeholder: '账号' })
                .fontSize(13)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.ink_tertiary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(6)
                .height(42)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.configUser = value;
                })
              TextInput({ text: this.configPassword, placeholder: '应用密码' })
                .type(InputType.Password)
                .fontSize(13)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.ink_tertiary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(6)
                .height(42)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.configPassword = value;
                })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text(this.syncing ? '同步中…' : (this.configured ? '立即同步' : '连接并同步'))
                .fontSize(13)
                .fontColor($r('app.color.inverse_ink'))
                .backgroundColor($r('app.color.ink'))
                .borderRadius(6)
                .padding({ left: 18, right: 18, top: 9, bottom: 9 })
                .onClick(() => this.runSync())
              Text(this.testing ? '测试中…' : '测试连接')
                .fontSize(12)
                .fontColor($r('app.color.ink'))
                .border({ width: 1, color: $r('app.color.line_strong') })
                .borderRadius(6)
                .padding({ left: 14, right: 14, top: 9, bottom: 9 })
                .onClick(() => this.testConnection())
              if (this.configured) {
                Text('断开')
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .padding({ left: 8, right: 8, top: 14, bottom: 14 })
                  .onClick(() => this.disconnect())
              }
            }
            .width('100%')
            .margin({ top: 4 })

            if (this.status.length > 0) {
              Text(this.status)
                .fontSize(11)
                .fontColor($r('app.color.ink_secondary'))
                .lineHeight(18)
                .width('100%')
            }

            Text('凭据保存在应用沙箱内；正式使用请用 HTTPS。')
              .fontSize(10)
              .fontColor($r('app.color.ink_tertiary'))
              .width('100%')
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)

          Column({ space: 8 }) {
            Text('分布式')
              .fontSize(14)
              .fontColor($r('app.color.ink'))
            Text('同账号可信设备、同一局域网内零配置同步，将在下一阶段接入。')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
              .lineHeight(19)
          }
          .width('100%')
          .padding(18)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(10)
          .alignItems(HorizontalAlign.Start)
        }
        .padding({ left: 20, right: 20, bottom: 32 })
      }
      .layoutWeight(1)
      .scrollBar(BarState.Off)
      .edgeEffect(EdgeEffect.None)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }
}
