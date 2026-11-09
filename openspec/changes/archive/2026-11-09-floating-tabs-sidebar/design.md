# Design

## Context

现状与约束见 `AGENTS.md` 与 `proposal.md`。影响本设计的关键事实：

- 当前手机壳层是 `Navigation(navStack)` + 自绘 header，`openPane()` 通过 `pushPathByName('tags'|'sync'|'settings')` 实现目的地切换；`detail` 是唯一需要栈语义的页面。
- 宽屏是 `Row[SideNav | StreamHome | 右栏]`，700–999vp 没有停靠栏，目的地切换依赖抽屉。
- `AppState.pane` 已是宽屏右栏与抽屉导航的单一事实源；`AppState.homeFilter` 目前只有 `StreamHome` 单向写入。
- 根 Stack 用 `expandSafeArea` 做沉浸式背景延伸，内容由安全区保证避让；已有 `immersive-ui` 规格约束。
- API 26 起原生 `Tabs` 支持 `barFloatingStyle`，可直接获得悬浮背板与 `uiMaterial.ImmersiveMaterial`，且材质在不支持设备上自动无效果。

## Goals / Non-Goals

**Goals:**

- 在不复制 `StreamHome` 实例的前提下，让三档断点各自拥有稳定的目的地切换方式。
- 让页签、停靠栏、抽屉共享同一份目的地与资料库状态，避免两套导航真相。
- 把悬浮材质限制在页签背板，保持正文与列表的纸面观感。

**Non-Goals:**

- 不启用智感握姿（`adaptToHandedness`）；HdsTabs / MiniBar 于 2026-11-09 修订引入（见 D1、D12）。
- 不改变阅读层、分享页、桌面卡片的内部结构。
- 不做内容区材质化、不做背景模糊叠加。
- 不改变标签、同步、设置页的功能与文案。

## Decisions

### D1. 页签使用原生 `Tabs` + `barFloatingStyle`，不用 `HdsTabs`

- 选择：`Tabs({ barPosition: End })` + `barOverlap(true)` + `vertical(false)` + `barFloatingStyle({ barBottomMargin, systemMaterial })`。
- 理由：`barFloatingStyle` 正好是 API 26 能力，具备 `barWidth / barSideMargin / barBottomMargin / maskColor / maskHeight / systemMaterial`；`uiMaterial` 在不支持设备上可设置但无效果，无需能力分支。
- 备选与否决：`HdsTabs`（MiniBar、半屏居中对齐、`hdsMaterial`）需要 `@kit.UIDesignKit`，且 `SystemMaterialParams` 在 PC/2in1 需先 `getSystemMaterialTypes()`；本变更不需要 MiniBar，收益不抵依赖与分支成本。
- 真机校准（2026-11-07 反馈）：默认 `barBottomMargin` 在手机上偏高（页签有悬空感），显式收紧为最小呼吸位（候选 8vp，真机微调）；蒙层色与分档宽度仍用系统默认。
- 修订（2026-11-09）：推翻初版否决，页签载体换用 `@kit.UIDesignKit` 的 `HdsTabs`——资料库入口下沉到常驻迷你栏（见 D12）后，官方 MiniBar 的折叠展开动效、页签栏-迷你栏自适应布局与 HDS 材质正好承接，自绘伴随胶囊的对齐/避让成本反超依赖成本；材质走 `systemMaterialEffect` 默认 ADAPTIVE 档（PC/2in1 免 `getSystemMaterialTypes()` 查询）。原否决理由中的依赖成本已接受，嵌套位形风险转记 Risks；上述 `barBottomMargin` 贴底口径在 HdsTabs 参数体系下重定位（并入任务 8.6）。

### D2. 手机壳层保持 `Navigation` 在外、`Tabs` 在内

- 选择：`Navigation(navStack) > Tabs(4)`，`navStack` 只 push `detail`；`PageMap` 删除 tags/sync/settings 分支。
- 理由：改动最小，详情天然覆盖页签，返回栈退回原页签；`openPane()` 退化为写 `AppState.pane`。
- 备选与否决：Tabs 在外、每个 Tab 一套 `NavPathStack`——四套栈与跨 Tab 跳转/返回语义复杂，且现有单栈契约要整体推翻。

### D3. 700–999vp 的 `Tabs` 只包右栏

- 选择：`Row[ StreamHome 340 | Tabs(右栏四页) ]`，页签在右栏底部居中。
- 理由：`StreamHome` 只实例化一次，列表状态与滚动位置不因页签切换重建；批量栏在左栏、页签在右栏，互不遮挡。
- 备选与否决：`Tabs` 包整个 Row——四个 `TabContent` 会各建一份 `StreamHome`，产生四份列表与四次查询；退化为单栏布局——放弃现有平板两栏体验。

### D4. `AppState.pane` 仍是唯一事实源，`navStack` 只保留 detail

- 选择：`Tabs.index` 由 `@Monitor('appState.pane')` 推导，`onChange` 只写 `goPane()`；`openPane()` 在 <1000vp 不再操作导航栈。
- 理由：页签、停靠栏、`TagsPage.pick()`、深链 `openBookmark()` 都继续写 `pane`，无需新建第二套状态；返回语义集中在 `Index.onBackPress`。
- 备选与否决：单独维护 `tabIndex` 再与 `pane` 双向同步——两套状态容易发散，且 `TagsPage` 等既有入口需要额外改写。

### D5. 抽屉只放资料库，`NavList` 只保留在 ≥1000vp 停靠栏

- 选择：给 `NavList` 增加显隐参数；`FolderDrawer` 不再渲染 `NavList`；`SideNav` 继续渲染。
- 理由：有页签的地方页签承担目的地，抽屉承担资料库；避免手机出现两套完全相同的四项导航。
- 备选与否决：抽屉继续保留 `NavList`——与页签完全重复，且 `navigation-shell` 的"子页面可开侧边栏"语义会更混乱。

### D6. 目的地定义提升为共享常量

- 选择：把 `NavList.ets` 的 `NAV_ITEMS` 移到公共常量，页签与停靠栏共用；页签用 `SymbolGlyph + 文字`，停靠栏保持纯文字。
- 理由：规格要求页签与侧栏同源；图标让胶囊更易扫视，纯文字停靠栏保留现有克制风格。
- 备选与否决：页签纯文字——更像分段控件，缺少快速识别锚点；停靠栏也加图标——改动现有视觉且无明确收益。

### D7. `homeFilter` 所有权收进 `AppState`

- 选择：`StreamHome` 删除本地 `filter`，读写 `appState.homeFilter`；侧栏智能视图写同一字段；`selectFilter()` 继续负责退出批量与重载。
- 理由：侧栏与列表共享一个事实源，避免"点了侧栏列表不动"；也消除 `FolderPanel` 已经在读、`StreamHome` 却不监听的隐性不一致。
- 备选与否决：保留本地 `filter` 再加 `@Monitor` 反向同步——两条写路径容易产生回环与重复重载。
- 真机反馈跟进（2026-11-07）：主页筛选 chips 行随智能视图落地而移除，`StreamHome` 只读 `homeFilter`（`@Monitor` 负责重载与退批量），`selectFilter()` 与 chips 的 hover/press 状态删除；退批量与关弹层由智能视图 `pick()` 承担。

### D8. 批量态隐藏页签

- 选择：<700vp 进入批量选择时把页签高度动画到 0 并取消悬浮样式，由 `BatchActionBar` 接管底部；退出批量后恢复。
- 理由：避免两个底部栏叠在一起；符合"上下文操作栏替换导航栏"的常见心智。
- 备选与否决：让批量栏浮在页签上方——视觉拥挤且压缩列表空间；把批量操作改成半模态——改变现有高效多选流程。
- 待验证：`barHeight(0)` 与 `barFloatingStyle(undefined)` 的组合动画是否干净；若残留蒙层，兜底为"批量栏浮在页签上方"。
- 修订（2026-11-09）：迁移 HdsTabs 后，隐藏动效优先用 `HdsTabsController.applyHideAnimation()`（页签栏与迷你栏整体隐藏）；若语义不等价（不可逆、不含迷你栏等）则沿用高度归零思路兜底。见任务 8.5。

### D9. 材质只用在页签背板

- 选择：`uiMaterial.ImmersiveMaterial({ style: THIN, colorInvert: true, interactive: true })`；`maskColor` 向 paper 色微调，避免底部出现冷灰带。
- 理由：材质是稀缺视觉资源，页签面积小、层级明确；正文与列表保持纸面，维护现有产品气质。
- 备选与否决：应用级 `UIMaterial.state = enable`——会让所有弹窗/菜单默认材质化，超出本变更范围，另立变更评估；HDS 材质——见 D1。
- 修订（2026-11-09）：载体随 D1 换为 HdsTabs `systemMaterialEffect`，默认 ADAPTIVE 档按设备算力自适应，免 PC/2in1 材质查询；材质仍只作用于页签栏与迷你栏背板。

### D10. 安全区沿用根容器单点扩展

- 选择：根 Stack 继续 `expandSafeArea`；页签的 `barBottomMargin` 从底部安全区起算，内容侧只在页签可见时加一份内边距。
- 理由：维持 `immersive-ui` 的"背景延伸、内容避让"不变量；避免页签自己再扩展一次造成双倍留白。
- 备选与否决：给 `Tabs` 单独 `expandSafeArea`——与根扩展叠加，手势条/三键栏切换时容易出现双倍避让。
- 修订（2026-11-09）：`barBottomMargin` 口径随 HdsTabs 迁移失效，贴底与双倍留白校准在 HdsTabs 布局/分档参数下重做（任务 8.6）。
- 修订（2026-11-09 真机反馈）：主页列表未延伸到屏幕底部——页签与迷你栏背板之下（含底部导航避让区）只有根 Stack 的 paper 底色，列表内容不进入页签之下，材质背板无内容可透，观感呈不透明色带截断（先前误记为「迷你栏背景不透明」）。修复口径：页签宿主的内容链须延伸进底部安全区，主列表在页签背板与系统导航区之下滚动至屏幕底缘；「背景延伸、内容避让」不变量在页签宿主内放宽为「列表延伸至底缘 + 末行靠 `TAB_BOTTOM_RESERVE` 内边距保证可见」，原否决理由（双倍避让）改由按安全区实际高度重校 `barBottomMargin` 化解——避让只发生在页签定位，不再发生在内容链。真机校准并入任务 8.6（手势/三键两种导航均须复验）。

### D11. 目的地切换统一播放单向「落纸」进场

- 选择：每次目的地切换（<1000vp 页签、≥1000vp 停靠栏右栏）都播放一次进场过渡——opacity 0→1 + translateY 12vp→0、240ms、`Curve.FastOutSlowIn`，与抽屉动画同一套词汇；冷激活与已挂载页签间切换不区分，统一播放；应用启动首屏（初始 pane）直出不播。实现走状态驱动隐式 `.animation()`，不用 `TransitionEffect` 挂条件渲染内容（抽屉实测面板本体不动画的教训）；`Tabs.animationDuration(0)` 显式关闭默认 300ms 横滑。
- 理由：页签属鸿蒙转场框架的同层级场景，规范手法是单向淡入淡出（无出场元素可交叉）；方向中立的上浮「落纸」不暗示页签有左右顺序；冷热两种观感并存（冷有过渡、热硬切）在走查中读作「行为不一致」而非「效率优势」，统一节奏更稳；240ms 落在局部运动 200–300ms 带内且与 `DRAWER_DURATION` 同值。
- 备选与否决：`Tabs.animationDuration` 横滑——上下层级隐喻错配、受控 index（pane→Monitor 回写）易与滑动互相打架，且默认 300ms 横滑会与进场叠加（模拟器实测），已显式置 0；冷热区分（仅冷激活播）——初版方案，走查后冷热观感不一致，按下述反馈推翻；交叉淡入淡出——需要新旧两页同时存活，与 `visitedTabs` 惰性门控结构性冲突；列表逐项 stagger 进场——三个页面各自实现、拖慢感知加载，违背纸面克制；启动后空闲预热挂载——动画统一后只剩「消除冷挂载空白段」一个收益，若复测该段变主因再评估。
- 真机反馈跟进（2026-11-09）：初版仅冷激活播放、热切换瞬时；另实测发现 `Tabs` 默认 300ms 横滑会先于进场动画出现，已显式 `animationDuration(0)` 关闭。按走查反馈改为每次切换统一播放。
- 修订（2026-11-09）：进场过渡在 HdsTabs 载体上需等价恢复（含默认横滑关闭），复验口径不变（任务 8.1）。

### D12. 「资料库」迷你栏：HdsTabs MiniBar 承载资料库入口

- 选择：为 <1000vp 的 HdsTabs 配置迷你栏：`miniBarBuilder` 自绘单一「资料库」入口（`SymbolGlyph` 侧栏图标 + 「资料库」文字），宽度分档沿用系统默认（上限 328vp）；点击（无论折叠或展开形态）直接打开现有左侧资料库抽屉，折叠/展开只是空间自适应的视觉形态，不构成独立交互步骤；抽屉行为维持既有规格（遮罩、点外部/返回关闭，智能视图选择后切回流笺并关抽屉）。`<700vp` 迷你栏伴随窗口底部页签，`700–999vp` 伴随右栏页签（接受「右栏底部入口 → 左侧抽屉 → 左栏列表变化」的跨栏错位，换取 <1000vp 入口规则统一）；`≥1000vp` 不配置迷你栏，停靠栏直达资料库。主页头部 ☰ 删除 <1000vp 分支（≥1000vp 保留切换停靠栏展开/收起）。<700vp 批量态迷你栏随页签一起隐藏；700–999vp 批量栏在左栏，迷你栏不动。
- 修订（2026-11-09 真机反馈）：迷你栏入口去「资料库」文字，仅保留 `SymbolGlyph`（26fp，较页签 22fp 适当放大）；图标镜像抽屉状态——打开显 `open_sidebar`、收起显 `close_sidebar`，与 ☰ 的状态映射约定一致（navigation-shell 规格；初稿的动作语义映射经真机确认反直觉，已交换），点击开合切换抽屉；`StreamHome` 头部 <1000vp 改用与页签页同构的 `PageHeader`（计数副题移入 trailing 状态槽），34fp 标题顶边与「标签/同步/设置」页对齐（≥1000vp 副题随 ☰ 行 trailing 呈现）。
- 修订（2026-11-09 真机反馈·折叠屏）：HdsTabs 宽度 >600vp 时迷你栏初始为展开样式、分档宽度向 328vp 上限膨胀，单图标入口被拉宽。迷你栏固定为紧凑圆形：`miniBarStyle: COLLAPSE` + `miniBarWidth` 三档全部钉住页签栏高度（56×56 圆）；样式初始化参数仅在 <600vp 生效，宽度钉住覆盖其余分档。折叠/展开不再作为空间自适应形态保留——单一图标无需展开态。
- 理由：入口下沉到常驻底部后，「标签 / 同步 / 设置」页签下也能打开资料库（现状仅在流笺页头可达）；抽屉、拖拽会话、智能视图联动全部复用，无资料库交互重做；官方折叠展开动效与分档布局免自绘对齐。
- 备选与否决：资料库升格第五页签——与「页签与停靠栏同源四项」规格冲突，≥1000vp 连带加第五项；迷你栏原地展开资料库面板——328vp 容不下文件夹树与跨列拖拽会话，资料库交互全部重做；页头 ☰ 与迷你栏并存——重复入口，违背入口唯一。

## Risks / Trade-offs

- [`Tabs` 一次性构建全部 `TabContent`，`TagsPage` / `SyncPage` 在启动时就初始化] → 先测量冷启动；若回归明显，给未访问页签加"首次激活后再挂载"的门控，挂载后保持存活。
- [`barOverlap` 与根安全区叠加导致双倍底部留白] → 在真机分别测手势条与三键栏；以内容末行可见且无额外空白为验收。
- [2in1 窗口缩到 <700vp 会走页签分支] → 在 2in1 上做一次窄窗走查，确认材质无效果时样式仍成立（背景、圆角、阴影）。
- [批量态隐藏页签的动画不干净] → 按 D8 的兜底方案降级。
- [抽屉新增固定分区压缩文件夹树空间] → 手机抽屉只放智能视图 + 文件夹树；标签与同步状态仅大屏。
- [拖拽投放依赖抽屉自动展开与文件夹区滚动] → 保持 `FolderPanel` 现有内部滚动与 `maybeAutoScroll`，新增分区不得再外套滚动容器。
- [移除三个导航栈子页会影响既有设备端用例] → 同步更新 `entry/src/ohosTest` 中涉及手机导航栈与抽屉切换的套件。
- [`PageHeader` 的 ☰ 参数失去调用方] → 评估后删除无用参数，避免留下死代码与误导性注释。
- [手机端换筛选需先开抽屉，比原 chips 多一跳] → 真机体验后用户决策接受，换取主页聚焦与入口唯一；`BatchActionBar` 与空态的回收站判断已读 `appState.homeFilter`（任务 1.2），不受 chips 移除影响。
- [≥1000vp 右栏为条件渲染，每次切换重挂页面并丢失页内滚动位置] → 本变更先以 D11 进场过渡软化观感；「惰性挂载+常驻」改造（`StreamHome` 同款收益）另立变更评估。
- [HdsTabs 官方推荐作 Page 根容器，本方案嵌在 `Navigation` 内（<700vp）与右栏 `Row` 内（700–999vp）] → 先做嵌套原型验证布局、事件与返回键行为，再全面迁移；此为迁移的硬性前置验证点（任务 8.1）。
- [原生 Tabs 既有配置迁移回归（自绘页签 item、`animationDuration(0)`、批量隐藏、贴底、无障碍语义）] → 任务 8.1 逐项等价恢复，全断点走查兜底。
- [`applyHideAnimation` 语义未验证（是否含迷你栏、是否可逆）] → 任务 8.5 验证，不等价则高度归零兜底。
- [PC/2in1 材质能力差异] → `systemMaterialEffect` 用默认 ADAPTIVE 档免查询；2in1 窄窗走查无材质时样式仍成立。

## Migration Plan

1. 先落共享 `NAV_ITEMS` 与 `homeFilter` 所有权，保持现有 UI 行为不变。
2. 落 <700vp 页签与抽屉资料库化，跑设备端导航套件。
3. 落 700–999vp 右栏页签，重点验列表状态保持与批量栏位置。
4. 落侧栏扩展分区，验计数联动、标签筛选与同步状态刷新。
5. 更新规格与 `AGENTS.md`，最后做一次全断点人工走查。
6. 真机反馈修订（2026-11-09）：页签迁移 HdsTabs 并落资料库迷你栏——先嵌套原型验证，再迁移 <700vp、后 700–999vp，最后删主页 ☰ 的 <1000vp 分支并复验批量态、贴底与进场过渡（任务 8.x）。

回滚按断点逐层回退：700–999vp 页签、<700vp 页签、侧栏扩展相互独立；共享常量与 `homeFilter` 改动不依赖页签，可保留。HdsTabs 迁移失败可回退原生 Tabs（barFloatingStyle 配置在 git 历史中）。

## Open Questions

- 页签蒙层是否需要显式改为 paper 色调，还是沿用系统默认的 `#CCF1F3F5` / `#99000000`。
- 页签在 700–999vp 右栏内的具体最大宽度是否需要限制，还是交给悬浮样式分档（迁移前 `barFloatingStyle`、迁移后 HdsTabs 分档）的默认规则。
- 迷你栏分档宽度是否需要显式配置（`HdsBarWidthRangeOptions`），还是沿用系统默认。
- 迷你栏折叠/展开的驱动方式（系统布局自适应 vs 显式 `applyMiniBarStyle`）待原型确认；D12 假设折叠/展开不构成独立交互步骤。
