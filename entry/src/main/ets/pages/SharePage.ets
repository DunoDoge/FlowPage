import { common } from '@kit.AbilityKit';
import { AppState } from '../common/AppState';
import { BookmarkSource } from '../common/Constants';
import { domainOf, isValidHttpUrl } from '../common/UrlUtil';
import { FlowRepository } from '../repository/FlowRepository';

@Entry
@ComponentV2
struct SharePage {
  @Local urlText: string = '';
  @Local titleText: string = '';
  @Local tagsText: string = '';
  @Local busy: boolean = false;

  aboutToAppear(): void {
    const url = AppStorage.get<string>('shared_url');
    const title = AppStorage.get<string>('shared_title');
    this.urlText = url !== undefined ? url : '';
    this.titleText = title !== undefined ? title : '';
  }

  private close(): void {
    const context = getContext(this) as common.UIExtensionContext;
    context.terminateSelf();
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
      const context = getContext(this) as common.Context;
      await FlowRepository.get().init(context);
      const outcome = await FlowRepository.get().saveUrl(
        this.urlText,
        this.titleText,
        this.parseTags(),
        '',
        BookmarkSource.SHARE
      );
      if (outcome.created) {
        FlowRepository.get().applyMetadata(outcome.bookmark.id).catch(() => {});
      }
      this.close();
    } catch (error) {
      this.busy = false;
      AppState.shared.toast('没收下');
    }
  }

  build() {
    Column({ space: 12 }) {
      Row() {
        Text('收进流笺')
          .fontSize(20)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
        Blank()
        Text('取消')
          .fontSize(13)
          .fontColor($r('app.color.ink_secondary'))
          .onClick(() => this.close())
      }
      .width('100%')

      TextInput({ text: this.urlText, placeholder: 'https://…' })
        .fontSize(14)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(6)
        .height(42)
        .onChange((value: string) => {
          this.urlText = value;
        })

      if (this.urlText.length > 0 && isValidHttpUrl(this.urlText)) {
        Text(domainOf(this.urlText))
          .fontSize(11)
          .fontColor($r('app.color.ink_tertiary'))
          .width('100%')
      }

      TextInput({ text: this.titleText, placeholder: '标题（可留空）' })
        .fontSize(15)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(6)
        .height(42)
        .onChange((value: string) => {
          this.titleText = value;
        })

      TextInput({ text: this.tagsText, placeholder: '标签，用逗号分隔' })
        .fontSize(13)
        .fontColor($r('app.color.ink'))
        .placeholderColor($r('app.color.ink_tertiary'))
        .backgroundColor($r('app.color.surface_alt'))
        .borderRadius(6)
        .height(42)
        .onChange((value: string) => {
          this.tagsText = value;
        })

      Text(this.busy ? '收下中…' : '收下')
        .fontSize(14)
        .fontColor($r('app.color.inverse_ink'))
        .backgroundColor($r('app.color.ink'))
        .borderRadius(6)
        .width('100%')
        .textAlign(TextAlign.Center)
        .padding({ top: 11, bottom: 11 })
        .onClick(() => this.save())
    }
    .width('100%')
    .height('100%')
    .padding({ left: 20, right: 20, top: 16, bottom: 20 })
    .backgroundColor($r('app.color.paper'))
    .alignItems(HorizontalAlign.Start)
  }
}
