import { Want } from '@kit.AbilityKit';
import { KeyCode } from '@kit.InputKit';
import { pasteboard } from '@kit.BasicServicesKit';
import { WebNetErrorList, webview } from '@kit.ArkWeb';
import { AppState } from '../common/AppState';
import { BookmarkSource, ReadState } from '../common/Constants';
import { domainOf, isSameUrl, normalizeUrl } from '../common/UrlUtil';
import { decodeWebHtml } from '../common/WebHtmlCodec';
import { ArticleExtractService } from '../core/service/ArticleExtractService';
import { ArticleCodec } from '../core/service/ArticleCodec';
import { ArticleDocument } from '../model/Article';
import { ReaderPageLoader } from '../core/service/ReaderPageLoader';
import { Bookmark } from '../model/Bookmark';
import { MetadataApplyResult } from '../model/MetadataResult';
import { ReadingEntry, ReadingMode } from '../model/ReadingEntry';
import { FlowRepository } from '../repository/FlowRepository';
import { ReaderView } from './ReaderView';

const MAX_STACK: number = 20;
const MAX_WEB_HTML: number = 1500000;
const DOCUMENT_START_SCRIPT: string =
  `(function(){try{window.open=function(){return null;};}catch(e){}` +
  `document.addEventListener('click',function(e){var t=e.target;` +
  `while(t&&t.tagName!=='A'){t=t.parentElement;}` +
  `if(t&&t.getAttribute('target')){t.removeAttribute('target');}},true);` +
  `})();`;

function documentStartScripts(): ScriptItem[] {
  const item: ScriptItem = { script: DOCUMENT_START_SCRIPT, scriptRules: ['*'] };
  return [item];
}

@ComponentV2
export struct ReadingShell {
  @Param compact: boolean = false;
  @Event onClose: () => void = () => {};

  @Local appState: AppState = AppState.shared;
  @Local entries: ReadingEntry[] = [];
  @Local index: number = 0;
  @Local mode: number = ReadingMode.READER;
  @Local browserSrc: string = '';
  @Local browserError: string = '';
  @Local browserProgress: number = 0;
  @Local webTitle: string = '';
  @Local webMounted: boolean = false;
  @Local browserActive: boolean = false;
  @Local addressEditing: boolean = false;
  @Local addressDraft: string = '';
  private webController: webview.WebviewController = new webview.WebviewController();
  private pendingUrl: string = '';
  private disposed: boolean = false;
  private compactTimer: number = -1;
  private extracting: boolean = false;

  aboutToAppear(): void {
    this.applySeed();
  }

  aboutToDisappear(): void {
    this.disposed = true;
    this.browserActive = false;
    this.webMounted = false;
    this.appState.readingCanGoBack = false;
    if (this.compactTimer >= 0) {
      clearTimeout(this.compactTimer);
      this.compactTimer = -1;
    }
  }

  @Monitor('appState.readingTick')
  onSeedChanged(): void {
    if (!this.disposed) {
      this.applySeed();
    }
  }

  @Monitor('appState.readingBackTick')
  onBackRequested(): void {
    if (!this.disposed) {
      this.back();
    }
  }
  private applySeed(): void {
    const seed = this.appState.readingSeed;
    const entry = new ReadingEntry();
    entry.url = seed.url;
    entry.title = seed.title.length > 0 ? seed.title : domainOf(seed.url);
    entry.article = seed.article;
    entry.articleUrl = seed.article.blocks.length > 0 ? seed.url : '';
    entry.mode = seed.mode;
    entry.transient = seed.transient;
    entry.position = -1;
    entry.savedOnce = false;
    entry.loading = false;
    entry.error = '';
    if (seed.bookmarkId.length > 0) {
      entry.bookmark = seed.bookmark;
      entry.bookmarkId = seed.bookmarkId;
    } else {
      entry.bookmark = this.syntheticBookmark(seed.url, entry.title);
      entry.bookmarkId = entry.bookmark.id;
    }
    this.entries = [entry];
    this.index = 0;
    this.browserError = '';
    this.browserProgress = 0;
    this.webTitle = entry.title;
    this.addressEditing = false;
    this.pendingUrl = '';
    this.webMounted = false;
    if (entry.mode === ReadingMode.BROWSER) {
      this.browserSrc = entry.url;
      this.browserActive = true;
    } else if (seed.autoLoad && !ReaderPageLoader.isLikelyDocument(seed.url)) {
      entry.mode = ReadingMode.BROWSER;
      this.browserSrc = entry.url;
      this.browserActive = true;
    } else {
      this.browserSrc = '';
      this.browserActive = false;
      if (entry.article.blocks.length === 0 && seed.autoLoad) {
        this.loadEntry(entry).catch(() => {});
      }
    }
    this.syncBackState();
  }

  private syntheticBookmark(target: string, title: string): Bookmark {
    const bookmark = Bookmark.create(target, title, BookmarkSource.BROWSER);
    bookmark.url = target;
    bookmark.title = title;
    bookmark.siteName = domainOf(target);
    bookmark.rebuildSearch();
    return bookmark;
  }

  private currentEntry(): ReadingEntry {
    if (this.entries.length === 0) {
      return new ReadingEntry();
    }
    const safe = Math.max(0, Math.min(this.index, this.entries.length - 1));
    return this.entries[safe];
  }

  private isBrowserMode(): boolean {
    return this.mode === ReadingMode.BROWSER;
  }

  private pageTitle(): string {
    const entry = this.currentEntry();
    if (entry.title.length > 0) {
      return entry.title;
    }
    const domain = domainOf(entry.url);
    return domain.length > 0 ? domain : '阅读';
  }

  private subtitle(): string {
    const entry = this.currentEntry();
    const domain = domainOf(entry.url);
    if (entry.transient) {
      return domain.length > 0 ? `${domain} · 临时阅读` : '临时阅读';
    }
    return domain;
  }

  private syncBackState(): void {
    this.mode = this.currentEntry().mode;
    this.appState.readingCanGoBack = this.index > 0 || this.mode === ReadingMode.BROWSER;
  }

  private pushEntry(entry: ReadingEntry): boolean {
    if (this.entries.length >= MAX_STACK) {
      AppState.shared.toast(`最多同时打开 ${MAX_STACK} 层，先返回一层再继续`);
      return false;
    }
    this.entries.push(entry);
    this.entries = this.entries.slice(0);
    this.index = this.entries.length - 1;
    this.syncBackState();
    this.scheduleCompactIdle();
    return true;
  }

  // Non-current layers keep only an encoded article until visited again; the
  // encode itself waits for an idle gap so it never lands on the push path.
  private scheduleCompactIdle(): void {
    if (this.compactTimer >= 0) {
      clearTimeout(this.compactTimer);
    }
    this.compactTimer = setTimeout(() => {
      this.compactTimer = -1;
      this.compactNonCurrent();
    }, 600);
  }

  private compactNonCurrent(): void {
    if (this.disposed) {
      return;
    }
    for (let i = 0; i < this.entries.length; i++) {
      if (i === this.index) {
        continue;
      }
      const entry = this.entries[i];
      if (entry.compact.length > 0 || entry.article.blocks.length === 0 || entry.loading) {
        continue;
      }
      entry.compact = ArticleCodec.encode(entry.article);
      entry.article = new ArticleDocument();
    }
  }

  private expandCompacted(entry: ReadingEntry): void {
    if (entry.compact.length === 0) {
      return;
    }
    // retryCurrent() writes the article back after loading goes false; if a
    // compact landed in that gap the live article is fresher than the copy.
    if (entry.article.blocks.length > 0) {
      entry.compact = '';
      return;
    }
    entry.article = ArticleCodec.decode(entry.compact);
    entry.compact = '';
  }

  private createTransientEntry(target: string, mode: number): ReadingEntry {
    const entry = new ReadingEntry();
    entry.url = target;
    entry.title = domainOf(target);
    entry.mode = mode;
    entry.transient = true;
    entry.position = -1;
    entry.articleUrl = '';
    entry.bookmark = this.syntheticBookmark(target, entry.title);
    entry.bookmarkId = entry.bookmark.id;
    return entry;
  }

  private async loadEntry(entry: ReadingEntry): Promise<void> {
    if (entry.loading) {
      return;
    }
    entry.loading = true;
    entry.error = '';
    const result = await ReaderPageLoader.load(entry.url);
    entry.loading = false;
    if (this.disposed) {
      return;
    }
    if (result.success) {
      entry.article = result.article;
      entry.articleUrl = entry.url;
      if (result.title.length > 0) {
        entry.title = result.title;
        entry.bookmark.title = result.title;
      }
    } else {
      entry.error = result.error;
    }
  }

  private async retryCurrent(): Promise<void> {
    const entry = this.currentEntry();
    if (entry.transient) {
      await this.loadEntry(entry);
      return;
    }
    if (entry.bookmarkId.length === 0) {
      await this.loadEntry(entry);
      return;
    }
    entry.loading = true;
    const outcome = await FlowRepository.get().applyMetadata(entry.bookmarkId);
    entry.loading = false;
    if (outcome === MetadataApplyResult.FAILED) {
      AppState.shared.toast('抓取失败，请检查网络后重试');
      return;
    }
    const found = await FlowRepository.get().get(entry.bookmarkId);
    if (found === undefined) {
      AppState.shared.toast('这一笺没有找到');
      return;
    }
    entry.bookmark = found;
    entry.title = found.title;
    entry.article = await FlowRepository.get().loadArticle(found);
    entry.articleUrl = found.url;
    if (entry.article.blocks.length === 0) {
      AppState.shared.toast('没有提取到正文');
    }
  }

  private pushReaderLink(target: string): void {
    const normalized = normalizeUrl(target);
    if (normalized.length === 0) {
      AppState.shared.toast('这个链接打不开');
      return;
    }
    if (isSameUrl(normalized, this.currentEntry().url)) {
      AppState.shared.toast('已经在这一页了');
      return;
    }
    if (!ReaderPageLoader.isLikelyDocument(normalized)) {
      const entry = this.createTransientEntry(normalized, ReadingMode.BROWSER);
      if (!this.pushEntry(entry)) {
        return;
      }
      this.browserSrc = normalized;
      this.browserActive = true;
      this.webMounted = false;
      this.browserError = '';
      this.browserProgress = 0;
      this.webTitle = entry.title;
      return;
    }
    const entry = this.createTransientEntry(normalized, ReadingMode.READER);
    if (this.pushEntry(entry)) {
      this.loadEntry(entry).catch(() => {});
    }
  }

  private switchToBrowser(): void {
    const entry = this.currentEntry();
    if (entry.url.length === 0) {
      AppState.shared.toast('没有可以打开的地址');
      return;
    }
    entry.mode = ReadingMode.BROWSER;
    this.browserSrc = entry.url;
    this.browserError = '';
    this.browserProgress = 0;
    this.webTitle = entry.title;
    this.browserActive = true;
    this.webMounted = false;
    this.pendingUrl = '';
    this.syncBackState();
  }

  private switchToReader(): void {
    const entry = this.currentEntry();
    if (entry.article.blocks.length > 0 && isSameUrl(entry.url, entry.articleUrl)) {
      entry.mode = ReadingMode.READER;
      this.browserActive = false;
      this.webMounted = false;
      this.syncBackState();
      return;
    }
    this.extractFromWeb().catch(() => {});
  }

  private async extractFromWeb(): Promise<void> {
    if (this.extracting) {
      return;
    }
    if (!this.webMounted) {
      AppState.shared.toast('网页还没有准备好');
      return;
    }
    this.extracting = true;
    try {
      const entry = this.currentEntry();
      let html = '';
      try {
        const message = await this.webController.runJavaScriptExt(
          'document.body ? document.body.innerHTML : document.documentElement.outerHTML'
        );
        if (message.getType() === webview.JsMessageType.STRING) {
          html = message.getString();
        }
      } catch (error) {
        html = '';
      }
      html = decodeWebHtml(html);
      if (this.disposed) {
        return;
      }
      if (html.length === 0 || html.length > MAX_WEB_HTML) {
        AppState.shared.toast('这个页面没翻出正文，先看网页吧');
        return;
      }
      let baseUrl = entry.url;
      try {
        const live = this.webController.getUrl();
        if (live.length > 0) {
          baseUrl = live;
        }
      } catch (error) {
        baseUrl = entry.url;
      }
      const article = await ArticleExtractService.extractAsync(html, entry.title, baseUrl);
      if (this.disposed) {
        return;
      }
      if (article.blocks.length === 0) {
        AppState.shared.toast('这个页面没翻出正文，先看网页吧');
        return;
      }
      const liveEntry = this.createTransientEntry(baseUrl, ReadingMode.READER);
      liveEntry.title = entry.title;
      liveEntry.bookmark.title = entry.title;
      liveEntry.article = article;
      liveEntry.articleUrl = baseUrl;
      if (!this.pushEntry(liveEntry)) {
        return;
      }
      this.browserActive = false;
      this.webMounted = false;
    } finally {
      this.extracting = false;
    }
  }

  private back(): void {
    const entry = this.currentEntry();
    if (entry.mode === ReadingMode.BROWSER) {
      if (this.webMounted && this.browserActive) {
        let canGoBack = false;
        try {
          canGoBack = this.webController.accessBackward();
        } catch (error) {
          canGoBack = false;
        }
        if (canGoBack) {
          try {
            this.webController.backward();
          } catch (error) {
            AppState.shared.toast('返回失败');
          }
          return;
        }
      }
      if (entry.article.blocks.length > 0 && isSameUrl(entry.url, entry.articleUrl)) {
        entry.mode = ReadingMode.READER;
        this.browserActive = false;
        this.webMounted = false;
        this.syncBackState();
        return;
      }
    }
    if (this.index > 0) {
      const wasMounted = this.webMounted && this.browserActive;
      this.index = this.index - 1;
      // popped layers have no forward path; drop them for immediate GC
      this.entries = this.entries.slice(0, this.index + 1);
      this.prepareCurrentAfterPop(wasMounted);
      return;
    }
    this.close();
  }

  private prepareCurrentAfterPop(wasMounted: boolean): void {
    const entry = this.currentEntry();
    this.expandCompacted(entry);
    this.browserError = '';
    this.browserProgress = 0;
    this.webTitle = entry.title;
    if (entry.mode === ReadingMode.BROWSER) {
      this.browserActive = true;
      if (wasMounted) {
        this.webMounted = true;
        try {
          this.webController.loadUrl(entry.url);
        } catch (error) {
          this.webMounted = false;
          this.browserSrc = entry.url;
        }
      } else {
        this.browserSrc = entry.url;
        this.webMounted = false;
      }
    } else {
      this.browserActive = false;
      this.webMounted = false;
    }
    this.syncBackState();
  }

  private close(): void {
    this.disposed = true;
    this.browserActive = false;
    this.webMounted = false;
    this.appState.readingCanGoBack = false;
    this.onClose();
  }

  private async saveCurrent(): Promise<void> {
    const entry = this.currentEntry();
    if (entry.savedOnce || entry.url.length === 0) {
      return;
    }
    try {
      const outcome = await FlowRepository.get().saveUrl(entry.url, entry.title, [], '', BookmarkSource.BROWSER);
      entry.savedOnce = true;
      AppState.shared.toast(outcome.created ? '已收下这一笺' : '这一笺已经在册');
      FlowRepository.get().applyMetadata(outcome.bookmark.id).catch(() => {});
    } catch (error) {
      AppState.shared.toast('没能收下这一页');
    }
  }

  private async copyLink(): Promise<void> {
    const entry = this.currentEntry();
    if (entry.url.length === 0) {
      return;
    }
    try {
      const data = pasteboard.createData(pasteboard.MIMETYPE_TEXT_PLAIN, entry.url);
      await pasteboard.getSystemPasteboard().setData(data);
      AppState.shared.toast('链接已复制');
    } catch (error) {
      AppState.shared.toast('复制失败');
    }
  }

  private openSystemBrowser(): void {
    const entry = this.currentEntry();
    if (entry.url.length === 0) {
      return;
    }
    const context = AppState.shared.abilityContext;
    if (context === undefined) {
      AppState.shared.toast('没有找到可打开它的应用');
      return;
    }
    const want: Want = {
      action: 'ohos.want.action.viewData',
      uri: entry.url
    };
    context.startAbility(want).catch(() => {
      AppState.shared.toast('没有找到可打开它的应用');
    });
  }

  private startAddressEdit(): void {
    this.addressDraft = this.currentEntry().url;
    this.addressEditing = true;
  }

  private navigateToAddress(): void {
    const normalized = normalizeUrl(this.addressDraft);
    if (normalized.length === 0) {
      AppState.shared.toast('这个地址打不开');
      return;
    }
    this.addressEditing = false;
    const entry = this.currentEntry();
    if (isSameUrl(normalized, entry.url)) {
      AppState.shared.toast('已经在这一页了');
      return;
    }
    const wasBrowser = entry.mode === ReadingMode.BROWSER;
    entry.mode = ReadingMode.BROWSER;
    entry.url = normalized;
    this.browserError = '';
    this.browserProgress = 0;
    this.webTitle = '';
    this.browserActive = true;
    if (wasBrowser && this.webMounted) {
      try {
        this.webController.loadUrl(normalized);
      } catch (error) {
        this.webMounted = false;
        this.browserSrc = normalized;
      }
    } else {
      this.browserSrc = normalized;
      this.webMounted = false;
    }
    this.syncBackState();
  }

  private retryWeb(): void {
    if (!this.webMounted) {
      AppState.shared.toast('网页还没有准备好');
      return;
    }
    this.browserError = '';
    try {
      this.webController.refresh();
    } catch (error) {
      AppState.shared.toast('刷新失败');
    }
  }

  private onWebControllerAttached(): void {
    this.webMounted = true;
    if (this.pendingUrl.length > 0) {
      const target = this.pendingUrl;
      this.pendingUrl = '';
      try {
        this.webController.loadUrl(target);
      } catch (error) {
        this.webMounted = false;
      }
    }
  }

  private onWebPageBegin(): void {
    if (!this.browserActive) {
      return;
    }
    this.browserError = '';
    this.browserProgress = 0;
    this.webTitle = '';
  }

  private onWebPageEnd(url: string): void {
    if (!this.browserActive) {
      return;
    }
    const entry = this.currentEntry();
    if (entry.mode !== ReadingMode.BROWSER) {
      return;
    }
    if (url.startsWith('http://') || url.startsWith('https://')) {
      entry.url = url;
    }
    if (this.webTitle.length > 0) {
      entry.title = this.webTitle;
      if (entry.transient) {
        entry.bookmark.title = this.webTitle;
      }
    }
    this.browserProgress = 100;
    this.syncBackState();
  }

  private onWebProgress(progress: number): void {
    if (!this.browserActive) {
      return;
    }
    this.browserProgress = progress;
  }

  private onWebTitle(title: string): void {
    if (!this.browserActive || title.length === 0) {
      return;
    }
    this.webTitle = title;
    const entry = this.currentEntry();
    if (entry.mode === ReadingMode.BROWSER) {
      entry.title = title;
      if (entry.transient) {
        entry.bookmark.title = title;
      }
    }
  }

  private onWebLoadError(): void {
    if (!this.browserActive) {
      return;
    }
    this.browserError = '页面没有打开';
    this.browserProgress = 100;
  }

  private onWebHttpError(code: number): void {
    if (!this.browserActive || code < 400) {
      return;
    }
    this.browserError = '页面返回了错误';
    this.browserProgress = 100;
  }

  private onWebLoadIntercept(target: string, isMainFrame: boolean): boolean {
    if (!isMainFrame) {
      return false;
    }
    if (target === 'about:blank') {
      return false;
    }
    if (target.startsWith('http://') || target.startsWith('https://')) {
      return false;
    }
    AppState.shared.toast('这个链接不能在应用内打开');
    return true;
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column() {
        this.TopBar()
        if (this.addressEditing) {
          this.AddressBar()
        }
        if (this.isBrowserMode()) {
          this.BrowserPane()
        } else {
          this.ReaderPane()
        }
      }
      .width('100%')
      .height('100%')
      .backgroundColor($r('app.color.paper'))

      if (this.appState.toastText.length > 0) {
        Text(this.appState.toastText)
          .fontSize(13)
          .fontColor($r('app.color.inverse_ink'))
          .backgroundColor($r('app.color.ink'))
          .borderRadius(999)
          .padding({ left: 18, right: 18, top: 9, bottom: 9 })
          .margin({ bottom: 64 })
      }
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }

  @Builder
  TopBar() {
    Column() {
      Row({ space: 4 }) {
        this.BarButton('返回', () => this.back())
        Column({ space: 2 }) {
          Text(this.pageTitle())
            .fontSize(13)
            .fontColor($r('app.color.ink'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
          Text(this.subtitle())
            .fontSize(11)
            .fontColor($r('app.color.ink_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
        }
        .layoutWeight(1)
        .alignItems(HorizontalAlign.Start)
        .onClick(() => {
          if (this.isBrowserMode()) {
            this.startAddressEdit();
          }
        })

        Text(this.isBrowserMode() ? '阅读' : '网页')
          .fontSize(13)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ left: 10, right: 10 })
          .accessibilityText(this.isBrowserMode() ? '切换到阅读模式' : '切换到网页')
          .focusable(true)
          .onClick(() => {
            if (this.isBrowserMode()) {
              this.switchToReader();
            } else {
              this.switchToBrowser();
            }
          })
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              if (this.isBrowserMode()) {
                this.switchToReader();
              } else {
                this.switchToBrowser();
              }
            }
          })
        Text('⋯')
          .fontSize(18)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .width(44)
          .textAlign(TextAlign.Center)
          .accessibilityText('更多操作')
          .focusable(true)
          .bindMenu(this.MoreMenu)
      }
      .width('100%')
      .height(52)
      .padding({ left: this.compact ? 8 : 16, right: this.compact ? 8 : 16 })

      if (this.isBrowserMode() && this.browserProgress > 0 && this.browserProgress < 100) {
        Stack({ alignContent: Alignment.Start }) {
          Row()
            .width('100%')
            .height(2)
            .backgroundColor($r('app.color.line'))
          Row()
            .width(`${Math.round(this.browserProgress)}%`)
            .height(2)
            .backgroundColor($r('app.color.ink'))
        }
        .width('100%')
        .height(2)
      }
    }
    .width('100%')
    .backgroundColor($r('app.color.paper'))
    .border({ width: { bottom: 1 }, color: $r('app.color.line') })
  }

  @Builder
  AddressBar() {
    Row({ space: 6 }) {
      TextInput({ text: this.addressDraft, placeholder: 'https://' })
        .fontSize(14)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(6)
        .height(44)
        .layoutWeight(1)
        .enterKeyType(EnterKeyType.Go)
        .onChange((value: string) => {
          this.addressDraft = value;
        })
        .onSubmit((enterKey: EnterKeyType) => {
          this.navigateToAddress();
        })
      this.BarButton('前往', () => this.navigateToAddress())
      this.BarButton('取消', () => {
        this.addressEditing = false;
      })
    }
    .width('100%')
    .padding({ left: this.compact ? 8 : 16, right: this.compact ? 8 : 16, bottom: 6 })
  }

  @Builder
  BarButton(label: string, action: () => void) {
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
  MoreMenu() {
    Menu() {
      if (this.isBrowserMode()) {
        MenuItem({ content: '刷新' })
          .onClick(() => {
            this.retryWeb();
          })
      }
      MenuItem({ content: '复制链接' })
        .onClick(() => {
          this.copyLink().catch(() => {});
        })
      if (this.currentEntry().transient && !this.currentEntry().savedOnce) {
        MenuItem({ content: '收藏这一页' })
          .onClick(() => {
            this.saveCurrent().catch(() => {});
          })
      }
      MenuItem({ content: '输入网址' })
        .onClick(() => {
          this.startAddressEdit();
        })
      MenuItem({ content: '用系统浏览器打开' })
        .onClick(() => {
          this.openSystemBrowser();
        })
      MenuItem({ content: '关闭' })
        .onClick(() => {
          this.close();
        })
    }
  }

  @Builder
  ReaderPane() {
    Column() {
      ReaderView({
        bookmark: this.currentEntry().bookmark,
        bookmarkId: this.currentEntry().bookmarkId,
        article: this.currentEntry().article,
        compact: this.compact,
        immersive: true,
        externalChrome: true,
        transient: this.currentEntry().transient,
        initialBlock: this.currentEntry().transient ? this.currentEntry().position : -1,
        savedOnce: this.currentEntry().savedOnce,
        loading: this.currentEntry().loading,
        onClose: () => this.back(),
        onOpenLink: (url: string) => {
          this.pushReaderLink(url);
        },
        onOpenBrowser: () => {
          this.switchToBrowser();
        },
        onSavePage: () => {
          this.saveCurrent().catch(() => {});
        },
        onRetry: () => {
          this.retryCurrent().catch(() => {});
        },
        onPositionChanged: (index: number) => {
          this.currentEntry().position = index;
        },
        onReadComplete: () => {
          const entry = this.currentEntry();
          if (!entry.transient && entry.bookmarkId.length > 0) {
            FlowRepository.get().setRead(entry.bookmarkId, ReadState.READ).catch(() => {});
            entry.bookmark.readState = ReadState.READ;
          }
        },
        onExcerptSaved: (excerpt: string) => {
          this.currentEntry().bookmark.excerpt = excerpt;
        }
      })
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  BrowserPane() {
    Stack() {
      if (this.browserSrc.length > 0) {
        Web({ src: this.browserSrc, controller: this.webController })
          .javaScriptAccess(true)
          .domStorageAccess(true)
          .fileAccess(false)
          .zoomAccess(true)
          .darkMode(WebDarkMode.Auto)
          .forceDarkAccess(false)
          .mediaPlayGestureAccess(true)
          .multiWindowAccess(false)
          .javaScriptOnDocumentStart(documentStartScripts())
          .onControllerAttached(() => {
            this.onWebControllerAttached();
          })
          .onPageBegin((event: OnPageBeginEvent) => {
            this.onWebPageBegin();
          })
          .onPageEnd((event: OnPageEndEvent) => {
            this.onWebPageEnd(event.url);
          })
          .onProgressChange((event: OnProgressChangeEvent) => {
            this.onWebProgress(event.newProgress);
          })
          .onTitleReceive((event: OnTitleReceiveEvent) => {
            this.onWebTitle(event.title);
          })
          .onErrorReceive((event: OnErrorReceiveEvent) => {
            if (!event.request.isMainFrame()) {
              return;
            }
            const code = event.error.getErrorCode();
            if (code !== WebNetErrorList.NET_OK && code !== WebNetErrorList.ERR_ABORTED) {
              this.onWebLoadError();
            }
          })
          .onHttpErrorReceive((event: OnHttpErrorReceiveEvent) => {
            if (event.request.isMainFrame()) {
              this.onWebHttpError(event.response.getResponseCode());
            }
          })
          .onLoadIntercept((event: OnLoadInterceptEvent): boolean => {
            return this.onWebLoadIntercept(event.data.getRequestUrl(), event.data.isMainFrame());
          })
          .backgroundColor($r('app.color.paper'))
          .width('100%')
          .height('100%')
      } else {
        Column({ space: 10 }) {
          Text('没有可以打开的地址')
            .fontSize(15)
            .fontColor($r('app.color.ink_secondary'))
        }
        .width('100%')
        .height('100%')
        .justifyContent(FlexAlign.Center)
      }

      if (this.browserError.length > 0) {
        this.BrowserErrorOverlay()
      }
    }
    .layoutWeight(1)
    .width('100%')
  }

  @Builder
  BrowserErrorOverlay() {
    Column({ space: 14 }) {
      Text(this.browserError)
        .fontSize(15)
        .fontColor($r('app.color.ink_secondary'))
      Row({ space: 12 }) {
        this.BarButton('重试', () => {
          this.retryWeb();
        })
        this.BarButton('用系统浏览器打开', () => {
          this.openSystemBrowser();
        })
      }
    }
    .width('100%')
    .height('100%')
    .justifyContent(FlexAlign.Center)
    .backgroundColor($r('app.color.paper'))
  }
}
