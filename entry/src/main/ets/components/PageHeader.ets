import { KeyCode } from '@kit.InputKit';
import { AppState } from '../common/AppState';

// Shared page header for stack-pushed sub pages: optional back + optional
// sidebar menu (phone drawer entry, hidden on wide where the rail is docked)
// plus a caller-supplied trailing status slot. Menu icon stays open_sidebar
// because the drawer has no persistent open state on narrow widths.
// Feedback is hover/press driven manually: stateStyles sticks on plain
// text/glyph components after the pointer leaves, so each control paints a
// conditional surface_alt background while hovered or pressed.
@ComponentV2
export struct PageHeader {
  @Param showBack: boolean = false;
  @Param showMenu: boolean = false;
  @Event onBack: () => void = () => {};
  @Local appState: AppState = AppState.shared;
  @Local menuHovered: boolean = false;
  @Local menuPressed: boolean = false;
  @Local backHovered: boolean = false;
  @Local backPressed: boolean = false;

  @Builder
  NoopTrailing() {
  }

  @BuilderParam trailing: () => void = this.NoopTrailing;

  build() {
    Row() {
      if (this.showMenu) {
        // Centered Stack owns the hit box and background: a sized
        // SymbolGlyph paints its background on the placeholder box, which
        // does not follow the glyph anchor and reads as misaligned.
        Stack({ alignContent: Alignment.Center }) {
          SymbolGlyph($r('sys.symbol.open_sidebar'))
            .fontSize(20)
            .fontColor([$r('app.color.ink_secondary')])
        }
        .width(44)
        .height(44)
        .backgroundColor(this.menuPressed || this.menuHovered
          ? $r('app.color.surface_alt')
          : Color.Transparent)
        .borderRadius(8)
        .accessibilityText('打开侧边栏')
        .focusable(true)
        .onHover((isHover: boolean) => {
          this.menuHovered = isHover;
        })
        .onTouch((event: TouchEvent) => {
          if (event.type === TouchType.Down) {
            this.menuPressed = true;
          } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
            this.menuPressed = false;
          }
        })
        .onClick(() => {
          this.appState.folderDrawerOpen = true;
        })
        .onKeyEvent((event: KeyEvent) => {
          if (event.type === KeyType.Down &&
            (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
            this.appState.folderDrawerOpen = true;
          }
        })
      }

      if (this.showBack) {
        Text('返回')
          .fontSize(13)
          .fontColor($r('app.color.ink_secondary'))
          .height(44)
          .padding({ right: 12 })
          .accessibilityText('返回')
          .focusable(true)
          .backgroundColor(this.backPressed || this.backHovered
            ? $r('app.color.surface_alt')
            : Color.Transparent)
          .borderRadius(8)
          .onHover((isHover: boolean) => {
            this.backHovered = isHover;
          })
          .onTouch((event: TouchEvent) => {
            if (event.type === TouchType.Down) {
              this.backPressed = true;
            } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
              this.backPressed = false;
            }
          })
          .onClick(() => this.onBack())
          .onKeyEvent((event: KeyEvent) => {
            if (event.type === KeyType.Down &&
              (event.keyCode === KeyCode.KEYCODE_ENTER || event.keyCode === KeyCode.KEYCODE_SPACE)) {
              this.onBack();
            }
          })
      }

      Blank()

      this.trailing()
    }
    .width('100%')
    .padding({ left: 20, right: 20, top: 12 })
  }
}
