# Tasks

## 1. 共享基础（保持现有行为）

- [x] 1.1 把 `NAV_ITEMS` 从 `entry/src/main/ets/components/NavList.ets` 提升到公共常量模块，`NavList` 与后续页签共用同一份目的地定义；验证停靠栏仍渲染四项且顺序不变；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 1.2 把筛选所有权收进 `entry/src/main/ets/common/AppState.ets` 的 `homeFilter`，删除 `entry/src/main/ets/components/StreamHome.ets` 的本地 `filter`，所有读写改为 `appState.homeFilter`；验证筛选 chips、`FolderPanel` 的批量判断与列表重载行为不变；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 1.3 给 `entry/src/main/ets/components/NavList.ets` 增加显隐参数，默认保持显示；分别以显示/隐藏两种参数渲染，验证导航项数量与选中竖线正确；以 `check_ets_files` + `hvigorw assembleHap` 收尾。

## 2. 手机悬浮页签（<700vp）

- [x] 2.1 改造 `entry/src/main/ets/pages/Index.ets` 的 `PhoneShell`：`Navigation` 外层保留，内容改为四项 `Tabs`，`PageMap` 只保留 `detail`，`openPane` 在手机端只写 `appState.pane`；验证四个页签可切换、详情可打开并盖住页签；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 2.2 在 `Index` 中建立 `Tabs.index` 与 `appState.pane` 的双向一致（`@Monitor` + `onChange`），并扩展 `onBackPress`：导航栈为空且 pane 非 `DETAIL` 时回到「流笺」；验证从设置页签按返回回到流笺、详情页返回回到原页签、页签切换不增长导航栈；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 2.3 调整 `entry/src/main/ets/pages/TagsPage.ets`、`SyncPage.ets`、`SettingsPage.ets` 顶层化后的页头：手机页签内不显示返回与 ☰；删除 `entry/src/main/ets/components/PageHeader.ets` 中失去调用方的参数与注释；验证三个页签页头无返回/☰、内容完整；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 2.4 给手机列表与详情尾部增加页签高度对应的底部内边距（仅在页签可见时生效）；滚动主页与详情到底部，验证最后一行操作区/末尾正文不被页签或导航条遮挡；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 2.5 实现 <700vp 批量态隐藏页签、由 `BatchActionBar` 接管底部；验证进入批量后页签消失、批量栏完整可见，退出批量后页签恢复；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 2.6 为页签补齐无障碍标签与选中态语义；用 `uitest dumpLayout` 或读屏验证每个页签可读出名称与选中状态；以 `check_ets_files` + `hvigorw assembleHap` 收尾。

## 3. 平板右栏页签（700–999vp）

- [x] 3.1 改造 `entry/src/main/ets/pages/Index.ets` 的 `WideShell`：右栏包四项 `Tabs`，左栏 `StreamHome` 保持单实例；验证切页签前后左栏列表滚动位置、筛选与选中行不丢失；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 3.2 给右栏四个页面增加页签可见时的底部内边距；把标签页、同步页、设置页分别滚到底，验证末尾内容不被页签遮挡；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 3.3 在 2in1 上把窗口缩到 <700vp 再拉回 700–999vp，验证页签位置、材质无效果时的样式、左栏状态与返回语义均正确；以 `check_ets_files` + `hvigorw assembleHap` 收尾。

## 4. 资料库侧栏

- [x] 4.1 改造 `entry/src/main/ets/pages/Index.ets` 的 `FolderDrawer` 与 `entry/src/main/ets/components/NavigationRail.ets`：抽屉隐藏 `NavList`，停靠栏保留；验证 <1000vp 抽屉只有资料库、≥1000vp 停靠栏仍有四项导航；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 4.2 新增智能视图组件（全部/未读/星标/归档/回收站 + 计数），读取 `FlowRepository.summary()` 并写 `appState.homeFilter`；验证点击「未读」后列表筛选、批量退出、抽屉关闭、目的地切回流笺；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 4.3 把智能视图接入手机抽屉与大屏停靠栏，保持手机抽屉只含智能视图 + 文件夹树；验证抽屉滚动顺畅、文件夹树展开集合与滚动位置不被压缩或重置；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 4.4 在 ≥1000vp 停靠栏新增标签分区（名称 + 计数，选择后筛选列表并保持列表列可见），随 `refreshTick` 刷新；验证新增/改名标签后侧栏立即更新；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 4.5 在 ≥1000vp 停靠栏新增同步状态摘要（是否已配置、上次同步相对时间、进入同步页入口），同步完成后刷新；验证配置前/后与同步完成后的三种显示状态；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 4.6 按 `interaction-feedback` 规格给智能视图行、标签行、页签补齐 `surface_alt` 悬停/按压反馈与 Symbol 图标；验证反馈随指针离开/抬手消失、选中态不被覆盖；以 `check_ets_files` + `hvigorw assembleHap` 收尾。

## 5. 悬浮材质与安全区

- [x] 5.1 在页签上启用 `barOverlap(true)`、`barPosition(BarPosition.End)`、`vertical(false)` 与 `barFloatingStyle` 的 `uiMaterial.ImmersiveMaterial`；先沿用系统默认蒙层色与默认分档宽度，真机验收后再微调；验证浅色/深色下胶囊、蒙层与选中态均清晰；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 5.2 校准页签与根容器 `expandSafeArea` 的叠加：分别在手势导航与三键导航下测量底部留白；验证最后一行可见且无双倍留白；以 `check_ets_files` + `hvigorw assembleHap` 收尾。（HdsTabs 迁移后本项并入任务 8.6 重校）
- [x] 5.3 验证批量态隐藏页签的动画；若 `barHeight(0)` + 取消悬浮样式残留蒙层，则按 design.md 的兜底改为批量栏浮在页签上方；以 `check_ets_files` + `hvigorw assembleHap` 收尾。

## 6. 文档与整体验收

- [x] 6.1 更新 `AGENTS.md` 的导航模型、断点矩阵、侧栏分区与材质作用域事实，按仓库惯例保留易变数字的单一维护点；以全量内链 `grep` 校对文档链接收尾。
- [x] 6.2 做一次全断点人工走查（<700 / 700–999 / ≥1000，浅色/深色，手势/三键，2in1 窄窗），并测量冷启动耗时与阅读页回归；记录在变更内，确认无启动明显回归与阅读性能变化。
- [x] 6.3 运行 `codelinter -c code-linter.json5`，确认无新增 error；把结果随变更记录。

## 7. 真机反馈修订（页签贴底 + 筛选入口收敛）

- [x] 7.1 移除 `entry/src/main/ets/components/StreamHome.ets` 的筛选 chips 行及 `FILTERS` / `selectFilter` / chips hover-press 状态，筛选入口收敛到资料库智能视图；`appState.homeFilter` 监听与 `BatchActionBar` / 空态的回收站判断保留；验证抽屉与停靠栏智能视图筛选联动不变；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 7.2 显式收紧页签 `barBottomMargin` 贴底（候选 8vp，真机微调），保持根容器单点 `expandSafeArea`；手势与三键导航下验证无双倍留白、末行可见；以 `check_ets_files` + `hvigorw assembleHap` 收尾。（HdsTabs 迁移后 `barBottomMargin` 口径失效，并入任务 8.6 重校）
- [x] 7.3 更新 `AGENTS.md` 筛选入口与页签贴底事实；复跑 `codelinter -c code-linter.json5` 确认无新增 error。

- [x] 7.4 修复冷启动资料库竞态：抽屉常驻挂载的 `SmartViews`/`FolderPanel`（及停靠栏 `TagSection`/`SyncSection`）在仓库 init 完成前发起查询导致智能视图计数为 0、树卡加载态；新增 `AppState.libraryReady` 门控（`aboutToAppear` + `@Monitor`），`Index.initRepository` 置位；真机复验冷启动计数即时正确、页签页无异常延迟；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 7.5 按 design.md D11 落地目的地切换进场过渡：`entry/src/main/ets/pages/Index.ets` 给 <700vp 与 700–999vp 页签与 ≥1000vp 右栏 pane 加「落纸」进场（opacity + translateY 12vp、240ms、`Curve.FastOutSlowIn`，状态驱动隐式 `.animation()` 实现，勿用 `TransitionEffect` 挂条件渲染内容；已挂载页签间切换需重触发进场，不能只靠首次挂载；`Tabs.animationDuration(0)` 关闭默认横滑）；验证每次切换（冷与热）均有过渡且无左右滑动、≥1000vp 每次切换有过渡、启动首屏不播过渡；以 `check_ets_files` + `hvigorw assembleHap` 收尾。

## 8. 真机反馈修订（页签迁移 HdsTabs + 资料库迷你栏）

- [x] 8.1 先做 HdsTabs 嵌套原型（`Navigation` 内 <700vp、右栏 `Row` 内 700–999vp）验证布局、事件与返回键行为，通过后把 <700vp 与 700–999vp 页签从原生 `Tabs` 迁移到 `@kit.UIDesignKit` 的 `HdsTabs`：controller 换 `HdsTabsController`，index↔pane 双向一致、自绘页签 item、默认横滑关闭与 D11 进场过渡、无障碍语义逐项等价恢复；验证四页签切换、详情覆盖、返回语义不回归；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.2 材质迁移：HdsTabs `systemMaterialEffect` 用默认 ADAPTIVE 档（PC/2in1 免 `getSystemMaterialTypes()` 查询），材质仍只作用于页签栏与迷你栏背板；验证浅色/深色背板、2in1 窄窗材质降级时样式成立；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.3 按 design.md D12 配置「资料库」迷你栏：`miniBarBuilder` 自绘入口（仅 `SymbolGlyph` 侧栏图标、26fp、无文字——真机反馈修订，宽度分档用系统默认），图标镜像抽屉状态（打开显 `open_sidebar`、收起显 `close_sidebar`，与 ☰ 状态映射约定一致），点击切换抽屉开合、直接复用现有 `FolderDrawer`；验证折叠/展开形态下均可开门、抽屉行为（遮罩、点外部关闭、智能视图选择后切回流笺）不回归；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.4 删除 `entry/src/main/ets/components/StreamHome.ets` 头部 ☰ 的 <1000vp 分支（`folderDocked` 分支保留），<1000vp 头部改用与页签页同构的 `PageHeader`（计数副题移入 trailing 状态槽）使 34fp 标题顶边与「标签/同步/设置」页对齐（真机反馈修订）；验证 <1000vp 无 ☰ 且资料库唯一入口为迷你栏、≥1000vp ☰ 切换停靠栏不变；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.5 批量态隐藏迁移：优先 `HdsTabsController.applyHideAnimation()`（页签与迷你栏整体隐藏），语义不等价则沿用高度归零兜底；验证 <700vp 进入/退出批量动画干净、`BatchActionBar` 接管底部、700–999vp 迷你栏不受批量影响；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.6 在 HdsTabs 载体上重做贴底与安全区校准（并入原 5.2 / 7.2 口径；2026-11-09 真机反馈追加：主页列表未延伸到屏幕底部——页签/迷你栏背板与导航避让区之下透出 paper 底色带，须让页签宿主内容链延伸进底部安全区、列表在页签与导航区之下滚动至屏幕底缘，并按安全区实际高度重校 `barBottomMargin`，见 design.md D10 修订）：手势与三键导航下验证页签+迷你栏组合贴底、列表延伸至底缘无色带截断、无双倍留白、末行可见；`TAB_BOTTOM_RESERVE` 覆盖组合高度；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.7 迷你栏无障碍：入口可读出「资料库」名称与打开抽屉的动作语义，热区不小于 44vp；用 `uitest dumpLayout` 或读屏验证；以 `check_ets_files` + `hvigorw assembleHap` 收尾。
- [x] 8.8 更新 `AGENTS.md`（☰→迷你栏、HdsTabs 依赖与断点事实）；复跑 `codelinter -c code-linter.json5` 确认无新增 error。

## Workflow follow-up

- 评审通过后归档变更，并按仓库流程把 delta 合入 `openspec/specs/`。
- 归档后复核 `AGENTS.md` 与主规格是否一致。
