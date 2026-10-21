import { common, Want } from '@kit.AbilityKit';
import { systemShare } from '@kit.ShareKit';
import { preferences } from '@kit.ArkData';
import { MetadataService } from '../core/service/MetadataService';
import { Bookmark } from '../model/Bookmark';
import { AppState } from '../common/AppState';
import { ReadState, SnapshotStatus } from '../common/Constants';
import { formatFullDate } from '../common/DateUtil';
import { domainOf } from '../common/UrlUtil';
import { FlowRepository } from '../repository/FlowRepository';

@ComponentV2
export struct DetailContent {
  @Param bookmarkId: string = '';
  @Param showBack: boolean = false;
  @Param compact: boolean = false;
  @Event onBack: () => void = () => {};
  @Event onRemoved: () => void = () => {};

  @Local bookmark: Bookmark = new Bookmark();
  @Local hasBookmark: boolean = false;
  @Local tab: number = 0;
  @Local snapshot: string = '';
  @Local snapshotLoading: boolean = false;
  @Local editing: boolean = false;
  @Local draftTitle: string = '';
  @Local draftNote: string = '';
  @Local draftExcerpt: string = '';
  @Local draftTags: string = '';
  @Local busy: boolean = false;
  @Local linkStatus: number = 0;
  @Local checking: boolean = false;
  @Local readingSize: number = 17;
  @Local readingLine: number = 30;

  aboutToAppear(): void {
    this.readReading();
    this.load();
  }

  @Monitor('bookmarkId')
  onBookmarkChanged(): void {
    this.load();
  }

  private async load(): Promise<void> {
    if (this.bookmarkId.length === 0) {
      this.hasBookmark = false;
      return;
    }
    const repo = FlowRepository.get();
    const found = await repo.get(this.bookmarkId);
    if (found === undefined) {
      this.hasBookmark = false;
      return;
    }
    this.bookmark = found;
    this.hasBookmark = true;
    this.linkStatus = found.linkStatus;
    this.draftTitle = found.title;
    this.draftNote = found.note;
    this.draftExcerpt = found.excerpt;
    this.draftTags = found.tags.join(', ');
    if (found.readState === ReadState.UNREAD && !found.deleted) {
      repo.setRead(found.id, ReadState.READ);
      found.readState = ReadState.READ;
    }
    if (this.tab === 0) {
      this.loadSnapshot(found);
    }
  }

  private async loadSnapshot(bookmark: Bookmark): Promise<void> {
    if (bookmark.snapshotStatus !== SnapshotStatus.DONE) {
      this.snapshot = '';
      return;
    }
    this.snapshotLoading = true;
    this.snapshot = '';
    this.snapshot = await FlowRepository.get().loadSnapshot(bookmark);
    this.snapshotLoading = false;
  }

  private readReading(): void {
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: 'flowpage_settings' });
      const size = store.getSync('reading_size', 17);
      this.readingSize = typeof size === 'number' ? size : 17;
      this.readingLine = this.readingSize + 13;
    } catch (error) {
      this.readingSize = 17;
      this.readingLine = 30;
    }
  }

  private changeReading(delta: number): void {
    let next = this.readingSize + delta;
    if (next < 15) {
      next = 15;
    }
    if (next > 21) {
      next = 21;
    }
    this.readingSize = next;
    this.readingLine = next + 13;
    try {
      const store = preferences.getPreferencesSync(getContext(this), { name: 'flowpage_settings' });
      store.putSync('reading_size', next);
      store.flush().catch(() => {});
    } catch (error) {
      return;
    }
  }

  private async checkLink(): Promise<void> {
    if (!this.hasBookmark || this.checking) {
      return;
    }
    this.checking = true;
    const status = await MetadataService.checkLink(this.bookmark.url);
    this.linkStatus = status;
    await FlowRepository.get().setLinkStatus(this.bookmark.id, status);
    this.checking = false;
    if (status === 1) {
      AppState.shared.toast('链接可用');
    } else if (status === 2) {
      AppState.shared.toast('链接可能失效');
    } else {
      AppState.shared.toast('暂时无法判断');
    }
  }

  private linkLabel(): string {
    if (this.checking) {
      return '正在检查链接…';
    }
    if (this.linkStatus === 1) {
      return '链接可用';
    }
    if (this.linkStatus === 2) {
      return '链接可能失效';
    }
    return '链接状态未检查';
  }

  private async refreshMetadata(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    this.busy = true;
    await FlowRepository.get().applyMetadata(this.bookmark.id);
    await this.load();
    this.busy = false;
    AppState.shared.toast('已经重新抓取');
  }

  private openOriginal(): void {
    if (!this.hasBookmark) {
      return;
    }
    try {
      const context = getContext(this) as common.UIAbilityContext;
      const want: Want = {
        action: 'ohos.want.action.viewData',
        uri: this.bookmark.url
      };
      context.startAbility(want);
    } catch (error) {
      AppState.shared.toast('没有找到可打开它的应用');
    }
  }

  private async shareBookmark(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    const data = new systemShare.SharedData({
      utd: 'general.hyperlink',
      content: `flowpage://bookmark/${this.bookmark.id}`,
      title: this.bookmark.title,
      description: '来自流笺'
    });
    const controller = new systemShare.ShareController(data);
    try {
      const context = this.getUIContext().getHostContext() as common.UIAbilityContext;
      await controller.show(context, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (error) {
      AppState.shared.toast('没有拉起分享面板');
    }
  }

  private toggleStar(): void {
    if (!this.hasBookmark) {
      return;
    }
    const next = !this.bookmark.starred;
    FlowRepository.get().setStarred(this.bookmark.id, next);
    this.bookmark.starred = next;
  }

  private toggleArchive(): void {
    if (!this.hasBookmark) {
      return;
    }
    const next = !this.bookmark.archived;
    FlowRepository.get().setArchived(this.bookmark.id, next);
    this.bookmark.archived = next;
    if (next) {
      this.onRemoved();
    }
  }

  private async restoreBookmark(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    const id = this.bookmark.id;
    await FlowRepository.get().restore(id);
    AppState.shared.toast('已恢复');
    this.onRemoved();
  }

  private async purgeBookmark(id: string): Promise<void> {
    await FlowRepository.get().purge(id);
    AppState.shared.toast('已彻底删除');
    this.onRemoved();
  }

  private confirmDelete(): void {
    if (!this.hasBookmark) {
      return;
    }
    const id = this.bookmark.id;
    if (this.bookmark.deleted) {
      AlertDialog.show({
        title: '彻底删除这一笺？',
        message: '删除后不可恢复，正文快照也会一并删除。',
        primaryButton: {
          value: '取消',
          action: () => {}
        },
        secondaryButton: {
          value: '彻底删除',
          fontColor: $r('app.color.danger'),
          action: () => {
            this.purgeBookmark(id);
          }
        }
      });
      return;
    }
    AlertDialog.show({
      title: '删除这一笺？',
      message: '30 天内可在回收站恢复。',
      primaryButton: {
        value: '取消',
        action: () => {}
      },
      secondaryButton: {
        value: '删除',
        fontColor: $r('app.color.danger'),
        action: () => {
          FlowRepository.get().delete(id);
          AppState.shared.toast('已放进回收站');
          this.onRemoved();
        }
      }
    });
  }

  private async saveEdits(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    this.busy = true;
    const repo = FlowRepository.get();
    const id = this.bookmark.id;
    await repo.setTitle(id, this.draftTitle.trim());
    await repo.setNote(id, this.draftNote);
    await repo.setExcerpt(id, this.draftExcerpt);
    const tags: string[] = [];
    const raw = this.draftTags.split(',');
    for (let i = 0; i < raw.length; i++) {
      const name = raw[i].trim();
      if (name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
    }
    const rawCn = this.draftTags.split('，');
    for (let i = 0; i < rawCn.length; i++) {
      const name = rawCn[i].trim();
      if (name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
    }
    await repo.setTags(id, tags);
    await this.load();
    this.editing = false;
    this.busy = false;
  }

  private switchTab(index: number): void {
    this.tab = index;
    if (index === 0 && this.hasBookmark) {
      this.loadSnapshot(this.bookmark);
    }
  }

  build() {
    Column() {
      if (!this.hasBookmark) {
        this.EmptyDetail()
      } else {
        this.DetailBody()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  @Builder
  EmptyDetail() {
    Column({ space: 12 }) {
      Text('选一笺')
        .fontSize(24)
        .fontColor($r('app.color.ink'))
      Text('左边收着的链接，会在这里展开。')
        .fontSize(13)
        .fontColor($r('app.color.ink_secondary'))
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  DetailBody() {
    List() {
      ListItem() {
        Row() {
          Column() {
            Row() {
              if (this.showBack) {
                Text('返回')
                  .fontSize(13)
                  .fontColor($r('app.color.ink_secondary'))
                  .padding({ top: 8, bottom: 8, right: 12 })
                  .onClick(() => this.onBack())
              }
              Blank()
              if (!this.bookmark.deleted) {
                Text(this.editing ? '取消' : '编辑')
                  .fontSize(13)
                  .fontColor($r('app.color.ink_secondary'))
                  .padding({ left: 10, top: 8, bottom: 8 })
                  .onClick(() => {
                    this.editing = !this.editing;
                    if (!this.editing) {
                      this.draftTitle = this.bookmark.title;
                      this.draftNote = this.bookmark.note;
                      this.draftExcerpt = this.bookmark.excerpt;
                      this.draftTags = this.bookmark.tags.join(', ');
                    }
                  })
              }
            }
            .width('100%')
            .padding({ top: 8 })

            if (this.editing) {
              this.Editor()
            } else {
              this.Reader()
            }
          }
          .width('100%')
          .constraintSize({ maxWidth: 680 })
          .padding({ left: this.compact ? 20 : 32, right: this.compact ? 20 : 32, bottom: 48 })
          .alignItems(HorizontalAlign.Start)
        }
        .width('100%')
        .justifyContent(FlexAlign.Center)
      }
    }
    .width('100%')
    .height('100%')
    .scrollBar(BarState.Off)
    .edgeEffect(EdgeEffect.None)
  }

  @Builder
  Reader() {
    Column() {
      Text(this.bookmark.title.length > 0 ? this.bookmark.title : this.bookmark.url)
        .fontSize(this.compact ? 26 : 30)
        .fontWeight(FontWeight.Bold)
        .fontColor($r('app.color.ink'))
        .lineHeight(this.compact ? 35 : 40)
        .width('100%')
        .margin({ top: 18 })

      Row({ space: 8 }) {
        Text(domainOf(this.bookmark.url))
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
        Text('·')
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
        Text(formatFullDate(this.bookmark.createdAt))
          .fontSize(12)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .margin({ top: 10 })

      if (this.bookmark.tags.length > 0) {
        Flex({ wrap: FlexWrap.Wrap }) {
          ForEach(this.bookmark.tags, (tag: string) => {
            Text(tag)
              .fontSize(11)
              .fontColor($r('app.color.ink_secondary'))
              .padding({ left: 7, right: 7, top: 3, bottom: 3 })
              .border({ width: 1, color: $r('app.color.line_strong') })
              .borderRadius(2)
              .margin({ right: 6, top: 6 })
          }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ top: 10 })
      }

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))
        .margin({ top: 20, bottom: 18 })

      Row({ space: 22 }) {
        this.TabLabel('正文', 0)
        this.TabLabel('摘录', 1)
        this.TabLabel('备注', 2)
      }
      .width('100%')

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))
        .margin({ top: 8, bottom: 18 })

      if (this.tab === 0 && this.snapshot.length > 0) {
        Row({ space: 12 }) {
          Text('字号')
            .fontSize(10)
            .fontColor($r('app.color.ink_tertiary'))
          Text('A−')
            .fontSize(13)
            .fontColor($r('app.color.ink_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => this.changeReading(-2))
          Text('A+')
            .fontSize(13)
            .fontColor($r('app.color.ink_secondary'))
            .padding({ left: 8, right: 8, top: 4, bottom: 4 })
            .onClick(() => this.changeReading(2))
        }
        .width('100%')
        .margin({ bottom: 10 })
      }

      if (this.tab === 0) {
        if (this.snapshotLoading) {
          Text('正在翻出正文…')
            .fontSize(14)
            .fontColor($r('app.color.ink_tertiary'))
        } else if (this.snapshot.length > 0) {
          Text(this.snapshot)
            .fontSize(this.readingSize)
            .lineHeight(this.readingLine)
            .fontColor($r('app.color.ink'))
            .width('100%')
            .textAlign(TextAlign.Start)
        } else {
          Column({ space: 10 }) {
            Text('这条还没存下正文。')
              .fontSize(15)
              .fontColor($r('app.color.ink_secondary'))
            Text(this.busy ? '正在抓取…' : '重试抓取')
              .fontSize(13)
              .fontColor($r('app.color.ink'))
              .border({ width: 1, color: $r('app.color.line_strong') })
              .borderRadius(6)
              .padding({ left: 12, right: 12, top: 7, bottom: 7 })
              .onClick(() => {
                if (!this.busy) {
                  this.refreshMetadata();
                }
              })
          }
          .alignItems(HorizontalAlign.Start)
          .width('100%')
          .padding({ top: 12, bottom: 12 })
        }
      } else if (this.tab === 1) {
        if (this.bookmark.excerpt.length > 0) {
          Row() {
            Row()
              .width(2)
              .height('100%')
              .backgroundColor($r('app.color.line_strong'))
              .margin({ right: 12 })
            Text(this.bookmark.excerpt)
              .fontSize(16)
              .lineHeight(28)
              .fontColor($r('app.color.ink_secondary'))
              .layoutWeight(1)
          }
          .alignItems(VerticalAlign.Top)
          .width('100%')
        } else {
          Text('还没有摘录。点「编辑」写下让你停下来的那句。')
            .fontSize(14)
            .fontColor($r('app.color.ink_tertiary'))
            .lineHeight(23)
        }
      } else {
        if (this.bookmark.note.length > 0) {
          Text(this.bookmark.note)
            .fontSize(16)
            .lineHeight(28)
            .fontColor($r('app.color.ink'))
            .width('100%')
        } else {
          Text('还没有备注。')
            .fontSize(14)
            .fontColor($r('app.color.ink_tertiary'))
        }
      }

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))
        .margin({ top: 28, bottom: 16 })

      Flex({ wrap: FlexWrap.Wrap }) {
        if (this.bookmark.deleted) {
          this.ActionLabel('恢复', () => this.restoreBookmark())
          this.ActionLabel('打开原文', () => this.openOriginal())
          this.ActionLabel('彻底删除', () => this.confirmDelete())
        } else {
          this.ActionLabel('打开原文', () => this.openOriginal())
          this.ActionLabel('分享', () => this.shareBookmark())
          this.ActionLabel(this.bookmark.starred ? '取消星标' : '加星标', () => this.toggleStar())
          this.ActionLabel(this.bookmark.archived ? '取消归档' : '归档', () => this.toggleArchive())
          this.ActionLabel('查链接', () => this.checkLink())
          this.ActionLabel('删除', () => this.confirmDelete())
        }
      }
      .width('100%')

      Text(this.snapshot.length > 0 ? '已存下正文' : '正文待补全')
        .fontSize(11)
        .fontColor($r('app.color.ink_tertiary'))
        .margin({ top: 18 })
      Text(this.linkLabel())
        .fontSize(11)
        .fontColor(this.linkStatus === 2 ? $r('app.color.danger') : $r('app.color.ink_tertiary'))
        .margin({ top: 4 })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  TabLabel(label: string, index: number) {
    Text(label)
      .fontSize(13)
      .fontColor(this.tab === index ? $r('app.color.ink') : $r('app.color.ink_tertiary'))
      .fontWeight(this.tab === index ? FontWeight.Medium : FontWeight.Normal)
      .padding({ bottom: 7 })
      .border({
        width: { bottom: this.tab === index ? 1 : 0 },
        color: $r('app.color.ink')
      })
      .onClick(() => this.switchTab(index))
  }

  @Builder
  ActionLabel(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(label === '删除' || label === '彻底删除' ? $r('app.color.danger') : $r('app.color.ink_secondary'))
      .padding({ right: 18, top: 8, bottom: 8 })
      .onClick(action)
  }

  @Builder
  Editor() {
    Column({ space: 14 }) {
      Text('标题')
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
      TextInput({ text: this.draftTitle })
        .fontSize(16)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.surface'))
        .border({ width: 1, color: $r('app.color.line') })
        .borderRadius(6)
        .height(44)
        .onChange((value: string) => {
          this.draftTitle = value;
        })

      Text('标签（用逗号分隔）')
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
      TextInput({ text: this.draftTags, placeholder: '技术, 稍后读' })
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.surface'))
        .border({ width: 1, color: $r('app.color.line') })
        .borderRadius(6)
        .height(44)
        .onChange((value: string) => {
          this.draftTags = value;
        })

      Text('摘录')
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
      TextArea({ text: this.draftExcerpt, placeholder: '留下一句。' })
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.surface'))
        .border({ width: 1, color: $r('app.color.line') })
        .borderRadius(6)
        .height(96)
        .onChange((value: string) => {
          this.draftExcerpt = value;
        })

      Text('备注')
        .fontSize(12)
        .fontColor($r('app.color.ink_tertiary'))
      TextArea({ text: this.draftNote, placeholder: '为什么收下它？' })
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .backgroundColor($r('app.color.surface'))
        .border({ width: 1, color: $r('app.color.line') })
        .borderRadius(6)
        .height(96)
        .onChange((value: string) => {
          this.draftNote = value;
        })

      Text(this.busy ? '保存中…' : '保存')
        .fontSize(14)
        .fontColor($r('app.color.inverse_ink'))
        .backgroundColor($r('app.color.ink'))
        .borderRadius(6)
        .padding({ left: 22, right: 22, top: 10, bottom: 10 })
        .margin({ top: 6 })
        .onClick(() => {
          if (!this.busy && this.hasBookmark && this.bookmark.id.length > 0) {
            this.saveEdits();
          }
        })
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: 22 })
  }
}
