import { Bookmark } from '../model/Bookmark';
import { ReadState } from '../common/Constants';
import { formatRelative } from '../common/DateUtil';
import { domainOf } from '../common/UrlUtil';

@ComponentV2
export struct BookmarkRow {
  @Param bookmark: Bookmark = new Bookmark();
  @Param selected: boolean = false;
  @Event onOpen: (id: string) => void = (id: string) => {};
  @Event onToggleStar: (id: string, starred: boolean) => void = (id: string, starred: boolean) => {};
  @Local pressing: boolean = false;

  private subtitle(): string {
    const domain = domainOf(this.bookmark.url);
    const time = formatRelative(this.bookmark.createdAt);
    if (domain.length === 0) {
      return time;
    }
    return `${domain} · ${time}`;
  }

  build() {
    Row({ space: 10 }) {
      if (this.bookmark.readState === ReadState.UNREAD && !this.bookmark.archived) {
        Row()
          .width(2)
          .height(16)
          .backgroundColor($r('app.color.ink'))
          .borderRadius(1)
          .margin({ top: 5 })
      }

      Column() {
        Text(this.bookmark.title.length > 0 ? this.bookmark.title : this.bookmark.url)
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .lineHeight(25)
          .maxLines(2)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
          .width('100%')

        if (this.bookmark.description.length > 0) {
          Text(this.bookmark.description)
            .fontSize(15)
            .fontColor($r('app.color.ink_secondary'))
            .lineHeight(23)
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .width('100%')
            .margin({ top: 4 })
        }

        Row({ space: 8 }) {
          Text(this.subtitle())
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
            .maxLines(1)
            .textOverflow({ overflow: TextOverflow.Ellipsis })
            .layoutWeight(1)
          ForEach(this.bookmark.tags.slice(0, 2), (tag: string) => {
            Text(tag)
              .fontSize(11)
              .fontColor($r('app.color.ink_secondary'))
              .padding({ left: 6, right: 6, top: 2, bottom: 2 })
              .border({ width: 1, color: $r('app.color.line_strong') })
              .borderRadius(2)
              .maxLines(1)
          }, (tag: string) => tag)
        }
        .width('100%')
        .margin({ top: 8 })
      }
      .layoutWeight(1)
      .alignItems(HorizontalAlign.Start)
      .onTouch((event: TouchEvent) => {
        if (event.type === TouchType.Down) {
          this.pressing = true;
        } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
          this.pressing = false;
        }
      })
      .onClick(() => {
        this.pressing = false;
        this.onOpen(this.bookmark.id);
      })

      Button(this.bookmark.starred ? '★' : '☆')
        .type(ButtonType.Normal)
        .fontSize(16)
        .fontColor(this.bookmark.starred ? $r('app.color.ink') : $r('app.color.ink_tertiary'))
        .backgroundColor(Color.Transparent)
        .width(32)
        .height(44)
        .padding(0)
        .responseRegion({ x: -12, y: 0, width: 44, height: 44 })
        .margin({ right: 8 })
        .onClick(() => {
          const next = !this.bookmark.starred;
          this.bookmark.starred = next;
          this.onToggleStar(this.bookmark.id, next);
        })
    }
    .width('100%')
    .padding({ left: 20, right: 24, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor(this.pressing || this.selected ? $r('app.color.surface_alt') : Color.Transparent)
  }
}
