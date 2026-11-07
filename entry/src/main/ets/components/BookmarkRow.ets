import { Bookmark } from '../model/Bookmark';
import { KeyCode } from '@kit.InputKit';
import { unifiedDataChannel } from '@kit.ArkData';
import { HighlightSegment, highlightSegments } from '../common/Highlight';
import { ReadState } from '../common/Constants';
import { FolderDragSession } from '../common/FolderDragSession';
import { formatRelative } from '../common/DateUtil';
import { domainOf } from '../common/UrlUtil';

@ComponentV2
export struct BookmarkRow {
  @Param bookmark: Bookmark = new Bookmark();
  @Param index: number = 0;
  @Param keyword: string = '';
  @Param selected: boolean = false;
  @Param selectionMode: boolean = false;
  @Param checked: boolean = false;
  @Param selectedBookmarkIds: string[] = [];
  @Param selectedFolderIds: string[] = [];
  @Param dragEnabled: boolean = true;
  @Event onOpen: (id: string) => void = (id: string) => {};
  @Event onToggleStar: (id: string, starred: boolean) => void = (id: string, starred: boolean) => {};
  @Event onMoveFocus: (delta: number) => void = (delta: number) => {};
  @Event onFocused: (index: number) => void = (index: number) => {};
  @Event onRequestActions: (id: string) => void = (id: string) => {};
  @Event onToggleSelect: (id: string) => void = (id: string) => {};
  @Event onBeginDrag: (id: string) => void = (id: string) => {};
  @Event onDragFinished: () => void = () => {};
  @Local pressing: boolean = false;
  // Manual hover/press feedback state for the trailing star/more buttons;
  // stateStyles leaves the pressed background stuck, hdsEffect.pressShadow
  // does not render on custom components.
  @Local starHovered: boolean = false;
  @Local starPressed: boolean = false;
  @Local moreHovered: boolean = false;
  @Local morePressed: boolean = false;
  private suppressClick: boolean = false;

  private displayTitle(): string {
    return this.bookmark.title.length > 0 ? this.bookmark.title : this.bookmark.url;
  }

  private subtitle(): string {
    const domain = domainOf(this.bookmark.url);
    const time = formatRelative(this.bookmark.createdAt);
    if (domain.length === 0) {
      return time;
    }
    return `${domain} · ${time}`;
  }

  private requestActions(): void {
    if (this.selectionMode) {
      return;
    }
    this.suppressClick = true;
    setTimeout(() => {
      this.suppressClick = false;
    }, 400);
    this.onRequestActions(this.bookmark.id);
  }

  private activate(): void {
    if (this.suppressClick) {
      this.suppressClick = false;
      return;
    }
    this.onOpen(this.bookmark.id);
  }

  private startDrag(event: DragEvent): DragItemInfo {
    this.pressing = false;
    this.onBeginDrag(this.bookmark.id);
    const data = new unifiedDataChannel.PlainText();
    data.textContent = FolderDragSession.PAYLOAD;
    event.setData(new unifiedDataChannel.UnifiedData(data));
    const info: DragItemInfo = { extraInfo: FolderDragSession.PAYLOAD };
    return info;
  }

  private dragBadge(): number {
    if (this.checked) {
      return this.selectedBookmarkIds.length + this.selectedFolderIds.length;
    }
    return 1;
  }

  build() {
    Row({ space: 10 }) {
      if (this.selectionMode) {
        Text(this.checked ? '✓' : '')
          .fontSize(12)
          .fontWeight(FontWeight.Bold)
          .fontColor(this.checked ? $r('app.color.inverse_ink') : $r('app.color.ink_tertiary'))
          .width(20)
          .height(20)
          .textAlign(TextAlign.Center)
          .border({ width: 1, color: this.checked ? $r('app.color.ink') : $r('app.color.line_strong') })
          .borderRadius(10)
          .backgroundColor(this.checked ? $r('app.color.ink') : Color.Transparent)
          .margin({ top: 3 })
          .accessibilityText(this.checked ? '已选择' : '未选择')
          .onClick(() => this.onToggleSelect(this.bookmark.id))
      }

      if (this.bookmark.readState === ReadState.UNREAD && !this.bookmark.archived) {
        Row()
          .width(2)
          .height(16)
          .backgroundColor($r('app.color.ink'))
          .borderRadius(1)
          .margin({ top: 5 })
      }

      Column() {
        this.TitleText()

        if (this.bookmark.description.length > 0) {
          this.DescriptionText()
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
        this.activate();
      })
      .draggable(this.dragEnabled)
      .dragPreviewOptions({ numberBadge: this.dragBadge() })
      .onDragStart((event: DragEvent): DragItemInfo => {
        return this.startDrag(event);
      })
      .onDragEnd(() => {
        this.pressing = false;
        this.onDragFinished();
      })

      if (!this.selectionMode) {
        Button(this.bookmark.starred ? '★' : '☆')
          .type(ButtonType.Normal)
          .stateEffect(false)
          .fontSize(16)
          .fontColor(this.bookmark.starred ? $r('app.color.ink') : $r('app.color.ink_tertiary'))
          .width(32)
          .height(44)
          .padding(0)
          .responseRegion({ x: -12, y: 0, width: 44, height: 44 })
          .margin({ right: 8 })
          .backgroundColor(this.starPressed || this.starHovered
            ? $r('app.color.surface_alt')
            : Color.Transparent)
          .borderRadius(8)
          .onHover((isHover: boolean) => {
            this.starHovered = isHover;
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.starPressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.starPressed = false;
            }
          })
          .accessibilityText(this.bookmark.starred ? '取消星标' : '加星标')
          .onClick(() => {
            const next = !this.bookmark.starred;
            this.bookmark.starred = next;
            this.onToggleStar(this.bookmark.id, next);
          })
      }

      if (!this.selectionMode) {
        Button() {
          SymbolGlyph($r('sys.symbol.more'))
            .fontSize(16)
            .fontColor([$r('app.color.ink_secondary')])
        }
          .type(ButtonType.Normal)
          .stateEffect(false)
          .width(32)
          .height(44)
          .padding(0)
          .margin({ right: 4 })
          .responseRegion({ x: 0, y: 0, width: 44, height: 44 })
          .backgroundColor(this.morePressed || this.moreHovered
            ? $r('app.color.surface_alt')
            : Color.Transparent)
          .borderRadius(8)
          .onHover((isHover: boolean) => {
            this.moreHovered = isHover;
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.morePressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.morePressed = false;
            }
          })
          .accessibilityText('更多操作')
          .onClick(() => this.requestActions())
      }
    }
    .id(`bookmark-row-${this.bookmark.id}`)
    .width('100%')
    .constraintSize({ minHeight: 44 })
    .padding({ left: 20, right: 24, top: 16, bottom: 16 })
    .alignItems(VerticalAlign.Top)
    .backgroundColor(this.pressing || this.selected || this.checked ? $r('app.color.surface_alt') : Color.Transparent)
    // Desktop right-click opens the same anchored panel as the trailing "…"
    // button (D12); bound on the whole row like the folder rows so the hit
    // area covers the full row, not just the text column.
    .onMouse((event: MouseEvent) => {
      if (event.button === MouseButton.Right && event.action === MouseAction.Press) {
        this.requestActions();
      }
    })
    .accessibilityText(`${this.displayTitle()}，${this.subtitle()}`)
    .focusable(true)
    .onFocus(() => {
      this.onFocused(this.index);
    })
    .onKeyEvent((event: KeyEvent) => {
      if (event.type !== KeyType.Down) {
        return;
      }
      if (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE) {
        this.activate();
      } else if (event.keyCode === KeyCode.KEYCODE_DPAD_UP) {
        this.onMoveFocus(-1);
      } else if (event.keyCode === KeyCode.KEYCODE_DPAD_DOWN) {
        this.onMoveFocus(1);
      }
    })
  }

  @Builder
  TitleText() {
    Text() {
      ForEach(highlightSegments(this.displayTitle(), this.keyword), (segment: HighlightSegment) => {
        Span(segment.text)
          .fontSize(17)
          .fontWeight(segment.matched ? FontWeight.Bold : FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .textBackgroundStyle(segment.matched
            ? { color: $r('app.color.highlight') }
            : { color: Color.Transparent })
      }, (segment: HighlightSegment, index: number) => `${index}:${segment.matched}:${segment.text}`)
    }
    .lineHeight(25)
    .maxLines(2)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .width('100%')
  }

  @Builder
  DescriptionText() {
    Text() {
      ForEach(highlightSegments(this.bookmark.description, this.keyword), (segment: HighlightSegment) => {
        Span(segment.text)
          .fontSize(15)
          .fontColor($r('app.color.ink_secondary'))
          .fontWeight(segment.matched ? FontWeight.Bold : FontWeight.Normal)
          .textBackgroundStyle(segment.matched
            ? { color: $r('app.color.highlight') }
            : { color: Color.Transparent })
      }, (segment: HighlightSegment, index: number) => `${index}:${segment.matched}:${segment.text}`)
    }
    .lineHeight(23)
    .maxLines(1)
    .textOverflow({ overflow: TextOverflow.Ellipsis })
    .width('100%')
    .margin({ top: 4 })
  }
}
