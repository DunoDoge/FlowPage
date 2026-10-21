import { AppState } from '../common/AppState';
import { BookmarkSource } from '../common/Constants';
import { domainOf, isValidHttpUrl } from '../common/UrlUtil';
import { FlowRepository } from '../repository/FlowRepository';

@ComponentV2
export struct InboxSheet {
  @Local appState: AppState = AppState.shared;
  @Local urlText: string = '';
  @Local titleText: string = '';
  @Local tagsText: string = '';
  @Local noteText: string = '';
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

  build() {
    Stack({ alignContent: Alignment.Bottom }) {
      Column()
        .width('100%')
        .height('100%')
        .backgroundColor($r('app.color.overlay'))
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

        TextInput({ text: this.urlText, placeholder: 'https://…' })
          .fontSize(14)
          .fontColor($r('app.color.ink'))
          .placeholderColor($r('app.color.ink_tertiary'))
          .backgroundColor($r('app.color.surface_alt'))
          .borderRadius(6)
          .height(44)
          .onChange((value: string) => {
            this.urlText = value;
          })

        if (this.urlText.length > 0 && isValidHttpUrl(this.urlText)) {
          Text(domainOf(this.urlText))
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
            .width('100%')
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
      .borderRadius({ topLeft: 16, topRight: 16 })
      .onClick(() => {})
    }
    .width('100%')
    .height('100%')
  }
}
