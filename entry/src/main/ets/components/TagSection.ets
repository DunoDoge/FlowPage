import { TagCount } from '../model/Tag';
import { AppState } from '../common/AppState';
import { Pane } from '../common/Constants';
import { FlowRepository } from '../repository/FlowRepository';

// Rail-only tag section: picks write AppState.tagFilter so the stream
// column refilters without losing its place; the list column stays visible
// because the destination returns to the stream pane.
@ComponentV2
export struct TagSection {
  @Local appState: AppState = AppState.shared;
  @Local tags: TagCount[] = [];
  @Local hovered: string = '';
  @Local pressed: string = '';

  aboutToAppear(): void {
    if (this.appState.libraryReady) {
      this.load();
    }
  }

  @Monitor('appState.libraryReady')
  onLibraryReady(): void {
    if (this.appState.libraryReady) {
      this.load();
    }
  }

  @Monitor('appState.refreshTick')
  onLibraryChanged(): void {
    this.load();
  }

  private async load(): Promise<void> {
    try {
      this.tags = await FlowRepository.get().listTags();
    } catch (error) {
      this.tags = [];
    }
  }

  private pick(tag: TagCount): void {
    this.appState.tagFilter = tag.name;
    this.appState.goPane(Pane.DETAIL);
  }

  build() {
    if (this.tags.length > 0) {
      Column() {
        Row() {
          Text('标签')
            .fontSize(13)
            .fontWeight(FontWeight.Medium)
            .fontColor($r('app.color.ink'))
          Blank()
          Text(`${this.tags.length}`)
            .fontSize(12)
            .fontColor($r('app.color.ink_tertiary'))
            .margin({ right: 12 })
        }
        .width('100%')
        .height(40)
        .padding({ left: 10 })
        .alignItems(VerticalAlign.Center)

        Divider()
          .strokeWidth(1)
          .color($r('app.color.line'))

        Scroll() {
          Column() {
            ForEach(this.tags, (tag: TagCount) => {
              Row() {
                if (this.appState.tagFilter === tag.name) {
                  Row()
                    .width(2)
                    .height(20)
                    .backgroundColor($r('app.color.ink'))
                    .borderRadius(1)
                }
                Text(tag.name)
                  .fontSize(14)
                  .fontColor(this.appState.tagFilter === tag.name
                    ? $r('app.color.ink')
                    : $r('app.color.ink_secondary'))
                  .fontWeight(this.appState.tagFilter === tag.name ? FontWeight.Medium : FontWeight.Normal)
                  .margin({ left: 20 })
                  .layoutWeight(1)
                  .maxLines(1)
                  .textOverflow({ overflow: TextOverflow.Ellipsis })
                Text(`${tag.count}`)
                  .fontSize(12)
                  .fontColor($r('app.color.ink_tertiary'))
                  .margin({ right: 12 })
              }
              .width('100%')
              .height(40)
              .alignItems(VerticalAlign.Center)
              .accessibilityText(`筛选标签${tag.name}，${tag.count} 条`)
              .focusable(true)
              .backgroundColor(this.pressed === tag.id || this.hovered === tag.id
                ? $r('app.color.surface_alt')
                : Color.Transparent)
              .onHover((isHover: boolean) => {
                this.hovered = isHover ? tag.id : '';
              })
              .onTouch((event: TouchEvent) => {
                if (event.type === TouchType.Down) {
                  this.pressed = tag.id;
                } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                  this.pressed = '';
                }
              })
              .onClick(() => {
                this.pick(tag);
              })
            }, (tag: TagCount) => `${tag.id}|${tag.name}|${tag.count}`)
          }
          .width('100%')
        }
        .width('100%')
        .constraintSize({ maxHeight: 200 })
        .scrollBar(BarState.Off)
        .edgeEffect(EdgeEffect.None)
      }
      .width('100%')
    }
  }
}
