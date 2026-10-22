import { Want } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { systemShare } from '@kit.ShareKit';
import { MetadataService } from '../core/service/MetadataService';
import { ArticleDocument } from '../model/Article';
import { MetadataApplyResult } from '../model/MetadataResult';
import { Bookmark } from '../model/Bookmark';
import { AppState } from '../common/AppState';
import { ReadState, SnapshotStatus } from '../common/Constants';
import { formatFullDate } from '../common/DateUtil';
import { deepLinkTextOf, shareContentOf } from '../common/ShareUtil';
import { domainOf } from '../common/UrlUtil';
import { FlowRepository } from '../repository/FlowRepository';
import { ReaderView } from './ReaderView';

@ComponentV2
export struct DetailContent {
  @Param bookmarkId: string = '';
  @Param showBack: boolean = false;
  @Param compact: boolean = false;
  @Event onBack: () => void = () => {};
  @Event onRemoved: () => void = () => {};

  @Local appState: AppState = AppState.shared;
  @Local bookmark: Bookmark = new Bookmark();
  @Local hasBookmark: boolean = false;
  @Local tab: number = 0;
  @Local article: ArticleDocument = new ArticleDocument();
  @Local articleLoading: boolean = false;
  @Local showReader: boolean = false;
  @Local editing: boolean = false;
  @Local draftTitle: string = '';
  @Local draftNote: string = '';
  @Local draftExcerpt: string = '';
  @Local draftTags: string = '';
  @Local busy: boolean = false;
  @Local linkStatus: number = 0;
  @Local checking: boolean = false;
  private readTimer: number = -1;
  private articleKey: string = '';

  aboutToAppear(): void {
    this.load();
  }

  aboutToDisappear(): void {
    this.clearReadingTimer();
  }

  @Monitor('bookmarkId')
  onBookmarkChanged(): void {
    this.load();
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    this.syncSnapshot().catch(() => {});
  }

  // applyMetadata() can run outside this page (e.g. the share flow). Refresh
  // only the snapshot fields so draft edits are not clobbered by a list tick.
  private async syncSnapshot(): Promise<void> {
    if (this.bookmarkId.length === 0 || this.busy || this.editing) {
      return;
    }
    const found = await FlowRepository.get().get(this.bookmarkId);
    if (found === undefined) {
      return;
    }
    const snapshotChanged = found.snapshotPath !== this.bookmark.snapshotPath ||
      found.snapshotAt !== this.bookmark.snapshotAt;
    this.bookmark = found;
    this.hasBookmark = true;
    this.linkStatus = found.linkStatus;
    if (!snapshotChanged) {
      return;
    }
    this.articleKey = '';
    this.article = new ArticleDocument();
    if (this.tab === 0) {
      await this.loadArticle(found);
    }
  }

  private clearReadingTimer(): void {
    if (this.readTimer >= 0) {
      clearTimeout(this.readTimer);
      this.readTimer = -1;
    }
  }

  private startReadingTimer(id: string): void {
    this.clearReadingTimer();
    this.readTimer = setTimeout(() => {
      this.readTimer = -1;
      this.markRead(id);
    }, 30000);
  }

  private async load(): Promise<void> {
    this.clearReadingTimer();
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
    if (this.bookmark.id !== found.id) {
      this.articleKey = '';
      this.article = new ArticleDocument();
    }
    this.bookmark = found;
    this.hasBookmark = true;
    this.linkStatus = found.linkStatus;
    this.draftTitle = found.title;
    this.draftNote = found.note;
    this.draftExcerpt = found.excerpt;
    this.draftTags = found.tags.join(', ');
    if (found.readState === ReadState.UNREAD && !found.deleted) {
      found.readState = ReadState.READING;
      try {
        await repo.setRead(found.id, ReadState.READING);
      } catch (error) {
        return;
      }
    }
    if (!found.deleted && found.readState !== ReadState.READ) {
      this.startReadingTimer(found.id);
    }
    if (this.tab === 0) {
      await this.loadArticle(found);
    }
  }

  private articleKeyOf(bookmark: Bookmark): string {
    return `${bookmark.id}|${bookmark.snapshotPath}|${bookmark.snapshotAt}`;
  }

  private async loadArticle(bookmark: Bookmark): Promise<void> {
    const key = this.articleKeyOf(bookmark);
    if (this.articleKey === key) {
      return;
    }
    this.articleKey = key;
    if (bookmark.snapshotPath.length === 0) {
      this.article = new ArticleDocument();
      this.articleLoading = false;
      return;
    }
    this.articleLoading = true;
    try {
      const loaded = await FlowRepository.get().loadArticle(bookmark);
      if (this.articleKey === key) {
        this.article = loaded;
      }
    } catch (error) {
      this.article = new ArticleDocument();
    } finally {
      this.articleLoading = false;
    }
  }

  private async checkLink(): Promise<void> {
    if (!this.hasBookmark || this.checking) {
      return;
    }
    this.checking = true;
    try {
      const status = await MetadataService.checkLink(this.bookmark.url);
      this.linkStatus = status;
      await FlowRepository.get().setLinkStatus(this.bookmark.id, status);
      if (status === 1) {
        AppState.shared.toast('链接可用');
      } else if (status === 2) {
        AppState.shared.toast('链接可能失效');
      } else {
        AppState.shared.toast('暂时无法判断');
      }
    } catch (error) {
      AppState.shared.toast('链接检查失败，请稍后再试');
    } finally {
      this.checking = false;
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
    if (!this.hasBookmark || this.busy) {
      return;
    }
    this.busy = true;
    try {
      const result = await FlowRepository.get().applyMetadata(this.bookmark.id);
      if (result === MetadataApplyResult.FAILED) {
        AppState.shared.toast('抓取失败，请检查网络后重试');
        return;
      }
      this.articleKey = '';
      await this.load();
      if (result === MetadataApplyResult.EMPTY) {
        AppState.shared.toast('没有提取到正文，请稍后再试');
      } else {
        AppState.shared.toast('已经重新抓取');
      }
    } catch (error) {
      AppState.shared.toast('抓取失败，请检查网络后重试');
    } finally {
      this.busy = false;
    }
  }

  private openOriginal(): void {
    if (!this.hasBookmark) {
      return;
    }
    const context = AppState.shared.abilityContext;
    if (context === undefined) {
      AppState.shared.toast('没有找到可打开它的应用');
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: this.bookmark.url
    };
    context.startAbility(want).catch(() => {
      AppState.shared.toast('没有找到可打开它的应用');
    });
  }

  private async shareBookmark(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    const data = new systemShare.SharedData({
      utd: 'general.hyperlink',
      content: shareContentOf(this.bookmark),
      title: this.bookmark.title,
      description: domainOf(this.bookmark.url)
    });
    const controller = new systemShare.ShareController(data);
    const shareContext = AppState.shared.abilityContext;
    if (shareContext === undefined) {
      AppState.shared.toast('没有拉起分享面板');
      return;
    }
    try {
      await controller.show(shareContext, {
        selectionMode: systemShare.SelectionMode.SINGLE,
        previewMode: systemShare.SharePreviewMode.DEFAULT
      });
    } catch (error) {
      AppState.shared.toast('没有拉起分享面板');
    }
  }

  private async copyDeepLink(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, deepLinkTextOf(this.bookmark));
      await pasteboard.getSystemPasteboard().setData(data);
      AppState.shared.toast('深链已复制');
    } catch (error) {
      AppState.shared.toast('复制深链失败');
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

  private async markRead(id: string): Promise<void> {
    this.clearReadingTimer();
    try {
      await FlowRepository.get().setRead(id, ReadState.READ);
      if (this.bookmark.id === id) {
        this.bookmark.readState = ReadState.READ;
        AppState.shared.toast('已标记为已读');
      }
    } catch (error) {
      AppState.shared.toast('没能标记已读');
    }
  }

  private async toggleRead(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    if (this.bookmark.readState === ReadState.READ) {
      this.clearReadingTimer();
      try {
        await FlowRepository.get().setRead(this.bookmark.id, ReadState.UNREAD);
        this.bookmark.readState = ReadState.UNREAD;
        AppState.shared.toast('已标记为未读');
      } catch (error) {
        AppState.shared.toast('没能标记未读');
      }
      return;
    }
    await this.markRead(this.bookmark.id);
  }

  private async restoreBookmark(): Promise<void> {
    if (!this.hasBookmark) {
      return;
    }
    const id = this.bookmark.id;
    try {
      await FlowRepository.get().restore(id);
      AppState.shared.toast('已恢复');
      this.onRemoved();
    } catch (error) {
      AppState.shared.toast('恢复失败，请稍后再试');
    }
  }

  private async purgeBookmark(id: string): Promise<void> {
    try {
      await FlowRepository.get().purge(id);
      AppState.shared.toast('已彻底删除');
      this.onRemoved();
    } catch (error) {
      AppState.shared.toast('删除失败，请稍后再试');
    }
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
          action: async () => {
            try {
              await FlowRepository.get().delete(id);
              AppState.shared.toast('已放进回收站');
              this.onRemoved();
            } catch (error) {
              AppState.shared.toast('删除失败，请重试');
            }
          }
        }
    });
  }

  private draftTagList(): string[] {
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
    return tags;
  }

  private async saveEdits(): Promise<void> {
    if (!this.hasBookmark || this.busy) {
      return;
    }
    this.busy = true;
    try {
      await FlowRepository.get().saveEdits(
        this.bookmark.id,
        this.draftTitle.trim(),
        this.draftNote,
        this.draftExcerpt,
        this.draftTagList()
      );
      await this.load();
      this.editing = false;
      AppState.shared.toast('已保存');
    } catch (error) {
      AppState.shared.toast('保存失败，本地没有写入');
    } finally {
      this.busy = false;
    }
  }

  private switchTab(index: number): void {
    this.tab = index;
    if (index === 0 && this.hasBookmark) {
      this.loadArticle(this.bookmark).catch(() => {});
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
    .onKeyEvent((event: KeyEvent) => {
      if (event.type === KeyType.Down && event.keyCode === KeyCode.KEYCODE_ESCAPE && this.showBack) {
        this.onBack();
      }
    })
    .bindContentCover(this.showReader, this.FullReader(), {
      enableSafeArea: true,
      onDisappear: () => {
        this.showReader = false;
      }
    })
  }

  @Builder
  FullReader() {
    ReaderView({
      bookmark: this.bookmark,
      bookmarkId: this.bookmark.id,
      article: this.article,
      compact: this.compact,
      immersive: true,
      loading: this.articleLoading || this.busy,
      onClose: () => {
        this.showReader = false;
      },
      onRetry: () => {
        this.refreshMetadata();
      },
      onReadComplete: () => {
        this.markRead(this.bookmark.id);
      },
      onExcerptSaved: (excerpt: string) => {
        this.bookmark.excerpt = excerpt;
        this.draftExcerpt = excerpt;
      }
    })
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
                  .height(44)
                  .padding({ right: 12 })
                  .accessibilityText('返回列表')
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
              if (!this.bookmark.deleted) {
                Text(this.editing ? '取消' : '编辑')
                  .fontSize(13)
                  .fontColor($r('app.color.ink_secondary'))
                  .height(44)
                  .padding({ left: 10 })
                  .accessibilityText(this.editing ? '取消编辑' : '编辑这一笺')
                  .focusable(true)
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
        .accessibilityText(this.bookmark.title)

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
        Text(this.bookmark.readState === ReadState.READ ? '已读' : (this.bookmark.readState === ReadState.READING ? '阅读中' : '未读'))
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
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

      if (this.tab === 0) {
        ReaderView({
          bookmark: this.bookmark,
          bookmarkId: this.bookmark.id,
          article: this.article,
          compact: this.compact,
          immersive: false,
          loading: this.articleLoading || this.busy,
          onOpenImmersive: () => {
            this.showReader = true;
          },
          onRetry: () => {
            this.refreshMetadata();
          },
          onExcerptSaved: (excerpt: string) => {
            this.bookmark.excerpt = excerpt;
            this.draftExcerpt = excerpt;
          }
        })
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
          this.ActionLabel('复制深链', () => this.copyDeepLink())
          this.ActionLabel(this.bookmark.starred ? '取消星标' : '加星标', () => this.toggleStar())
          this.ActionLabel(this.bookmark.archived ? '取消归档' : '归档', () => this.toggleArchive())
          this.ActionLabel('查链接', () => this.checkLink())
          this.ActionLabel('重新抓取', () => this.refreshMetadata())
          this.ActionLabel(this.bookmark.readState === ReadState.READ ? '标记未读' : '标记已读', () => this.toggleRead())
          this.ActionLabel('删除', () => this.confirmDelete())
        }
      }
      .width('100%')

      Text(this.article.blocks.length > 0 ? '已存下正文' : (this.bookmark.snapshotStatus === SnapshotStatus.OFF ? '自动快照已关闭' : '正文待补全'))
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
      .height(44)
      .padding({ top: 13 })
      .border({
        width: { bottom: this.tab === index ? 1 : 0 },
        color: $r('app.color.ink')
      })
      .accessibilityText(`切换到${label}`)
      .focusable(true)
      .onClick(() => this.switchTab(index))
  }

  @Builder
  ActionLabel(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(label === '删除' || label === '彻底删除' ? $r('app.color.danger') : $r('app.color.ink_secondary'))
      .height(44)
      .padding({ right: 18 })
      .accessibilityText(label)
      .focusable(true)
      .onClick(action)
      .onKeyEvent((event: KeyEvent) => {
        if (event.type === KeyType.Down &&
          (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
          action();
        }
      })
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
        .accessibilityText('标题')
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
        .accessibilityText('标签，用逗号分隔')
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
        .accessibilityText('摘录')
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
        .accessibilityText('备注')
        .onChange((value: string) => {
          this.draftNote = value;
        })

      Text(this.busy ? '保存中…' : '保存')
        .fontSize(14)
        .fontColor($r('app.color.inverse_ink'))
        .backgroundColor($r('app.color.ink'))
        .borderRadius(6)
        .height(44)
        .padding({ left: 22, right: 22 })
        .textAlign(TextAlign.Center)
        .margin({ top: 6 })
        .accessibilityText('保存编辑')
        .focusable(true)
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
