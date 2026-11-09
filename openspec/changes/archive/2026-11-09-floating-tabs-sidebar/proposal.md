# Proposal

## Why

小屏设备目前把「标签 / 同步 / 设置」塞进手机的导航栈，目的地切换依赖 ☰ 抽屉里的四项文字导航，拇指可达性和切换效率都不理想。大屏侧栏则只有四项导航与文件夹树，没有把已有的智能视图、标签和同步状态暴露出来。本轮把目的地导航改为底部悬浮页签（手机与 700–999vp），把抽屉/侧栏收敛为「资料库」，并让大屏侧栏承载更多资料库入口。

## What Changes

- 新增底部悬浮页签，作为 `流笺 / 标签 / 同步 / 设置` 四个目的地的唯一切换入口：
  - `<700vp`：页签位于窗口底部；`Navigation` 外层保留，仅 `detail` 仍走导航栈，详情页盖住页签。
  - `700–999vp`：页签包住右栏内容并在右栏底部居中；左栏 `StreamHome` 保持常驻，不复制列表实例。
  - `>=1000vp`：不显示页签，仍使用停靠式 `SideNav`。
- 页签容器迁移到 `@kit.UIDesignKit` 的 `HdsTabs`，并为 <1000vp 配置「资料库」迷你栏（MiniBar）：迷你栏是常驻的资料库入口，点击打开现有左侧抽屉；主页头部 ☰ 在 <1000vp 随之移除，资料库入口在 标签/同步/设置 页签下同样可达；`>=1000vp` 无迷你栏，停靠栏与 ☰ 切换不变。
- 抽屉与侧栏改为「资料库」：抽屉不再渲染四项导航；`NavList` 只在没有页签的 `>=1000vp` 停靠栏中保留。
- 侧栏内容扩展：
  - 手机抽屉：智能视图（全部 / 未读 / 星标 / 归档 / 回收站，带计数）+ 文件夹树。
  - 大屏侧栏：智能视图 + 文件夹树 + 标签（前 N 项 + 计数）+ 同步状态（已配置 / 上次同步 / 去同步）。
- 统一导航数据源：`NAV_ITEMS` 从 `NavList.ets` 私有常量提升为共享定义，页签与停靠栏同源；页签使用 `SymbolGlyph + 文字`。
- 筛选入口收敛：`appState.homeFilter` 成为唯一事实源，侧栏智能视图（手机抽屉 / 大屏停靠栏）是主列表筛选的唯一入口；主页原有筛选 chips 行随之移除。
- **BREAKING**（内部交互契约）：手机端不再通过导航栈进入 tags / sync / settings；`PageHeader` 的 ☰ 不再用于子页面切目的地；<1000vp 页头 ☰ 移除，资料库入口由悬浮页签迷你栏承担。系统返回在页签栈为空时回到「流笺」页签。
- 手机批量选择时隐藏悬浮页签与迷你栏，由 `BatchActionBar` 接管底部；`700–999vp` 批量栏在左栏，与右栏页签互不影响。
- 悬浮页签与迷你栏以 HdsTabs 的沉浸式系统材质渲染背板（默认 ADAPTIVE 档，PC/2in1 免材质能力查询）；遵循沉浸光感作用域与功耗约束，不做全页面材质化。页签真机校准贴底：在 HdsTabs 布局/分档参数下校准，不与根容器安全区扩展叠加成双倍间距。
- 页签切换与 ≥1000vp 右栏切换统一加入单向「落纸」进场过渡（淡入 + 上浮，每次切换播放、无左右滑动，启动首屏除外），并显式关闭页签默认横滑动效。

## Capabilities

### New Capabilities

- `library-sidebar`: 资料库侧栏的内容分区、计数与筛选联动、按断点裁剪，以及侧栏与页签/列表的状态一致性。

### Modified Capabilities

- `navigation-shell`: 目的地导航由导航栈改为悬浮页签；抽屉不再承载目的地项；返回与 pane 语义随断点变化；资料库入口由页头 ☰ 改为页签迷你栏（<1000vp）。
- `immersive-ui`: 悬浮页签与迷你栏和系统栏、列表末行、批量操作栏的遮挡与安全区约束。
- `interaction-feedback`: 悬浮页签、资料库迷你栏与侧栏新分区的悬停/按压反馈、图标规范与触控热区。

## Impact

- 主要代码：`pages/Index.ets`（壳层与断点）、`components/StreamHome.ets`（底部内边距、批量态与筛选行移除）、`components/NavList.ets`（共享常量与 `showItems`）、`components/NavigationRail.ets`、`components/FolderPanel.ets`、`components/PageHeader.ets`、`pages/TagsPage.ets` / `SyncPage.ets` / `SettingsPage.ets`（顶层化后的页头参数）、`common/AppState.ets`（`homeFilter` 双向）、新增页签与资料库组件。
- 依赖：页签容器改用 `@kit.UIDesignKit` 的 `HdsTabs`（含 hdsMaterial），除此之外无第三方运行时依赖；PC/2in1 材质用默认 ADAPTIVE 档免能力查询。
- 测试：`entry/src/ohosTest` 中涉及手机导航栈、抽屉、pane 切换的套件需要同步调整；新增页签切换、返回语义、侧栏筛选联动的设备端用例。
- 规格与文档：`openspec/specs/navigation-shell`、`immersive-ui`、`interaction-feedback` 需更新；落地后按 AGENTS.md 更新导航模型与断点事实。
- 风险：Tabs 会一次性构建全部 TabContent（启动期多出标签/同步/设置的初始化）；`barOverlap` 与现有安全区方案叠加需要真机校准；2in1 窄窗会走页签分支，材质行为需走查；HdsTabs 官方推荐作 Page 根容器而本方案嵌在 `Navigation` 内与右栏内，需原型验证；原生 Tabs 既有配置（自绘页签 item、进场过渡、批量隐藏、贴底、无障碍）需逐项等价迁移。
