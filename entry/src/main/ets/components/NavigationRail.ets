import { NavList } from './NavList';
import { FolderPanel } from './FolderPanel';

@ComponentV2
export struct SideNav {
  @Event onSelect: (pane: string) => void = (pane: string) => {};

  build() {
    Column() {
      NavList({
        onSelect: (pane: string) => {
          this.onSelect(pane);
        }
      })

      Column() {
        FolderPanel({
          isWide: true,
          docked: true
        })
      }
      .width('100%')
      .layoutWeight(1)
      .clip(false)
      .padding({ bottom: 24 })
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
    .border({ width: { right: 1 }, color: $r('app.color.line') })
  }
}
