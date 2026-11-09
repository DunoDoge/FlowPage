import { AppState } from '../common/AppState';
import { NAV_ITEMS, NavItem } from '../common/Constants';

// Shared top inset so the overlay drawer and the docked rail breathe the
// same amount below the safe-area edge; label inset matches the home
// header's 20vp hamburger inset. The inset stays rendered even when the
// nav items are hidden (drawer carries the library instead) so the first
// block keeps the same offset on every breakpoint.
const TOP_INSET: number = 26;
const LABEL_INSET: number = 20;

// Feedback is driven manually by onHover/onTouch + @Local state:
// stateStyles leaves the pressed background stuck on plain rows, and the
// official hdsEffect.pressShadow renders nothing outside HDS-themed
// components (verified on device), so a conditional surface_alt background
// is the reliable option.
@ComponentV2
export struct NavList {
  @Param showItems: boolean = true;
  @Local appState: AppState = AppState.shared;
  @Local hoveredPane: string = '';
  @Local pressedPane: string = '';
  @Event onSelect: (pane: string) => void = (pane: string) => {};

  build() {
    Column() {
      if (this.showItems) {
        Column() {
          ForEach(NAV_ITEMS, (item: NavItem) => {
            Row() {
              if (this.appState.pane === item.pane) {
                Row()
                  .width(2)
                  .height(20)
                  .backgroundColor($r('app.color.ink'))
                  .borderRadius(1)
              }
              Text(item.label)
                .fontSize(14)
                .fontColor(this.appState.pane === item.pane ? $r('app.color.ink') : $r('app.color.ink_secondary'))
                .fontWeight(this.appState.pane === item.pane ? FontWeight.Medium : FontWeight.Normal)
                .margin({ left: LABEL_INSET })
            }
            .width('100%')
            .height(44)
            .alignItems(VerticalAlign.Center)
            .accessibilityText(`打开${item.label}`)
            .focusable(true)
            .backgroundColor(this.pressedPane === item.pane || this.hoveredPane === item.pane
              ? $r('app.color.surface_alt')
              : Color.Transparent)
            .onHover((isHover: boolean) => {
              this.hoveredPane = isHover ? item.pane : '';
            })
            .onTouch((event: TouchEvent) => {
              if (event.type === TouchType.Down) {
                this.pressedPane = item.pane;
              } else if (event.type === TouchType.Up || event.type === TouchType.Cancel) {
                this.pressedPane = '';
              }
            })
            .onClick(() => {
              this.onSelect(item.pane);
            })
          }, (item: NavItem) => item.pane)
        }
        .width('100%')
        .padding({ top: TOP_INSET })

        Divider()
          .strokeWidth(1)
          .color($r('app.color.line'))
          .margin({ top: 8 })
      } else {
        // An empty padded column collapses to zero height, so the hidden
        // form carries the shared top inset as an explicit spacer.
        Column()
          .width('100%')
          .height(TOP_INSET)
      }
    }
    .width('100%')
  }
}
