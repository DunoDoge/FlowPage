# Design

## Context

现状：应用窗口为默认非沉浸布局，各页面背景绘制止步于安全区边界，状态栏/导航条区域显示系统默认底色，与 paper 背景形成色带断层。用户要求背景沉浸适配顶部状态栏与底部导航条；需求澄清确认全屏沉浸 / 全应用统一 / 阅读层统一沉浸三个口径。经 SDD 流程（spec → plan → tasks → 实现 → build-only 验证）交付：3 个文件、6 处容器 `expandSafeArea` 扩展、共 +6 行，真机目视验证通过（commit `e0bb529`）。

约束（引用 AGENTS.md，不复制）：ArkTS 严格子集（禁 any/as）、主 UI 统一 V2 装饰器、颜色一律 `$r('app.color.*')` 成对维护、构建用 hvigorw（本仓库 devecocli build 不可用）、阅读链路性能预算不可劣化、`bindContentCover` + ReadingShell 阅读栈内存形态机不可破坏。

## Goals / Non-Goals

**Goals:**

- 系统栏区域（状态栏 + 导航条）透出应用背景色，整屏无系统栏默认底色边界（深浅色均成立）。
- 全部可交互内容不被系统栏遮挡，避让量由框架安全区机制管理，不硬编码、不手动计算 insets。
- 全应用统一：手机导航栈、宽屏两栏/三栏、标签/同步/设置、弹层（抽屉/收笺/遮罩）、分享页、阅读全屏层。
- 动态窗口形态（旋转/折叠/分屏/自由窗/三键栏切换）自动跟踪。
- 零 window API、零新增状态、零新文件、零资源变更，最小 diff。

**Non-Goals:**

- 内容真正布局/滚动到系统栏下方（如列表滚入状态栏后方）——本应用不需要，属全屏布局方案的语义。
- 隐藏系统栏（如阅读时隐藏状态栏）——用户已确认保持系统栏可见。
- 状态栏内容色手动设置与用户开关——依赖系统深浅色联动。
- 桌面卡片（widget 进程）适配——独立进程，不在范围。
- 业务逻辑/数据层/路由/权限任何变更。

## Decisions

### D1: 沉浸路线——组件安全区方案（expandSafeArea 绘制延伸），否决全屏布局与系统栏变色

在携带背景色的容器上应用 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`，仅延伸背景绘制到状态栏/导航条下方；布局系统保持安全区内布局，交互内容自动避让。

- 官方依据：沉浸式效果避让策略 FAQ（faqs-arkui-897）明确记载「组件安全区方案：布局系统保持安全区内布局，然后通过接口延伸绘制内容（如背景色）到状态栏和导航条区域实现沉浸式效果」；本应用全部界面为纯色背景、需求为「背景延伸 + 内容避让」，与该方案语义精确匹配。
- 收益：零避让高度计算（无 px→vp 换算）、零 avoidAreaChange 监听、零全局状态；动态形态由框架自动跟踪；不改 `bindContentCover` 既有语义；Tabs 自 API 11 起默认即此方案，可行性已被系统自身验证。
- 备选 A（全屏布局方案：`setWindowLayoutFullScreen(true)` + `getWindowAvoidArea` / `on('avoidAreaChange')` 换算 insets + 各页手动 padding + `enableSafeArea:false` + ReadingShell 内避让）：能力更强（内容可布局到系统栏下），但改动面大、需处理 px 单位与避让区监听、Navigation padding 传染、阅读层语义重建，风险与本需求不匹配。否决（保留为兜底 B，触发条件未满足）。
- 备选 B（仅 `setWindowSystemBarProperties` 把系统栏背景色设为 paper）：非真沉浸，仍有边界，用户在需求澄清中否决。

### D2: 状态栏内容色——依赖系统深浅色自动联动，不调 window API

不设置系统栏属性。应用颜色模式跟随系统，系统栏内容色默认随系统深浅色，与跟随系统的背景天然一致（浅色 paper → 深色图标；深色 paper → 浅色图标）。

- 备选（主动 `setWindowSystemBarProperties` 设内容色并监听 `onConfigurationUpdate` 重设）：维护成本高，验收以设备实测为准；仅当实测对比度不足时作为兜底 A 实施——真机目视验证图标清晰可读，未触发。

### D3: 扩展点清单——按「屏幕边缘处背景色 ≠ 根 paper」确定，否决逐页/全量扩展

`expandSafeArea` 是逐组件属性（父容器扩展不波及子容器背景），必须精确到每个在屏幕边缘呈现自有背景的容器：

1. Index 根 Stack（paper）：TOP+BOTTOM——一次覆盖手机导航栈全部 NavDestination（标签/同步/设置/详情）、宽屏两栏/三栏（SideNav/StreamHome/DetailContent 均 paper 同色）、启动占位。
2. FolderDrawer 抽屉列（paper + 右侧 1px 边框线）：TOP+BOTTOM——背景与边框线贯通至屏幕上下缘；抽屉导航内容仍在安全区。抽屉遮罩（overlay）：TOP+BOTTOM——抽屉打开时状态栏/导航条区域同步压暗。
3. InboxSheet 底部面板（surface，上圆角）：仅 BOTTOM——消除面板下缘与导航条区域 paper 的色差接缝；面板内容与圆角不变。全屏遮罩（overlay）：TOP+BOTTOM。
4. SharePage 根 Column（paper，ShareAbility 独立窗口）：TOP+BOTTOM。

- 备选 A（Tags/Sync/Settings/Detail 等逐页扩展）：paper 同色下无视觉差异，徒增冗余维护点。否决。
- 备选 B（全部容器统一扩展）：过度工程。否决。
- 实施注记：抽屉列的 paper 与根 Stack 同色，其扩展的必要性在于右侧 1px 边框线（`app.color.line`）须贯通至屏幕上下缘——真机目视验证边框线贯通成立，该处扩展判定非冗余。

### D4: 阅读全屏层——保留 bindContentCover `enableSafeArea: true`，ReadingShell 零改动

不改 ReadingShell 与 bindContentCover 配置。覆盖层内容继续由 `enableSafeArea: true` 保留在安全区（TopBar 在状态栏下方、正文在导航条上方）；系统栏区域透出底层根 Stack 扩展后的 paper，与 ReadingShell 自身 paper 同色无缝。

- 收益：阅读交互（目录/进度/位置恢复/搜索/链接下钻/收藏这一页/阅读栈内存形态机）零风险，性能预算零威胁。
- 备选（`enableSafeArea: false` + ReadingShell 内手动避让）：需 insets 管线，风险高收益零（本应用不需要内容延伸到系统栏下）。否决。

### D5: 验证门禁——遵循仓库特殊约束

构建用 `hvigorw assembleHap`（本仓库 devecocli build 因 modelVersion 26.0.0 不可用）；静态检查先 `check_ets_files` 再 `codelinter -c code-linter.json5`；部署用 `devecocli run --skip-build`（或 hdc install）；UI 实证为沉浸式唯一可靠验收手段（目视/截图：系统栏区域颜色 == 应用背景色、无边界带），由用户真机完成（HUAWEI MateBook Pro，通过）。

## Risks / Trade-offs

- **风险**：`bindContentCover` 在沉浸布局后的避让语义变化——实测 `enableSafeArea: true` 语义不变，阅读层无缝承接，未发生。
- **风险**：批量模式/跨列拖拽/文件夹抽屉命中区域受根部 padding 影响——本方案不加任何 padding（内容避让由框架安全区管理），命中区域不变。
- **Trade-off**：系统栏区域不可承载交互内容（绘制延伸 ≠ 布局延伸）——本应用无此需求，接受。
- **Trade-off**：状态栏图标对比度依赖系统联动而非主动控制——实测清晰可读；兜底 A 保留触发条件。

## Migration Plan

纯属性级 UI 改动，无数据/接口迁移；一次提交（`e0bb529`）直接生效，无渐进开关需求。

## Open Questions

（无——沉浸策略/范围/阅读层三个口径已在需求澄清确认；状态栏内容色对比度经真机目视验证通过，兜底 A 未触发。）
