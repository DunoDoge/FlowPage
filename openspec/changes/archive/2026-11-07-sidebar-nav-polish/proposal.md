# Proposal

## Why

侧边栏导航的交互质感落后于整体架构：☰ 是文本字形（跨设备渲染不一致且无状态语义）、抽屉导航项贴死安全区顶部（与 2in1 停靠栏的 26vp 留白不一致）、手机端进入标签/同步/设置后只剩「返回」无法再打开侧边栏，抽屉切换还会堆积导航栈；同时主要交互点在全项目范围内没有任何悬停/按压反馈，文本字形图标（`×`、`+`、`…`）不符合一次开发多端部署的图标规范。

## What Changes

- ☰ 按钮改用 `SymbolGlyph`：按点击动作显示图标——侧栏收起时显示 open_sidebar、展开时显示 close_sidebar；<1000vp（抽屉形态，无持久开合状态）恒显示 open_sidebar
- 手机/折叠屏抽屉导航区顶部补留白，对齐 2in1 停靠栏现有 26vp 口径
- tags / sync / settings 三个子页面头部增加 ☰ 入口，可在页内直接打开侧边栏抽屉（detail 详情页不加，已拍板）
- 抽屉切换 pane 时清空导航栈再进栈（对齐既有 `showDetailOnPhone` 的 clear+push 模式），消除 settings→sync→tags 层层堆栈
- FolderDrawer 增加出场/离场转场（平移 + 淡入）
- 主要交互点（☰、导航行、筛选 chips、书签行操作、页头按钮）补悬停/按压视觉反馈；阅读页内部不动（性能敏感区）
- 文本字形图标 SymbolGlyph 化：清除筛选 `×`、收笺 `+`、更多操作 `…`，保留既有 accessibilityText
- 子 44vp 触控目标（QuickActionPanel「取消」等）用 `responseRegion` 扩热区
- 抽共享组件消重：`NavList`（合并 SideNav 与 FolderDrawer 两份导航渲染）、`PageHeader`（合并 tags/sync/settings 三份页头，承载新 ☰ 入口）
- **不改**工程配置（`code-linter.json5` 保持现状）、**不改**断点阈值（700/1000vp 为刻意设计）、**不改** detail 页头部

## Capabilities

### New Capabilities

- `navigation-shell`: 侧边栏导航外壳的跨断点行为——☰ 图标语义与开合状态映射、抽屉/停靠栏形态一致性（含顶部留白）、子页面侧边栏可达性、抽屉 pane 切换的导航栈语义、抽屉转场
- `interaction-feedback`: 主交互面的反馈与图标规范——悬停/按压视觉反馈的覆盖范围与形态、SymbolGlyph 图标替代文本字形、触控热区下限

### Modified Capabilities

（无——`immersive-ui` 的安全区避让规则与 `ui-copy` 的文案约束均不受影响：抽屉留白不改变 expandSafeArea 行为，图标替换不改变文案与 accessibilityText）

## Impact

- **代码**：`entry/src/main/ets/components/NavigationRail.ets`（SideNav 重构为复用 NavList）、`entry/src/main/ets/pages/Index.ets`（FolderDrawer、openPane、PageMap 页头）、`entry/src/main/ets/components/StreamHome.ets`（☰ 按钮、chips、收笺按钮）、`entry/src/main/ets/pages/TagsPage.ets` / `SyncPage.ets` / `SettingsPage.ets`（换用 PageHeader）、`entry/src/main/ets/components/BookmarkRow.ets`（`…` 图标、热区）；新增 `components/NavList.ets`、`components/PageHeader.ets`
- **不受影响**：数据层（RDB/Repository）、同步、阅读页链路（ReaderView/ReadingShell）、桌面卡片（widget/ V1 组件）、`main_pages.json` 路由
- **符号资源依赖**：需在实现时对照 HarmonyOS Symbol 图标库核对 open_sidebar / close_sidebar 的 `sys.symbol.*` 资源名；若不存在按 design.md 的备选路径降级
- **文档**：AGENTS.md 中「☰ 全断点渲染」段落等易变事实需随实现更新
