# Tasks

## 1. 符号资源核对（前置 spike）

- [x] 1.1 对照 HarmonyOS Symbol 图标库确定 open_sidebar / close_sidebar 及关闭（×）、加号（+）、更多（…）对应的 `sys.symbol.*` 资源名；精确名不存在时按 `design.md` D1 降级链选定替代，并把最终资源名结论回写 `openspec/changes/sidebar-nav-polish/design.md` D1（验证：D1 小节记录了每个图标的最终资源名）

## 2. NavList 共享组件与抽屉留白

- [x] 2.1 新建 `entry/src/main/ets/components/NavList.ets`（@ComponentV2，NAV_ITEMS 渲染、`TOP_INSET=26`、标签缩进统一 20vp、`@Event onSelect`）；重构 `entry/src/main/ets/components/NavigationRail.ets` 的 SideNav 与 `entry/src/main/ets/pages/Index.ets` 的 FolderDrawer 复用之，抽屉导航区随之获得 26vp 顶部留白；收尾 `check_ets_files`（三个文件）+ `hvigorw assembleHap`（验证：构建通过，grep 确认 Index.ets 与 NavigationRail.ets 不再有各自手写的 NAV_ITEMS ForEach）

## 3. PageHeader 与子页面侧边栏可达性

- [x] 3.1 新建 `entry/src/main/ets/components/PageHeader.ets`（@ComponentV2：可选返回、可选 ☰ 菜单按钮，`@Event onBack/onMenu`，宽屏下 ☰ 不渲染）；`entry/src/main/ets/pages/TagsPage.ets` / `SyncPage.ets` / `SettingsPage.ets` 换用 PageHeader，☰ 点击置 `appState.folderDrawerOpen = true`；收尾 `check_ets_files`（四个文件）+ `hvigorw assembleHap`（验证：构建通过，grep 确认三页无手写返回行残留）
- [x] 3.2 `entry/src/main/ets/pages/Index.ets` 的 `openPane()` 手机端改为清栈再进（流笺 → `clear`；其余 pane → `clear` + `pushPathByName`，对齐 `showDetailOnPhone` 写法）；收尾 `check_ets_files` + `hvigorw assembleHap`（验证：构建通过；栈行为在 7.1 设备端核对）

## 4. ☰ SymbolGlyph 化与图标/热区替换

- [x] 4.1 `entry/src/main/ets/components/StreamHome.ets`：☰ 改 SymbolGlyph（≥1000vp 按 `sideNavOpen` 映射 open_sidebar/close_sidebar，<1000vp 恒 open_sidebar，无障碍标签随动作变化）；「+ 收笺」改加号符号 + 文字、清除筛选「×」改关闭符号；收尾 `check_ets_files` + `hvigorw assembleHap`（验证：构建通过，grep 确认 accessibilityText 全保留）
- [x] 4.2 `entry/src/main/ets/components/BookmarkRow.ets`：「…」按钮改更多符号；`entry/src/main/ets/components/StreamHome.ets` QuickActionPanel「取消」等可视高度 <44vp 的点击入口补 `responseRegion` 扩到 44vp；收尾 `check_ets_files`（两文件）+ `hvigorw assembleHap`（验证：构建通过）

## 5. 抽屉出入场转场

- [x] 5.1 `entry/src/main/ets/pages/Index.ets` FolderDrawer：抽屉列加平移+淡入 `transition`、遮罩加淡入 `transition`（条件渲染不触发动画时回退 `getUIContext().animateTo` 包裹状态翻转）；验证拖拽路径（`beginDragFromBookmark` → 自动展开）命中不受影响；收尾 `check_ets_files` + `hvigorw assembleHap`（验证：构建通过；拖拽投放行为在 7.1 设备端核对）

## 6. 主交互点悬停/按压反馈

- [x] 6.1 按 `design.md` D7 为以下交互点加 `stateStyles` hovered/pressed 背景高亮（`surface_alt`）：NavList 导航行、StreamHome（☰、筛选 chips、排序、批量、收笺、清除筛选）、BookmarkRow（星标、更多）、PageHeader（返回、☰）；hovered 不生效处补 `.hoverable(true)`；阅读页内部不动；收尾 `check_ets_files`（涉及文件）+ `hvigorw assembleHap`（验证：构建通过；反馈效果在 7.1 设备端核对）
- [x] 6.2 修复反馈触发时机（用户实测反馈：按压后阴影残留、hover 误触发、chips 按压异常）：stateStyles 方案在 plain 组件上状态机不可靠，按官方按压阴影指南改为 `hdsEffect.pressShadow`（BLEND_WHITE）+ `visualEffect` + onHover/onTouch 状态机，Button 类先 `stateEffect(false)`；更新 design D7 与 specs/interaction-feedback 措辞；收尾 `check_ets_files`（四文件）+ `hvigorw assembleHap` + 设备端点击后 dump 验证背景层无残留（验证：构建通过、设备端点击各交互点后 backgroundColor 无污染、chips 选中背景保持）

## 7. 集成验证与文档

- [x] 7.1 设备端全量核对：按 `openspec/changes/sidebar-nav-polish/specs/navigation-shell/spec.md` 与 `specs/interaction-feedback/spec.md` 场景逐条目检三断点（手机：抽屉留白/子页 ☰/清栈返回主页/转场/按压反馈；700-999vp 两栏；≥1000vp：☰ 双态图标、悬停反馈、拖拽自动展开）；跑既有设备端套件（`hvigorw --mode module -p module=entry@ohosTest ... assembleHap` + `hdc shell aa test ...`）确认无回归；`codelinter -c code-linter.json5` 保持 0 error（验证：场景清单全部通过、测试套件通过、lint 0 error）
  - 实测记录（MateBook Pro 2in1，浮动窗三档宽度模拟三断点）：≥1000vp ☰ 双态切换停靠栏 ✓；<700vp 抽屉顶部留白 ≈26vp ✓、标签页头 ☰（44vp SymbolGlyph）+ 返回 + trailing ✓、页内开抽屉 ✓、抽屉切 pane 清栈（tags→sync→Back 直达主页）✓、拖拽书签自动展开抽屉 ✓；700-999vp 两栏 ☰ 开抽屉 ✓；测试套件 202/202 通过 ✓；codelinter 0 error ✓
  - 人工验收遗留（无法程序化注入）：悬停/按压反馈的帧级效果（uitest 无 hover 注入）、抽屉转场动效节奏、真机手机状态栏下的抽屉沉浸观感
- [x] 7.2 更新 `AGENTS.md` 易变事实：☰ SymbolGlyph 双态语义、抽屉 26vp 留白口径、子页面 ☰ 入口（detail 除外）、抽屉切换清栈语义、NavList/PageHeader 组件归属；以全量内链 grep 校对收尾（验证：grep 确认 AGENTS.md 引用的组件路径与规格路径真实存在）
