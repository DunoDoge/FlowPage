import { AppState } from '../common/AppState';
import { Pane } from '../common/Constants';
import { FolderPanel } from './FolderPanel';

export class NavItem {
  label: string = '';
  pane: string = '';
}

export const NAV_ITEMS: NavItem[] = [
  { label: '流笺', pane: Pane.DETAIL },
  { label: '标签', pane: Pane.TAGS },
  { label: '同步', pane: Pane.SYNC },
  { label: '设置', pane: Pane.SETTINGS }
];

@ComponentV2
export struct SideNav {
  @Local appState: AppState = AppState.shared;
  @Event onSelect: (pane: string) => void = (pane: string) => {};

  build() {
    Column() {
      Column({ space: 2 }) {
        Text('流笺')
          .fontSize(22)
          .fontWeight(FontWeight.Bold)
          .fontColor($r('app.color.ink'))
        Text('FLOWPAGE')
          .fontSize(9)
          .fontColor($r('app.color.ink_tertiary'))
          .letterSpacing(2)
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 24, top: 26, bottom: 30 })

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
            .margin({ left: 22 })
        }
        .width('100%')
        .height(44)
        .alignItems(VerticalAlign.Center)
        .accessibilityText(`打开${item.label}`)
        .focusable(true)
        .onClick(() => this.onSelect(item.pane))
      }, (item: NavItem) => item.pane)

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))
        .margin({ top: 8 })

      Column() {
        FolderPanel({
          isWide: true,
          docked: true
        })
      }
      .width('100%')
      .layoutWeight(1)
      .clip(false)

      Column({ space: 6 }) {
        Text('本地优先')
          .fontSize(11)
          .fontColor($r('app.color.ink_tertiary'))
        Text('数据在这台设备上')
          .fontSize(10)
          .fontColor($r('app.color.ink_tertiary'))
      }
      .alignItems(HorizontalAlign.Start)
      .width('100%')
      .padding({ left: 24, bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
    .border({ width: { right: 1 }, color: $r('app.color.line') })
  }
}
