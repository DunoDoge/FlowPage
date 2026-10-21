import { LibrarySummary, FlowRepository } from '../repository/FlowRepository';
import { ConflictRecord } from '../model/Conflict';
import { AppState } from '../common/AppState';
import { formatRelative } from '../common/DateUtil';
import { WebDavConfig, WebDavTransport } from '../core/sync/WebDavTransport';
import { SyncConfigStore } from '../core/sync/SyncConfigStore';
import { SyncEngine, SyncReport } from '../core/sync/SyncEngine';
import { SyncErrorText } from '../core/sync/SyncErrorText';
import { SyncRecord } from '../core/sync/SyncRecord';
import { KeyCode } from '@kit.InputKit';

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
  @Local connected: boolean = false;
  @Local syncing: boolean = false;
  @Local testing: boolean = false;
  @Local credentialInvalid: boolean = false;
  @Local status: string = '';
  @Local lastSync: number = 0;
  @Local conflicts: ConflictRecord[] = [];
  @Local expandedConflict: string = '';
  @Local conflictBusy: string = '';

  aboutToAppear(): void {
    this.load();
  }

  @Monitor('appState.refreshTick')
  onChanged(): void {
    this.loadSummary();
    this.loadConflicts();
  }

  private async load(): Promise<void> {
    await this.loadSummary();
    await this.loadConflicts();
    const context = getContext(this);
    try {
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
    } catch (error) {
      this.status = '同步配置读取失败，请重试。';
    }
  }

  private async loadSummary(): Promise<void> {
    try {
      this.summary = await FlowRepository.get().summary();
    } catch (error) {
      AppState.shared.toast('没有读到数据统计');
    }
  }

  private async loadConflicts(): Promise<void> {
    try {
      this.conflicts = await FlowRepository.get().listConflicts();
    } catch (error) {
      this.conflicts = [];
    }
  }

  private conflictTitle(record: ConflictRecord): string {
    try {
      const remote = SyncRecord.parse(record.remoteJson);
      if (remote.title.trim().length > 0) {
        return remote.title;
      }
      const local = SyncRecord.parse(record.localJson);
      if (local.title.trim().length > 0) {
        return local.title;
      }
    } catch (error) {
      return record.bookmarkId;
    }
    return record.bookmarkId;
  }

  private conflictJson(raw: string): string {
    return raw.length > 1200 ? `${raw.substring(0, 1200)}…` : raw;
  }

  private async resolveConflict(record: ConflictRecord, useLocal: boolean): Promise<void> {
    if (this.conflictBusy.length > 0) {
      return;
    }
    this.conflictBusy = record.id;
    try {
      const applied = await FlowRepository.get().resolveConflict(record.id, useLocal);
      if (applied) {
        AppState.shared.toast(useLocal ? '已恢复到本地版本' : '已采用远端版本');
      } else {
        AppState.shared.toast('这条冲突已经无法恢复');
      }
      await this.loadConflicts();
    } catch (error) {
      AppState.shared.toast('恢复失败，请稍后重试');
    } finally {
      this.conflictBusy = '';
    }
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
      const context = getContext(this);
      const config = this.currentConfig();
      const serverChanged = await SyncConfigStore.save(context, config);
      if (serverChanged) {
        await FlowRepository.get().clearRemoteEtags();
      }
      this.configured = true;
      this.credentialInvalid = false;
      const report: SyncReport = await SyncEngine.sync(context);
      this.status = report.message;
      this.connected = true;
      this.lastSync = SyncConfigStore.lastSync(context);
      await this.loadConflicts();
      if (report.failed > 0) {
        AppState.shared.toast(`同步完成，但有 ${report.failed} 条失败`);
      } else {
        AppState.shared.toast('同步完成');
      }
    } catch (error) {
      this.connected = false;
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
      this.connected = true;
    } catch (error) {
      this.connected = false;
      this.status = this.errorText(error);
    } finally {
      this.testing = false;
    }
  }

  private disconnect(): void {
    const context = getContext(this);
    SyncConfigStore.clear(context);
    this.configured = false;
    this.connected = false;
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
        Text(this.connected ? '已连接' : (this.configured ? '已配置' : '本地模式'))
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
            Text(`${this.summary.total} 条笺 · ${this.summary.unread} 条未读 · ${this.summary.starred} 条星标 · ${this.summary.archived} 条归档`)
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
              .height(44)
              .onChange((value: string) => {
                this.configUrl = value;
                this.connected = false;
              })

            Row({ space: 8 }) {
              TextInput({ text: this.configUser, placeholder: '账号' })
                .fontSize(13)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.ink_tertiary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(6)
                .height(44)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.configUser = value;
                  this.connected = false;
                })
              TextInput({ text: this.configPassword, placeholder: '应用密码' })
                .type(InputType.Password)
                .fontSize(13)
                .fontColor($r('app.color.ink'))
                .placeholderColor($r('app.color.ink_tertiary'))
                .backgroundColor($r('app.color.surface_alt'))
                .borderRadius(6)
                .height(44)
                .layoutWeight(1)
                .onChange((value: string) => {
                  this.configPassword = value;
                  this.connected = false;
                })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text(this.syncing ? '同步中…' : (this.configured ? '立即同步' : '连接并同步'))
                .fontSize(13)
                .fontColor($r('app.color.inverse_ink'))
                .backgroundColor($r('app.color.ink'))
                .borderRadius(6)
                .height(44)
                .padding({ left: 18, right: 18 })
                .textAlign(TextAlign.Center)
                .accessibilityText('开始同步')
                .onClick(() => this.runSync())
              Text(this.testing ? '测试中…' : '测试连接')
                .fontSize(12)
                .fontColor($r('app.color.ink'))
                .border({ width: 1, color: $r('app.color.line_strong') })
                .borderRadius(6)
                .height(44)
                .padding({ left: 14, right: 14 })
                .textAlign(TextAlign.Center)
                .accessibilityText('测试连接')
                .onClick(() => this.testConnection())
              if (this.configured) {
                Text('断开')
                  .fontSize(12)
                  .fontColor($r('app.color.danger'))
                  .height(44)
                  .padding({ left: 8, right: 8 })
                  .accessibilityText('断开同步')
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

          this.ConflictPanel()

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

  private conflictReason(record: ConflictRecord): string {
    return record.reason === 'lww-remote-wins' ? '远端较新，已采用远端' : record.reason;
  }

  @Builder
  ConflictPanel() {
    Column({ space: 8 }) {
      Row() {
        Text('冲突记录')
          .fontSize(14)
          .fontColor($r('app.color.ink'))
        Blank()
        Text(`${this.conflicts.length}`)
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .width('100%')

      Text('两端同时修改同一笺时，远端版本胜出，被覆盖的本地版本留在这里，可随时恢复。')
        .fontSize(11)
        .fontColor($r('app.color.ink_tertiary'))
        .lineHeight(18)
        .width('100%')

      if (this.conflicts.length === 0) {
        Text('没有待处理的冲突。')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .width('100%')
      } else {
        ForEach(this.conflicts, (record: ConflictRecord) => {
          Column({ space: 8 }) {
            Row() {
              Column({ space: 3 }) {
                Text(this.conflictTitle(record))
                  .fontSize(13)
                  .fontColor($r('app.color.ink'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${this.conflictReason(record)} · ${formatRelative(record.createdAt)}`)
                  .fontSize(10)
                  .fontColor($r('app.color.ink_tertiary'))
              }
              .layoutWeight(1)
              .alignItems(HorizontalAlign.Start)

              Text(this.expandedConflict === record.id ? '收起' : '查看')
                .fontSize(12)
                .fontColor($r('app.color.ink_secondary'))
                .height(44)
                .padding({ left: 8, right: 8 })
                .accessibilityText('查看冲突版本')
                .onClick(() => {
                  this.expandedConflict = this.expandedConflict === record.id ? '' : record.id;
                })
            }
            .width('100%')

            Row({ space: 12 }) {
              Text('恢复本地')
                .fontSize(12)
                .fontColor($r('app.color.inverse_ink'))
                .backgroundColor($r('app.color.ink'))
                .borderRadius(6)
                .height(44)
                .padding({ left: 14, right: 14 })
                .accessibilityText('恢复本地版本')
                .onClick(() => this.resolveConflict(record, true))
              Text('采用远端')
                .fontSize(12)
                .fontColor($r('app.color.ink'))
                .border({ width: 1, color: $r('app.color.line_strong') })
                .borderRadius(6)
                .height(44)
                .padding({ left: 14, right: 14 })
                .accessibilityText('采用远端版本')
                .onClick(() => this.resolveConflict(record, false))
            }
            .width('100%')

            if (this.expandedConflict === record.id) {
              Column({ space: 4 }) {
                Text('本地版本')
                  .fontSize(10)
                  .fontColor($r('app.color.ink_tertiary'))
                Text(this.conflictJson(record.localJson))
                  .fontSize(10)
                  .fontColor($r('app.color.ink_secondary'))
                  .width('100%')
                Text('远端版本')
                  .fontSize(10)
                  .fontColor($r('app.color.ink_tertiary'))
                  .margin({ top: 6 })
                Text(this.conflictJson(record.remoteJson))
                  .fontSize(10)
                  .fontColor($r('app.color.ink_secondary'))
                  .width('100%')
              }
              .width('100%')
              .padding(10)
              .backgroundColor($r('app.color.surface_alt'))
              .borderRadius(6)
              .alignItems(HorizontalAlign.Start)
            }
          }
          .width('100%')
          .padding(12)
          .backgroundColor($r('app.color.surface'))
          .borderRadius(8)
          .alignItems(HorizontalAlign.Start)
        }, (record: ConflictRecord) => record.id)
      }
    }
    .width('100%')
    .padding(18)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(10)
    .alignItems(HorizontalAlign.Start)
  }
}
