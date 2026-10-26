import { KeyCode } from '@kit.InputKit';
import { pasteboard } from '@kit.BasicServicesKit';
import {
  SelectionContainer,
  SelectionContainerAttribute,
  SelectionContainerController,
  SelectionContainerTextJoinStyle
} from '@kit.ArkUI';
import { AppState } from '../common/AppState';
import { ArticleSignature } from '../common/ArticleSignature';
import { ReaderSegment, readerSegments } from '../common/ReaderSegments';
import { ReaderPrefs } from '../common/ReaderPrefs';
import { ReaderSettings } from '../common/ReaderSettings';
import { readerBlockProgress, readerProgressRatio } from '../common/ReaderProgress';
import { formatFullDate } from '../common/DateUtil';
import { domainOf } from '../common/UrlUtil';
import { ArticleBlock, ArticleBlockType, ArticleDocument, ReaderTocEntry } from '../model/Article';
import { Bookmark } from '../model/Bookmark';
import { ReadState, SnapshotStatus } from '../common/Constants';
import { FlowRepository } from '../repository/FlowRepository';
import { ReaderSearchIndex, ReaderSearchService } from '../core/service/ReaderSearchService';

const INITIAL_BLOCKS: number = 200;
const BLOCK_BATCH: number = 200;

@ComponentV2
export struct ReaderView {
  @Param bookmark: Bookmark = new Bookmark();
  @Param bookmarkId: string = '';
  @Param article: ArticleDocument = new ArticleDocument();
  @Param compact: boolean = false;
  @Param immersive: boolean = false;
  @Param loading: boolean = false;
  @Param externalChrome: boolean = false;
  @Param transient: boolean = false;
  @Param initialBlock: number = -1;
  @Param savedOnce: boolean = false;
  @Event onClose: () => void = () => {};
  @Event onOpenImmersive: () => void = () => {};
  @Event onRetry: () => void = () => {};
  @Event onReadComplete: () => void = () => {};
  @Event onExcerptSaved: (excerpt: string) => void = (excerpt: string) => {};
  @Event onOpenLink: (url: string) => void = (url: string) => {};
  @Event onOpenBrowser: () => void = () => {};
  @Event onSavePage: () => void = () => {};
  @Event onPositionChanged: (index: number) => void = (index: number) => {};

  @Local settings: ReaderSettings = ReaderSettings.shared;
  @Local toc: ReaderTocEntry[] = [];
  @Local showSettings: boolean = false;
  @Local showToc: boolean = false;
  @Local searching: boolean = false;
  @Local query: string = '';
  @Local activeQuery: string = '';
  @Local matches: number[] = [];
  @Local matchCursor: number = -1;
  @Local progress: number = 0;
  @Local blockFirst: number = 0;
  @Local visibleCount: number = INITIAL_BLOCKS;
  @Local readReported: boolean = false;
  @Local selectedText: string = '';
  private scroller: Scroller = new Scroller();
  private selectionController: SelectionContainerController = new SelectionContainerController();
  private restoring: boolean = false;
  private restoreTimer: number = -1;
  private restoreAttempts: number = 0;
  private searchTimer: number = -1;
  private anchorTimer: number = -1;
  private progressTimer: number = -1;
  private pendingSearchIndex: number = -1;
  private pendingJumpIndex: number = -1;
  private blockOffsets: number[] = [];
  private blockHeights: number[] = [];
  private measuredBlocks: number = 0;
  private contentBottom: number = 0;
  private viewportHeight: number = 0;
  private positionReady: boolean = false;
  private articleSignature: string = '';
  private extendAt: number = 0;
  private searchIndex: ReaderSearchIndex | null = null;
  private searchSignature: string = '';
  private searchGeneration: number = 0;

  aboutToAppear(): void {
    this.visibleCount = Math.min(INITIAL_BLOCKS, this.article.blocks.length);
    this.settings.load(getContext(this));
    this.restoreAttempts = 0;
    this.articleSignature = ArticleSignature.of(this.article);
    this.rebuildToc();
    if (this.immersive) {
      this.scheduleRestore();
    }
  }

  aboutToDisappear(): void {
    this.savePosition();
    this.clearTimers();
    // also invalidates in-flight search callbacks via the generation bump
    this.releaseSearchIndex();
  }

  @Monitor('article')
  onArticleChanged(): void {
    const signature = ArticleSignature.of(this.article);
    if (signature === this.articleSignature && this.article.blocks.length > 0) {
      return;
    }
    this.articleSignature = signature;
    this.resetReaderState();
    this.rebuildToc();
    this.releaseSearchIndex();
    this.activeQuery = '';
    this.matches = [];
    this.matchCursor = -1;
    this.pendingSearchIndex = -1;
    this.pendingJumpIndex = -1;
    this.showToc = false;
    this.showSettings = false;
    if (this.immersive) {
      this.scheduleRestore();
    }
    if (this.query.trim().length > 0) {
      this.applySearch(this.query);
    }
  }

  @Monitor('bookmarkId')
  onBookmarkChanged(): void {
    this.resetReaderState();
    this.query = '';
    this.activeQuery = '';
    this.matches = [];
    this.matchCursor = -1;
    this.pendingSearchIndex = -1;
    this.pendingJumpIndex = -1;
    this.searching = false;
    this.showToc = false;
    this.showSettings = false;
    this.articleSignature = '';
    this.releaseSearchIndex();
    this.rebuildToc();
    if (this.immersive) {
      this.scheduleRestore();
    }
  }

  private resetReaderState(): void {
    this.clearSearchTimer();
    this.clearAnchorTimer();
    this.clearProgressTimer();
    this.progress = 0;
    this.blockFirst = 0;
    this.selectedText = '';
    this.readReported = false;
    this.blockOffsets = [];
    this.blockHeights = [];
    this.measuredBlocks = 0;
    this.contentBottom = 0;
    this.positionReady = false;
    this.restoreAttempts = 0;
    this.visibleCount = Math.min(INITIAL_BLOCKS, this.article.blocks.length);
    this.extendAt = 0;
  }

  private clearSearchTimer(): void {
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
      this.searchTimer = -1;
    }
  }

  private clearAnchorTimer(): void {
    if (this.anchorTimer >= 0) {
      clearTimeout(this.anchorTimer);
      this.anchorTimer = -1;
    }
  }

  private clearProgressTimer(): void {
    if (this.progressTimer >= 0) {
      clearTimeout(this.progressTimer);
      this.progressTimer = -1;
    }
  }

  private clearTimers(): void {
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
      this.restoreTimer = -1;
    }
    this.clearAnchorTimer();
    this.clearSearchTimer();
    this.clearProgressTimer();
  }

  private currentId(): string {
    return this.bookmarkId.length > 0 ? this.bookmarkId : this.bookmark.id;
  }

  private shownBlocks(): ArticleBlock[] {
    if (this.visibleCount >= this.article.blocks.length) {
      return this.article.blocks;
    }
    return this.article.blocks.slice(0, this.visibleCount);
  }

  private ensureMounted(index: number): void {
    const total = this.article.blocks.length;
    if (index < 0 || index >= total || index < this.visibleCount) {
      return;
    }
    const target = Math.min(total, this.visibleCount + BLOCK_BATCH);
    this.visibleCount = target;
  }

  private extendBlocks(): void {
    const total = this.article.blocks.length;
    if (this.visibleCount >= total) {
      return;
    }
    const now = Date.now();
    if (now - this.extendAt < 300) {
      return;
    }
    this.extendByUser();
  }

  private extendByUser(): void {
    const total = this.article.blocks.length;
    if (this.visibleCount >= total) {
      return;
    }
    this.extendAt = Date.now();
    this.visibleCount = Math.min(total, this.visibleCount + BLOCK_BATCH);
  }

  private rebuildToc(): void {
    const entries: ReaderTocEntry[] = [];
    for (let i = 0; i < this.article.blocks.length; i++) {
      const block = this.article.blocks[i];
      if (block.type === ArticleBlockType.HEADING && block.text.length > 0) {
        entries.push(ReaderTocEntry.of(i, block.level, block.text));
      }
    }
    this.toc = entries;
  }

  private scheduleRestore(): void {
    this.restoring = true;
    this.positionReady = false;
    if (this.restoreTimer >= 0) {
      clearTimeout(this.restoreTimer);
    }
    this.restoreTimer = setTimeout(() => {
      this.restoreTimer = -1;
      this.restorePosition();
    }, 200);
  }

  private restorePosition(): void {
    if (this.article.blocks.length === 0) {
      this.restoring = false;
      this.positionReady = true;
      return;
    }
    let saved = 0;
    if (this.initialBlock >= 0) {
      saved = this.initialBlock;
    } else if (!this.transient) {
      saved = ReaderPrefs.readPosition(getContext(this), this.currentId());
    }
    if (saved > 0 && this.immersive) {
      const index = Math.min(saved, this.article.blocks.length - 1);
      this.ensureMounted(index);
      const offset = index < this.blockOffsets.length ? this.blockOffsets[index] : -1;
      if (!(offset > 0) && this.restoreAttempts < 10) {
        this.restoreAttempts = this.restoreAttempts + 1;
        this.restoring = false;
        this.scheduleRestore();
        return;
      }
      if (offset > 0) {
        this.blockFirst = index;
        this.progress = readerBlockProgress(index, this.article.blocks.length);
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset });
        this.positionReady = true;
      } else {
        this.positionReady = false;
      }
    } else {
      this.resetScrollOffset();
      this.positionReady = true;
    }
    this.restoreAttempts = 0;
    setTimeout(() => {
      this.restoring = false;
    }, 160);
  }

  private resetScrollOffset(): void {
    try {
      this.scroller.scrollTo({ xOffset: 0, yOffset: 0 });
    } catch (error) {
      // the scroller may not be bound yet
    }
  }

  private savePosition(): void {
    if (!this.immersive || this.article.blocks.length === 0 || this.restoring || !this.positionReady) {
      return;
    }
    if (this.blockFirst > 0 && !(this.blockOffsets[this.blockFirst] > 0)) {
      return;
    }
    this.onPositionChanged(this.blockFirst);
    if (!this.transient) {
      ReaderPrefs.writePosition(getContext(this), this.currentId(), this.blockFirst);
    }
  }

  private lastBlockBottom(): number {
    const last = this.article.blocks.length - 1;
    if (last < 0) {
      return 0;
    }
    const offset = last < this.blockOffsets.length ? this.blockOffsets[last] : 0;
    const height = last < this.blockHeights.length ? this.blockHeights[last] : 0;
    return offset + height;
  }

  private updateProgress(offset: number): void {
    if (this.measuredBlocks < this.visibleCount) {
      return;
    }
    if (this.visibleCount < this.article.blocks.length) {
      const ratio = readerBlockProgress(this.blockIndexAt(offset), this.article.blocks.length);
      if (Math.abs(ratio - this.progress) >= 0.005) {
        this.progress = ratio;
      }
      return;
    }
    const bottom = this.contentBottom > 0 ? this.contentBottom : this.lastBlockBottom();
    if (!(bottom > 0) || !(this.viewportHeight > 0)) {
      return;
    }
    const ratio = readerProgressRatio(offset, bottom, this.viewportHeight);
    if (Math.abs(ratio - this.progress) >= 0.005) {
      this.progress = ratio;
    }
    if (ratio >= 0.9 && !this.readReported) {
      this.readReported = true;
      this.onReadComplete();
    }
  }

  private scheduleProgressUpdate(): void {
    this.clearProgressTimer();
    this.progressTimer = setTimeout(() => {
      this.progressTimer = -1;
      if (!this.restoring && this.measuredBlocks === this.visibleCount) {
        this.updateProgress(this.scroller.currentOffset().yOffset);
      }
    }, 60);
  }

  private scrollToSearchMatch(index: number): void {
    if (index < 0) {
      return;
    }
    if (index >= this.visibleCount) {
      this.pendingJumpIndex = index;
      this.ensureMounted(index);
      return;
    }
    if (index < this.blockOffsets.length) {
      const offset = this.blockOffsets[index];
      if (typeof offset === 'number') {
        this.scrollToBlock(index);
        this.pendingSearchIndex = -1;
        return;
      }
    }
    this.pendingSearchIndex = index;
  }

  private onScrolled(): void {
    if (this.restoring) {
      return;
    }
    const offset = this.scroller.currentOffset().yOffset;
    if (offset > 0) {
      this.positionReady = true;
    }
    this.blockFirst = this.blockIndexAt(offset);
    this.updateProgress(offset);
  }

  private blockIndexAt(yOffset: number): number {
    let index = 0;
    for (let i = 0; i < this.blockOffsets.length; i++) {
      if (this.blockOffsets[i] <= yOffset + 8) {
        index = i;
      } else {
        break;
      }
    }
    return index;
  }

  private applyTypographyChange(mutate: () => void): void {
    let anchor = -1;
    if (this.immersive && this.article.blocks.length > 0) {
      anchor = this.blockIndexAt(this.scroller.currentOffset().yOffset);
    }
    mutate();
    if (this.immersive && anchor > 0) {
      this.clearAnchorTimer();
      this.anchorTimer = setTimeout(() => {
        this.anchorTimer = -1;
        this.scrollToBlock(anchor);
      }, 180);
    }
  }

  private toNumber(value: Length | undefined): number {
    if (value === undefined) {
      return 0;
    }
    if (typeof value === 'number') {
      return value;
    }
    if (typeof value === 'string') {
      const parsed = parseFloat(value);
      return isNaN(parsed) ? 0 : parsed;
    }
    return 0;
  }

  private scrollToBlock(index: number): void {
    if (this.article.blocks.length === 0) {
      return;
    }
    const target = Math.min(index, this.article.blocks.length - 1);
    if (target < this.blockOffsets.length) {
      const offset = this.blockOffsets[target];
      if (typeof offset === 'number') {
        this.scroller.scrollTo({ xOffset: 0, yOffset: offset, animation: true });
      }
    }
  }

  private applySearch(value: string): void {
    this.matches = [];
    this.matchCursor = -1;
    this.activeQuery = value;
    const needle = value.trim().toLowerCase();
    if (needle.length === 0) {
      return;
    }
    this.searchGeneration = this.searchGeneration + 1;
    const generation = this.searchGeneration;
    const index = this.ensureSearchIndex();
    ReaderSearchService.search(index, needle).then((hits: number[]) => {
      if (generation !== this.searchGeneration) {
        return;
      }
      this.matches = hits;
      if (this.matches.length > 0) {
        this.matchCursor = 0;
        this.scrollToSearchMatch(this.matches[0]);
      }
    });
  }

  private ensureSearchIndex(): ReaderSearchIndex {
    if (this.searchIndex !== null && this.searchSignature === this.articleSignature) {
      return this.searchIndex;
    }
    const index = ReaderSearchService.buildIndex(this.article);
    this.searchIndex = index;
    this.searchSignature = this.articleSignature;
    return index;
  }

  private releaseSearchIndex(): void {
    this.searchIndex = null;
    this.searchSignature = '';
    this.searchGeneration = this.searchGeneration + 1;
  }

  private queryChanged(value: string): void {
    this.query = value;
    if (this.searchTimer >= 0) {
      clearTimeout(this.searchTimer);
    }
    this.searchTimer = setTimeout(() => {
      this.searchTimer = -1;
      this.applySearch(this.query);
    }, 120);
  }

  private closeSearch(): void {
    this.clearSearchTimer();
    this.searching = false;
    this.query = '';
    this.activeQuery = '';
    this.matches = [];
    this.matchCursor = -1;
    this.pendingSearchIndex = -1;
    this.releaseSearchIndex();
  }

  private nextMatch(delta: number): void {
    if (this.matches.length === 0) {
      return;
    }
    let next = this.matchCursor + delta;
    if (next < 0) {
      next = this.matches.length - 1;
    }
    if (next >= this.matches.length) {
      next = 0;
    }
    this.matchCursor = next;
    this.scrollToSearchMatch(this.matches[next]);
  }

  private segmentsOf(block: ArticleBlock): ReaderSegment[] {
    return readerSegments(block.text, block.links, this.activeQuery);
  }

  private async copySelection(): Promise<void> {
    if (this.selectedText.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, this.selectedText);
      await pasteboard.getSystemPasteboard().setData(data);
      this.selectionController.clearTextSelection();
      AppState.shared.toast('已复制');
    } catch (error) {
      AppState.shared.toast('复制失败');
    }
  }

  private async saveExcerpt(text: string): Promise<void> {
    const selected = text.trim();
    if (selected.length === 0) {
      return;
    }
    try {
      const next = await FlowRepository.get().appendExcerpt(this.currentId(), selected);
      if (next.length === 0) {
        AppState.shared.toast('摘录没有存下');
        return;
      }
      this.selectionController.clearTextSelection();
      AppState.shared.toast('已存为摘录');
      this.onExcerptSaved(next);
    } catch (error) {
      AppState.shared.toast('摘录没有存下');
    }
  }

  private readLabel(): string {
    if (this.bookmark.readState === ReadState.READ) {
      return '已读';
    }
    if (this.bookmark.readState === ReadState.READING) {
      return '阅读中';
    }
    return '未读';
  }

  private headingSize(level: number): number {
    if (level <= 1) {
      return 26;
    }
    if (level === 2) {
      return 22;
    }
    if (level === 3) {
      return 19;
    }
    return 17;
  }

  private headingLine(level: number): number {
    return Math.round(this.headingSize(level) * 1.35);
  }

  build() {
    if (this.immersive) {
      this.ImmersiveRoot()
    } else {
      this.InlineRoot()
    }
  }

  @Builder
  ImmersiveRoot() {
    Stack({ alignContent: Alignment.TopStart }) {
      Column() {
        this.Toolbar()
        if (this.searching) {
          this.SearchBar()
        }
        if (this.showSettings) {
          this.SettingsPanel()
        }
        this.ProgressLine()
        if (this.loading) {
          Column() {
            Text('正在翻出正文…')
              .fontSize(14)
              .fontColor($r('app.color.ink_tertiary'))
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else if (this.article.blocks.length === 0) {
          Column() {
            this.EmptyBody()
          }
          .width('100%')
          .layoutWeight(1)
          .justifyContent(FlexAlign.Center)
        } else {
          Column() {
            Scroll(this.scroller) {
              SelectionContainer({ controller: this.selectionController }) {
                Column() {
                  this.ArticleHeaderItem()
                  ForEach(this.shownBlocks(), (block: ArticleBlock, index: number) => {
                    this.BlockItem(block, index)
                  }, (block: ArticleBlock, index: number) => {
                    return `${index}:${block.type}:${block.level}:${block.text.length}:${block.text.slice(0, 24)}`;
                  })
                  if (this.visibleCount < this.article.blocks.length) {
                    this.LoadMoreItem()
                  }
                  this.ArticleFooterItem()
                }
                .width('100%')
                .alignItems(HorizontalAlign.Start)
              }
              .copyOption(CopyOptions.LocalDevice)
              .textJoinStyle(SelectionContainerTextJoinStyle.NEWLINE)
              .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenu, TextResponseType.LONG_PRESS)
              .onTextSelectionChange((value: Array<string>) => {
                this.selectedText = value.join('\n');
              })
              .width('100%')
            }
            .width('100%')
            .height('100%')
            .scrollBar(BarState.Off)
            .edgeEffect(EdgeEffect.None)
            .onAreaChange((oldArea: Area, newArea: Area) => {
              this.viewportHeight = this.toNumber(newArea.height);
            })
            .onScroll((xOffset: number, yOffset: number) => {
              this.onScrolled();
            })
            .onScrollStop(() => {
              this.savePosition();
            })
            .onScrollEdge((side: Edge) => {
              if (side !== Edge.Bottom) {
                return;
              }
              const wasFull = this.visibleCount >= this.article.blocks.length;
              this.extendBlocks();
              if (wasFull && !this.readReported) {
                this.progress = 1;
                this.readReported = true;
                this.onReadComplete();
              }
            })
          }
          .width('100%')
          .layoutWeight(1)
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.paper'))
      .onKeyEvent((event: KeyEvent) => {
        if (!this.externalChrome && event.type === KeyType.Down &&
          event.keyCode === KeyCode.KEYCODE_ESCAPE) {
          this.onClose();
        }
      })

      if (this.showToc) {
        this.TocOverlay()
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  @Builder
  InlineRoot() {
    Column() {
      this.Toolbar()
      if (this.showSettings) {
        this.SettingsPanel()
      }
      if (this.loading) {
        Text('正在翻出正文…')
          .fontSize(14)
          .fontColor($r('app.color.ink_tertiary'))
          .padding({ top: 12, bottom: 12 })
      } else if (this.article.blocks.length === 0) {
        this.EmptyBody()
      } else {
        SelectionContainer({ controller: this.selectionController }) {
          Column() {
            ForEach(this.shownBlocks(), (block: ArticleBlock, index: number) => {
              this.BlockView(block, index)
            }, (block: ArticleBlock, index: number) => {
              return `${index}:${block.type}:${block.level}:${block.text.length}:${block.text.slice(0, 24)}`;
            })
            if (this.visibleCount < this.article.blocks.length) {
              this.LoadMoreItem()
            }
          }
          .width('100%')
          .alignItems(HorizontalAlign.Start)
        }
        .copyOption(CopyOptions.LocalDevice)
        .textJoinStyle(SelectionContainerTextJoinStyle.NEWLINE)
        .bindSelectionMenu(TextSpanType.TEXT, this.SelectionMenu, TextResponseType.LONG_PRESS)
        .onTextSelectionChange((value: Array<string>) => {
          this.selectedText = value.join('\n');
        })
        .width('100%')
      }
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
  }

  @Builder
  Toolbar() {
    Row({ space: 2 }) {
      if (this.immersive && !this.externalChrome) {
        this.ToolButton('关闭', () => this.onClose())
      }
      Blank()
      if (this.immersive && this.article.blocks.length > 0) {
        this.ToolButton('搜索', () => {
          this.searching = !this.searching;
          if (!this.searching) {
            this.closeSearch();
          }
        })
        if (this.toc.length > 0) {
          this.ToolButton('目录', () => {
            this.showToc = true;
          })
        }
      }
      this.ToolButton('字号', () => {
        this.showSettings = !this.showSettings;
      })
      if (this.immersive) {
        Text(`${Math.round(this.progress * 100)}%`)
          .fontSize(11)
          .fontColor($r('app.color.ink_tertiary'))
          .padding({ left: 8, right: 4 })
      } else if (this.article.blocks.length > 0) {
        Text('专注阅读')
          .fontSize(13)
          .fontColor($r('app.color.inverse_ink'))
          .backgroundColor($r('app.color.ink'))
          .borderRadius(4)
          .height(32)
          .padding({ left: 12, right: 12 })
          .margin({ left: 6 })
          .accessibilityText('进入专注阅读模式')
          .focusable(true)
          .onClick(() => this.onOpenImmersive())
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              this.onOpenImmersive();
            }
          })
      }
    }
    .width('100%')
    .height(48)
    .padding({ left: this.compact ? 10 : 20, right: this.compact ? 10 : 20 })
  }

  @Builder
  ToolButton(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.ink_secondary'))
      .height(44)
      .padding({ left: 10, right: 10 })
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
  ProgressLine() {
    Stack({ alignContent: Alignment.Start }) {
      Row()
        .width('100%')
        .height(2)
        .backgroundColor($r('app.color.line'))
      Row()
        .width(`${Math.round(this.progress * 100)}%`)
        .height(2)
        .backgroundColor($r('app.color.ink'))
    }
    .width('100%')
    .height(2)
  }

  @Builder
  SearchBar() {
    Row({ space: 4 }) {
      TextInput({ text: this.query, placeholder: '在正文中搜索' })
        .fontSize(14)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(6)
        .height(44)
        .layoutWeight(1)
        .onChange((value: string) => {
          this.queryChanged(value);
        })
      Text(this.matches.length === 0 ? '无结果' : `${this.matchCursor + 1}/${this.matches.length}`)
        .fontSize(11)
        .fontColor($r('app.color.ink_tertiary'))
        .padding({ left: 4, right: 4 })
      this.ToolButton('上一处', () => this.nextMatch(-1))
      this.ToolButton('下一处', () => this.nextMatch(1))
      this.ToolButton('关闭', () => this.closeSearch())
    }
    .width('100%')
    .padding({ left: this.compact ? 10 : 20, right: this.compact ? 10 : 20, bottom: 6 })
  }

  @Builder
  SettingsPanel() {
    Column({ space: 6 }) {
      Row() {
        Text('字号')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
        Blank()
        this.ToolButton('A−', () => {
          this.applyTypographyChange(() => this.settings.setSize(getContext(this), this.settings.size - 1));
        })
        Text(`${this.settings.size}`)
          .fontSize(13)
          .fontColor($r('app.color.ink'))
          .width(36)
          .textAlign(TextAlign.Center)
        this.ToolButton('A+', () => {
          this.applyTypographyChange(() => this.settings.setSize(getContext(this), this.settings.size + 1));
        })
      }
      .width('100%')

      Row() {
        Text('行距')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
        Blank()
        this.SettingOption('紧凑', this.settings.lineIndex === 0, () => {
          this.applyTypographyChange(() => this.settings.setLine(getContext(this), 0));
        })
        this.SettingOption('标准', this.settings.lineIndex === 1, () => {
          this.applyTypographyChange(() => this.settings.setLine(getContext(this), 1));
        })
        this.SettingOption('宽松', this.settings.lineIndex === 2, () => {
          this.applyTypographyChange(() => this.settings.setLine(getContext(this), 2));
        })
      }
      .width('100%')

      Row() {
        Text('段距')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
        Blank()
        this.SettingOption('小', this.settings.paraIndex === 0, () => {
          this.applyTypographyChange(() => this.settings.setPara(getContext(this), 0));
        })
        this.SettingOption('中', this.settings.paraIndex === 1, () => {
          this.applyTypographyChange(() => this.settings.setPara(getContext(this), 1));
        })
        this.SettingOption('大', this.settings.paraIndex === 2, () => {
          this.applyTypographyChange(() => this.settings.setPara(getContext(this), 2));
        })
      }
      .width('100%')

      Row() {
        Blank()
        this.ToolButton('完成', () => {
          this.showSettings = false;
        })
      }
      .width('100%')
    }
    .width('100%')
    .padding({ left: this.compact ? 12 : 24, right: this.compact ? 12 : 24, top: 8, bottom: 4 })
    .backgroundColor($r('app.color.surface_alt'))
    .border({ width: { bottom: 1 }, color: $r('app.color.line') })
  }

  @Builder
  SettingOption(label: string, selected: boolean, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor(selected ? $r('app.color.ink') : $r('app.color.ink_tertiary'))
      .fontWeight(selected ? FontWeight.Medium : FontWeight.Normal)
      .height(44)
      .padding({ left: 10, right: 10 })
      .border({
        width: { bottom: selected ? 1 : 0 },
        color: $r('app.color.ink')
      })
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
  TocOverlay() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .onClick(() => {
          this.showToc = false;
        })
      Row() {
        Column() {
          Row() {
            Text('目录')
              .fontSize(17)
              .fontWeight(FontWeight.Medium)
              .fontColor($r('app.color.ink'))
            Blank()
            this.ToolButton('关闭', () => {
              this.showToc = false;
            })
          }
          .width('100%')
          .height(48)
          List() {
            ForEach(this.toc, (entry: ReaderTocEntry) => {
              ListItem() {
                Text(entry.text)
                  .fontSize(entry.level <= 1 ? 15 : 13)
                  .fontWeight(entry.level <= 1 ? FontWeight.Medium : FontWeight.Normal)
                  .fontColor($r('app.color.ink_secondary'))
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                  .width('100%')
                  .height(44)
                  .padding({ left: 8 + Math.max(0, entry.level - 1) * 14, right: 8 })
                  .onClick(() => {
                    this.showToc = false;
                    this.scrollToSearchMatch(entry.index);
                  })
              }
            }, (entry: ReaderTocEntry) => `${entry.index}:${entry.level}:${entry.text.length}`)
          }
          .width('100%')
          .layoutWeight(1)
          .scrollBar(BarState.Off)
        }
        .width('100%')
        .height('100%')
        .constraintSize({ maxWidth: 560 })
        .backgroundColor($r('app.color.surface'))
        .borderRadius({ topLeft: 16, topRight: 16 })
        .padding({ left: 12, right: 12, bottom: 16 })
        .onClick(() => {})
      }
      .width('100%')
      .height('55%')
      .justifyContent(FlexAlign.Center)
    }
    .width('100%')
    .height('100%')
  }

  @Builder
  ArticleHeaderItem() {
    Row() {
      Column() {
        Text(this.bookmark.title.length > 0 ? this.bookmark.title : this.bookmark.url)
          .fontSize(this.compact ? 26 : 30)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
          .lineHeight(this.compact ? 35 : 40)
          .maxLines(4)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')
          .accessibilityText(this.bookmark.title)
        Row({ space: 8 }) {
          Text(domainOf(this.bookmark.url))
            .fontSize(12)
            .fontColor($r('app.color.ink_secondary'))
          Text('·')
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
          if (this.transient) {
            Text('临时阅读')
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
          } else {
            Text(formatFullDate(this.bookmark.createdAt))
              .fontSize(12)
              .fontColor($r('app.color.ink_tertiary'))
            Text(this.readLabel())
              .fontSize(12)
              .fontColor($r('app.color.ink_secondary'))
          }
        }
        .margin({ top: 10 })
        if (!this.transient && this.bookmark.tags.length > 0) {
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
          .margin({ top: 20, bottom: 20 })
      }
      .width('100%')
      .constraintSize({ maxWidth: 680 })
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.compact ? 20 : 40, right: this.compact ? 20 : 40, top: 12 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
  }

  @Builder
  LoadMoreItem() {
    Row() {
      Text(`继续阅读 · ${this.visibleCount}/${this.article.blocks.length}`)
        .fontSize(13)
        .fontColor($r('app.color.ink_secondary'))
        .border({ width: 1, color: $r('app.color.line_strong') })
        .borderRadius(6)
        .height(44)
        .padding({ left: 14, right: 14 })
        .accessibilityText('继续阅读更多正文')
        .focusable(true)
        .onClick(() => {
          this.extendByUser();
        })
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
            this.extendByUser();
          }
        })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .padding({ top: 20, bottom: 8 })
  }

  @Builder
  ArticleFooterItem() {
    Row() {
      Column({ space: 6 }) {
        Divider()
          .strokeWidth(1)
          .color($r('app.color.line'))
        if (this.transient) {
          Text('阅读中的网页')
            .fontSize(11)
            .fontColor($r('app.color.ink_tertiary'))
          Text('关闭后不会保存到书笺')
            .fontSize(11)
            .fontColor($r('app.color.ink_tertiary'))
          Text(this.savedOnce ? '已收藏' : '收藏这一页')
            .fontSize(12)
            .fontColor(this.savedOnce ? $r('app.color.ink_tertiary') : $r('app.color.ink'))
            .height(44)
            .padding({ right: 12 })
            .accessibilityText(this.savedOnce ? '已收藏这一页' : '收藏这一页')
            .focusable(!this.savedOnce)
            .onClick(() => {
              if (!this.savedOnce) {
                this.onSavePage();
              }
            })
            .onKeyEvent((event: KeyEvent) => {
              if (!this.savedOnce && event.type === KeyType.Down &&
                (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
                this.onSavePage();
              }
            })
        } else {
          Text(`收于 ${formatFullDate(this.bookmark.createdAt)}`)
            .fontSize(11)
            .fontColor($r('app.color.ink_tertiary'))
          Text(this.article.blocks.length > 0 ? '已存下正文' : '正文待补全')
            .fontSize(11)
            .fontColor($r('app.color.ink_tertiary'))
        }
      }
      .width('100%')
      .constraintSize({ maxWidth: 680 })
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.compact ? 20 : 40, right: this.compact ? 20 : 40, top: 24, bottom: 48 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      this.contentBottom = this.toNumber(newArea.position.y) + this.toNumber(newArea.height);
    })
  }

  @Builder
  BlockItem(block: ArticleBlock, index: number) {
    Row() {
      Column() {
        this.BlockView(block, index)
      }
      .width('100%')
      .constraintSize({ maxWidth: 680 })
      .alignItems(HorizontalAlign.Start)
      .padding({ left: this.compact ? 20 : 40, right: this.compact ? 20 : 40 })
    }
    .width('100%')
    .justifyContent(FlexAlign.Center)
    .onAreaChange((oldArea: Area, newArea: Area) => {
      const previous = index < this.blockHeights.length ? this.blockHeights[index] : 0;
      this.blockOffsets[index] = this.toNumber(newArea.position.y);
      this.blockHeights[index] = this.toNumber(newArea.height);
      if (!(previous > 0) && this.blockHeights[index] > 0) {
        this.measuredBlocks = this.measuredBlocks + 1;
      }
      if (!this.restoring && this.measuredBlocks === this.visibleCount) {
        this.scheduleProgressUpdate();
      }
      if (this.pendingJumpIndex >= 0) {
        const jumpTarget = this.pendingJumpIndex;
        if (jumpTarget >= this.visibleCount) {
          this.ensureMounted(jumpTarget);
        } else if (jumpTarget < this.blockOffsets.length && this.blockOffsets[jumpTarget] > 0) {
          this.pendingJumpIndex = -1;
          this.scrollToBlock(jumpTarget);
        }
      }
      if (this.pendingSearchIndex >= 0 && this.pendingSearchIndex < this.blockOffsets.length) {
        const pendingOffset = this.blockOffsets[this.pendingSearchIndex];
        if (typeof pendingOffset === 'number') {
          this.scrollToBlock(this.pendingSearchIndex);
          this.pendingSearchIndex = -1;
        }
      }
    })
  }

  @Builder
  BlockView(block: ArticleBlock, index: number) {
    if (block.type === ArticleBlockType.HEADING) {
      this.HeadingBlock(block, index)
    } else if (block.type === ArticleBlockType.QUOTE) {
      this.QuoteBlock(block, index)
    } else if (block.type === ArticleBlockType.LIST_ITEM) {
      this.ListBlock(block, index)
    } else if (block.type === ArticleBlockType.CODE) {
      this.CodeBlock(block, index)
    } else {
      this.ParagraphBlock(block, index)
    }
  }

  @Builder
  ParagraphBlock(block: ArticleBlock, index: number) {
    Column() {
      this.StyledText(block, this.settings.size, this.settings.lineHeight(), $r('app.color.ink'), FontWeight.Normal)
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: index === 0 ? 0 : this.settings.paragraphSpacing(), bottom: 4 })
  }

  @Builder
  HeadingBlock(block: ArticleBlock, index: number) {
    Column() {
      this.StyledText(
        block,
        this.headingSize(block.level),
        this.headingLine(block.level),
        $r('app.color.ink'),
        block.level <= 2 ? FontWeight.Bold : FontWeight.Medium
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .margin({ top: index === 0 ? 0 : 24, bottom: 6 })
  }

  @Builder
  QuoteBlock(block: ArticleBlock, index: number) {
    Row() {
      this.StyledText(block, this.settings.size, this.settings.lineHeight(), $r('app.color.ink_secondary'), FontWeight.Normal)
    }
    .width('100%')
    .padding({ left: 12 })
    .border({ width: { left: 2 }, color: $r('app.color.line_strong') })
    .margin({ top: index === 0 ? 0 : this.settings.paragraphSpacing(), bottom: 4 })
  }

  @Builder
  ListBlock(block: ArticleBlock, index: number) {
    Row() {
      Text('•')
        .fontSize(this.settings.size)
        .fontColor($r('app.color.ink_tertiary'))
        .width(16)
      Column() {
        this.StyledText(block, this.settings.size, this.settings.lineHeight(), $r('app.color.ink'), FontWeight.Normal)
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
    }
    .width('100%')
    .alignItems(VerticalAlign.Top)
    .margin({ top: index === 0 ? 0 : 6, bottom: 4 })
  }

  @Builder
  CodeBlock(block: ArticleBlock, index: number) {
    Column() {
      this.StyledText(
        block,
        this.settings.size - 1,
        this.settings.lineHeight() - 2,
        $r('app.color.ink'),
        FontWeight.Normal
      )
    }
    .width('100%')
    .alignItems(HorizontalAlign.Start)
    .padding(12)
    .backgroundColor($r('app.color.surface_alt'))
    .borderRadius(6)
    .margin({ top: index === 0 ? 0 : this.settings.paragraphSpacing(), bottom: 8 })
  }

  @Builder
  StyledText(block: ArticleBlock, size: number, line: number, color: ResourceColor, weight: FontWeight) {
    if (block.links.length > 0 || this.activeQuery.trim().length > 0) {
      Text() {
        ForEach(this.segmentsOf(block), (segment: ReaderSegment, index: number) => {
          if (segment.url.length > 0) {
            Span(segment.text)
              .fontSize(size)
              .fontColor(color)
              .fontWeight(weight)
              .decoration({ type: TextDecorationType.Underline, color: $r('app.color.ink_tertiary') })
              .textBackgroundStyle({
                color: segment.matched ? $r('app.color.highlight') : Color.Transparent
              })
              .onClick(() => {
                this.onOpenLink(segment.url);
              })
          } else if (segment.matched) {
            Span(segment.text)
              .fontSize(size)
              .fontColor(color)
              .fontWeight(weight)
              .textBackgroundStyle({ color: $r('app.color.highlight') })
          } else {
            Span(segment.text)
              .fontSize(size)
              .fontColor(color)
              .fontWeight(weight)
          }
        }, (segment: ReaderSegment, index: number) => {
          return `${index}:${segment.matched ? 1 : 0}:${segment.url.length}:${segment.text.length}`;
        })
      }
      .fontSize(size)
      .lineHeight(line)
      .fontColor(color)
      .fontWeight(weight)
      .width('100%')
      .textAlign(TextAlign.Start)
    } else {
      Text(block.text)
        .fontSize(size)
        .lineHeight(line)
        .fontColor(color)
        .fontWeight(weight)
        .width('100%')
        .textAlign(TextAlign.Start)
    }
  }

  @Builder
  SelectionMenu() {
    Menu() {
      MenuItem({ content: '复制' })
        .onClick(() => {
          this.copySelection().catch(() => {});
        })
      if (!this.transient) {
        MenuItem({ content: '存为摘录' })
          .onClick(() => {
            this.saveExcerpt(this.selectedText).catch(() => {});
          })
      }
    }
  }

  @Builder
  EmptyBody() {
    Column({ space: 12 }) {
      if (this.transient) {
        Text('没能翻出这一页的正文。')
          .fontSize(15)
          .fontColor($r('app.color.ink_secondary'))
        Text('可以试试在浏览器里看。')
          .fontSize(13)
          .fontColor($r('app.color.ink_tertiary'))
        Row({ space: 12 }) {
          this.TransientAction(this.loading ? '正在抓取…' : '重试', () => {
            if (!this.loading) {
              this.onRetry();
            }
          })
          this.TransientAction('在浏览器打开', () => this.onOpenBrowser())
        }
      } else {
        Text(this.bookmark.snapshotStatus === SnapshotStatus.OFF ? '自动快照已关闭。' : '这条还没存下正文。')
          .fontSize(15)
          .fontColor($r('app.color.ink_secondary'))
        if (this.bookmark.snapshotStatus === SnapshotStatus.OFF) {
          Text('可以在「设置 → 自动保存正文快照」中重新开启。')
            .fontSize(13)
            .fontColor($r('app.color.ink_tertiary'))
        } else {
          this.TransientAction(this.loading ? '正在抓取…' : '重试抓取', () => {
            if (!this.loading) {
              this.onRetry();
            }
          })
        }
      }
    }
    .alignItems(HorizontalAlign.Start)
    .padding({ top: 12, bottom: 12 })
  }

  @Builder
  TransientAction(label: string, action: () => void) {
    Text(label)
      .fontSize(13)
      .fontColor($r('app.color.ink'))
      .border({ width: 1, color: $r('app.color.line_strong') })
      .borderRadius(6)
      .height(44)
      .padding({ left: 12, right: 12 })
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
}
