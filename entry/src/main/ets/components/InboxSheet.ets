import { pasteboard } from '@kit.BasicServicesKit';
import { AppState } from '../common/AppState';
import { BookmarkSource } from '../common/Constants';
import { domainOf, extractAllUrls, extractFirstUrl, isValidHttpUrl } from '../common/UrlUtil';
import { FlowRepository } from '../repository/FlowRepository';

@ComponentV2
export struct InboxSheet {
  @Local appState: AppState = AppState.shared;
  @Local urlText: string = '';
  @Local titleText: string = '';
  @Local tagsText: string = '';
  @Local noteText: string = '';
  @Local batchUrls: string[] = [];
  @Local busy: boolean = false;

  aboutToAppear(): void {
    this.urlText = this.appState.inboxUrl;
  }

  private parseTags(): string[] {
    const tags: string[] = [];
    const raw = this.tagsText.split(',');
    for (let i = 0; i < raw.length; i++) {
      const name = raw[i].trim();
      if (name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
    }
    const rawCn = this.tagsText.split('，');
    for (let i = 0; i < rawCn.length; i++) {
      const name = rawCn[i].trim();
      if (name.length > 0 && tags.indexOf(name) < 0) {
        tags.push(name);
      }
    }
    return tags;
  }

  private async save(): Promise<void> {
    if (this.busy) {
      return;
    }
    if (!isValidHttpUrl(this.urlText)) {
      AppState.shared.toast('这不是一个可收的链接');
      return;
    }
    this.busy = true;
    try {
      const outcome = await FlowRepository.get().saveUrl(
        this.urlText,
        this.titleText,
        this.parseTags(),
        this.noteText,
        BookmarkSource.MANUAL
      );
      this.appState.closeInbox();
      if (outcome.created) {
        AppState.shared.toast('收下了');
        FlowRepository.get().applyMetadata(outcome.bookmark.id).catch(() => {});
      } else {
        AppState.shared.toast('这一笺已经收过');
      }
    } catch (error) {
      AppState.shared.toast('没收下，请检查链接');
    } finally {
      this.busy = false;
    }
  }

  private async readClipboard(): Promise<void> {
    try {
      const data = await pasteboard.getSystemPasteboard().getData();
      const text = data.getPrimaryText();
      const all = extractAllUrls(text);
      if (all.length > 1) {
        this.batchUrls = all;
        return;
      }
      if (all.length === 1) {
        this.batchUrls = [];
        this.urlText = all[0];
        return;
      }
      // Legacy single-link path: keep inferring bare domains for hand-typed
      // text; batch extraction above is strictly explicit http(s).
      const found = extractFirstUrl(text);
      if (found.length === 0) {
        AppState.shared.toast('剪贴板里没有链接');
        return;
      }
      this.urlText = found;
    } catch (error) {
      AppState.shared.toast('读不到剪贴板');
    }
  }

  private async saveBatch(): Promise<void> {
    if (this.busy || this.batchUrls.length === 0) {
      return;
    }
    this.busy = true;
    try {
      const outcome = await FlowRepository.get().saveUrls(this.batchUrls, BookmarkSource.MANUAL);
      this.appState.closeInbox();
      if (outcome.done === 0 && outcome.skipped > 0) {
        AppState.shared.toast('这些都已收过');
      } else {
        const skipSuffix = outcome.skipped > 0 ? `、跳过 ${outcome.skipped} 条` : '';
        AppState.shared.toast(`收下 ${outcome.done} 条${skipSuffix}`);
      }
    } catch (error) {
      AppState.shared.toast('没收下，请检查链接');
    } finally {
      this.busy = false;
    }
  }

  private removeBatchUrl(url: string): void {
    this.batchUrls = this.batchUrls.filter((one: string): boolean => one !== url);
  }

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
        .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])
        .onClick(() => this.appState.closeInbox())

      Column({ space: 12 }) {
        Row()
          .width(36)
          .height(3)
          .backgroundColor($r('app.color.line_strong'))
          .borderRadius(2)
          .margin({ bottom: 8 })

        Row() {
          Text('收一笺')
            .fontSize(20)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Blank()
          Text('关闭')
            .fontSize(13)
            .fontColor($r('app.color.ink_secondary'))
            .height(44)
            .padding({ left: 10 })
            .accessibilityText('关闭收笺面板')
            .onClick(() => this.appState.closeInbox())
        }
        .width('100%')

        Row({ space: 8 }) {
          TextInput({ text: this.urlText, placeholder: 'https://…' })
            .fontSize(14)
            .fontColor($r('app.color.ink'))
            .placeholderColor($r('app.color.ink_tertiary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(6)
            .height(44)
            .layoutWeight(1)
            .onChange((value: string) => {
              this.urlText = value;
            })
          PasteButton({ text: PasteDescription.PASTE })
            .fontSize(14)
            .fontColor($r('app.color.ink_secondary'))
            .backgroundColor($r('app.color.surface_alt'))
            .borderRadius(6)
            .height(44)
            .padding({ left: 16, right: 16 })
            .onClick((event: ClickEvent, result: PasteButtonOnClickResult) => {
              if (result === PasteButtonOnClickResult.SUCCESS) {
                this.readClipboard();
              } else {
                AppState.shared.toast('没有获得剪贴板授权');
              }
            })
        }
        .width('100%')

        if (this.urlText.length > 0 && isValidHttpUrl(this.urlText)) {
          Text(domainOf(this.urlText))
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
            .width('100%')
        }

        if (this.batchUrls.length > 0) {
          Column({ space: 10 }) {
            Row() {
              Text(`识别到 ${this.batchUrls.length} 条链接`)
                .fontSize(13)
                .fontColor($r('app.color.ink'))
              Blank()
              Text('点一条移除一条')
                .fontSize(11)
                .fontColor($r('app.color.ink_tertiary'))
            }
            .width('100%')

            Scroll() {
              Column() {
                ForEach(this.batchUrls, (url: string) => {
                  Column({ space: 2 }) {
                    Text(domainOf(url).length > 0 ? domainOf(url) : url)
                      .fontSize(12)
                      .fontColor($r('app.color.ink'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                    Text(url)
                      .fontSize(11)
                      .fontColor($r('app.color.ink_tertiary'))
                      .maxLines(1)
                      .textOverflow({ overflow: TextOverflow.Ellipsis })
                  }
                  .alignItems(HorizontalAlign.Start)
                  .width('100%')
                  .constraintSize({ minHeight: 44 })
                  .justifyContent(FlexAlign.Center)
                  .onClick(() => this.removeBatchUrl(url))
                }, (url: string) => url)
              }
              .width('100%')
            }
            .width('100%')
            .constraintSize({ maxHeight: 216 })
            .scrollBar(BarState.Auto)
            .edgeEffect(EdgeEffect.None)

            Row({ space: 10 }) {
              Text(this.busy ? '正在收下…' : `收下这 ${this.batchUrls.length} 条`)
                .fontSize(14)
                .fontColor($r('app.color.inverse_ink'))
                .backgroundColor($r('app.color.ink'))
                .borderRadius(6)
                .height(44)
                .layoutWeight(1)
                .textAlign(TextAlign.Center)
                .accessibilityText(`收下这 ${this.batchUrls.length} 条链接`)
                .onClick(() => this.saveBatch())
              SymbolGlyph($r('sys.symbol.xmark'))
                .fontSize(16)
                .fontColor([$r('app.color.ink_secondary')])
                .height(44)
                .padding({ left: 10, right: 4 })
                .accessibilityText('忽略这批链接')
                .onClick(() => {
                  this.batchUrls = [];
                })
            }
            .width('100%')
            .alignItems(VerticalAlign.Center)
          }
          .width('100%')
          .padding(10)
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(8)
          .alignItems(HorizontalAlign.Start)
        }

        TextInput({ text: this.titleText, placeholder: '标题（可留空，稍后自动补全）' })
          .fontSize(15)
          .fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.ink_tertiary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(6)
          .height(44)
          .onChange((value: string) => {
            this.titleText = value;
          })

        TextInput({ text: this.tagsText, placeholder: '标签，用逗号分隔' })
          .fontSize(14)
          .fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.ink_tertiary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(6)
          .height(44)
          .onChange((value: string) => {
            this.tagsText = value;
          })

        TextArea({ text: this.noteText, placeholder: '备注（可选）' })
          .fontSize(14)
          .fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.ink_tertiary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(6)
          .height(76)
          .onChange((value: string) => {
            this.noteText = value;
          })

        Text(this.busy ? '正在收下…' : '收下')
          .fontSize(15)
          .fontColor($r('app.color.inverse_ink'))
          .backgroundColor($r('app.color.ink'))
          .borderRadius(6)
          .width('100%')
          .textAlign(TextAlign.Center)
          .padding({ top: 12, bottom: 12 })
          .margin({ top: 4 })
          .onClick(() => this.save())
      }
      .width('100%')
      .constraintSize({ maxWidth: 560 })
      .padding({ left: 22, right: 22, top: 12, bottom: 28 })
      .backgroundColor($r('app.color.surface'))
      .expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.BOTTOM])
      .borderRadius({ topLeft: 16, topRight: 16 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
  }
}
