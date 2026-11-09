import { NavList } from './NavList';
import { SmartViews } from './SmartViews';
import { TagSection } from './TagSection';
import { SyncSection } from './SyncSection';
import { FolderPanel } from './FolderPanel';

// Docked rail (>=1000vp): destination nav on top, then the library — smart
// views, folder tree, tags and sync status. The tree keeps its internal
// scroll; the extra sections are fixed blocks around it.
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

      SmartViews()

      Column() {
        FolderPanel({
          isWide: true,
          docked: true
        })
      }
      .width('100%')
      .layoutWeight(1)
      .clip(false)

      TagSection()

      Divider()
        .strokeWidth(1)
        .color($r('app.color.line'))
        .margin({ top: 4 })

      SyncSection()
    }
    .width('100%')
    .height('100%')
    .backgroundColor($r('app.color.paper'))
    .border({ width: { right: 1 }, color: $r('app.color.line') })
    .padding({ bottom: 24 })
  }
}
