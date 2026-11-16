import { KeyCode } from '@kit.InputKit';
import { Bookmark } from '../model/Bookmark';
import { AppState } from '../common/AppState';
import { FlowRepository } from '../repository/FlowRepository';
import { FolderPicker } from './FolderPicker';

// Full-screen folder target page (stream-row-actions / bookmark-folders):
// taps inside the Miller picker only drill + stage; the bottom bar commits
// the move explicitly. Mounted by Index via bindContentCover from
// AppState.folderPickOpen -- no route is added for this page.
@ComponentV2
export struct FolderPickerPage {
  @Param bookmark: Bookmark = new Bookmark();
  // stagedTouched separates "tapped 根目录" (stagedId '') from never tapped.
  @Local stagedTouched: boolean = false;
  @Local stagedId: string = '';
  @Local stagedLabel: string = '';
  @Local moving: boolean = false;
  @Local closeHovered: boolean = false;
  @Local closePressed: boolean = false;
  @Local confirmPressed: boolean = false;

  private displayTitle(): string {
    return this.bookmark.title.length > 0 ? this.bookmark.title : this.bookmark.url;
  }

  private close(): void {
    AppState.shared.folderPickOpen = false;
  }

  private stage(folderId: string, label: string): void {
    this.stagedTouched = true;
    this.stagedId = folderId;
    this.stagedLabel = folderId.length > 0 ? label : '根目录';
  }

  private async confirm(): Promise<void> {
    if (this.moving || !this.stagedTouched) {
      return;
    }
    this.moving = true;
    try {
      await FlowRepository.get().setBookmarkFolder(this.bookmark.id, this.stagedId);
      AppState.shared.toast(`已移到${this.stagedLabel}`);
      this.close();
    } catch (error) {
      AppState.shared.toast('移动失败，请稍后再试');
    } finally {
      this.moving = false;
    }
  }

  build() {
    Column() {
      Row({ space: 8 }) {
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.xmark'))
            .fontSize(18)
            .fontColor([$r('app.color.ink_secondary')])
        }
        .width(44)
        .height(44)
        .backgroundColor(this.closePressed || this.closeHovered
          ? $r('app.color.surface_alt')
          : Color.Transparent)
        .borderRadius(8)
        .accessibilityText('取消移动书签')
        .focusable(true)
        .onHover((isHover: boolean) => {
          this.closeHovered = isHover;
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.closePressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.closePressed = false;
          }
        })
        .onClick(() => this.close())
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
            this.close();
          }
        })
        Text('移动到文件夹')
          .fontSize(17)
          .fontWeight(FontWeight.Medium)
          .fontColor($r('app.color.ink'))
          .layoutWeight(1)
      }
      .width('100%')
      .height(52)
      .padding({ left: 12, right: 12 })
      .alignItems(VerticalAlign.Center)

      Text(`「${this.displayTitle()}」`)
        .fontSize(12)
        .fontColor($r('app.color.ink_secondary'))
        .maxLines(1)
        .textOverflow({ overflow: TextOverflow.Ellipsis })
        .width('100%')
        .padding({ left: 20, right: 20 })
        .margin({ top: 4, bottom: 4 })

      Column() {
        FolderPicker({
          selectedId: this.bookmark.folderId,
          rootLabel: '根目录',
          confirmMode: true,
          onStage: (folderId: string, label: string): void => {
            this.stage(folderId, label);
          }
        })
      }
      .layoutWeight(1)
      .width('100%')
      .padding({ left: 16, right: 16, top: 4 })

      Row({ space: 12 }) {
        Text(this.stagedTouched ? `目标：${this.stagedLabel}` : '点选一个层级')
          .fontSize(12)
          .fontColor($r('app.color.ink_secondary'))
          .layoutWeight(1)
          .maxLines(1)
          .textOverflow({ overflow: TextOverflow.Ellipsis })
        Text('移到这里')
          .fontSize(13)
          .fontColor(this.stagedTouched ? $r('app.color.inverse_ink') : $r('app.color.ink_tertiary'))
          .backgroundColor(this.stagedTouched ? $r('app.color.ink') : $r('app.color.surface_alt'))
          .opacity(this.confirmPressed ? 0.85 : 1)
          .borderRadius(6)
          .height(44)
          .padding({ left: 16, right: 16 })
          .textAlign(TextAlign.Center)
          .accessibilityText(this.stagedTouched ? `移到${this.stagedLabel}` : '未选择目标')
          .focusable(this.stagedTouched)
          .enabled(this.stagedTouched)
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.confirmPressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.confirmPressed = false;
            }
          })
          .onClick(() => {
            this.confirm();
          })
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              this.confirm();
            }
          })
      }
      .width('100%')
      .padding({ left: 20, right: 20, top: 10, bottom: 14 })
      .alignItems(VerticalAlign.Center)
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
  }
}
