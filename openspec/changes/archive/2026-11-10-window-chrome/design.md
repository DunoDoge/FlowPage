# Design

## Context

- 现状：`EntryAbility.onWindowStageCreate` 仅 `loadContent('pages/Index')`，未触碰任何窗口装饰 API；≥1000vp 的 ☰ 位于 `StreamHome` 头部首行（`entry/src/main/ets/components/StreamHome.ets:750` 起，含尾部计数副题 SubtitleStatus）；断点经 `mediaquery.matchMediaSync('(width>=700vp/1000vp)')` 动态驱动（`entry/src/main/ets/pages/Index.ets:167`），自由窗缩放时 `isLarge` 自动更新。
- 沉浸式现状为组件安全区方案（`expandSafeArea`），自由窗内无系统栏安全区，根 Stack 的 `expandSafeArea` 自动 no-op，无需适配。
- 系统能力（均经 `devecocli docs` 核实，所需最高 API 22，项目 API 26 覆盖）：`setWindowDecorVisible`（非自由窗自动无效）、`setWindowDecorHeight`（37–112vp）、`setWindowTitleButtonVisible`、`setDecorButtonStyle`、`setWindowTitleMoveEnabled` + `startMoving`（须在 onTouch 回调内调用）、`isInFreeWindowMode` + `on('freeWindowModeChange')`、`getWindowStatus` + `on('windowStatusChange')`、`getTitleButtonRect` + `on('windowTitleButtonRectChange')`、`maximize`/`minimize`/`recover`、`setWindowTitle`。
- 官方 HDS 电脑端设计推荐「应用工具栏与窗口标题栏合一」，标题栏高度档位 40/56/64/72vp。

## Goals / Non-Goals

**Goals:**

- 自由窗窗口 chrome 与应用 paper 视觉统一，且 ≥1000vp 把 ☰ 与计数副题收进标题条、少占一行内容空间。
- 窗口控制（三键）始终可达：任意自由窗尺寸、最大化、真全屏（hover 悬浮栏）、阅读全屏层（decor 层天然不被覆盖）。
- 状态切换（浮动/最大化/真全屏/退出）不丢内容状态。

**Non-Goals:**

- 不自绘窗口控制按钮（最大化/最小化/关闭），不做窗口按钮的样式重造。
- 不触碰阅读链路（`bindContentCover` 不变量、ReadingShell）、同步、卡片、ShareAbility（系统分享面板宿主）。
- 阅读专注模式（ENTER_IMMERSIVE 真全屏阅读）后置另立 change。
- 不改 `module.json5`（`supportWindowMode` 默认已含 floating；最小窗口尺寸沿用系统默认 360×240vp，已满足二分屏准入）。

## Decisions

### D1 实现形态：藏栏留系统三键（方案 B）

`setWindowDecorVisible(false)` 隐藏系统标题栏，保留三键下沉右上并以 `setDecorButtonStyle` 主题化；应用自绘 40vp 标题条；`getTitleButtonRect` 做右缘避让。这是官方适配指南明示路径（「隐藏标题栏并适配三键位置」）。

- 备选 A（保留系统栏只调 `setDecorButtonStyle` + `setWindowDecorHeight`）：否决——无法移除系统栏背景与布局，达不到沉浸式与 ☰ 上移目标。
- 备选 C（连三键一起隐藏、全自绘）：否决——自绘三键在应用树内，会被阅读 `bindContentCover` 覆盖（阅读层失窗控），且需 `windowStatusChange` 翻还原图标、`terminateSelf` 关闭等一整套状态链，回归面大；系统三键属 decor 层（窗口管理器渲染），任何内容覆盖层都盖不住，保留它即保住全场景可达。

### D2 覆盖范围：所有自由窗渲染标题条（不按断点开关）

`isInFreeWindowMode` 为真即渲染 40vp 标题条：<1000vp 时条内仅拖拽面 + 三键避让（无 ☰、无计数，资料库入口仍归 HdsTabs 迷你栏）；≥1000vp 时加 ☰ 与计数副题。一条不变量「自由窗必有标题条」。

- 备选（仅 ≥1000vp 渲染，<1000vp 回退系统栏，resize 跨断点时 `setWindowDecorVisible(true/false)` 切换）：否决——自由窗可跨断点缩放（mediaquery 动态），跨断点瞬间系统栏弹入弹出，平滑度不可控，且 EntryAbility 需新增断点监听桥；状态机复杂度换不来收益。
- 备选（<1000vp 不加条、仅给 PageHeader 加三键避让 padding）：否决——无可见拖拽面，窗口移动完全依赖隐形系统条（与 D3 矛盾），且 <1000vp 顶部布局碎片化。
- 关键依据：`setWindowDecorVisible(false)` 只在自由窗状态生效（非自由窗调用无报错无效果），平板全屏/分屏天然安全，无需任何状态切换逻辑。

### D3 拖拽路径：关默认条 + 自绘（Path 2）

`setWindowTitleMoveEnabled(false)` 全局禁用系统默认的「标题栏拖拽 + 双击最大化」，标题条内自绘：

- 拖拽区：标题条空白部（不含 ☰ 与计数）`onTouch` 在 `TouchType.Move` 时调 `window.startMoving()`——Move 触发保证纯点按/双击不进入移动循环；
- 双击：`TapGesture({ count: 2 })`，按 `getWindowStatus()`（或监听维护的 `windowStatus`）在 FLOATING 调 `maximize()`、MAXIMIZE 调 `recover()`。

- 备选 Path 1（直用隐藏后的隐形系统条，零拖拽代码）：否决——隐形条拦截整个顶部 40vp 的双击，存在两个设计级缺陷：① 快速连点 ☰ 会误触最大化（tap 穿透但双击被拦）；② 隐形条叠在阅读层顶栏上，阅读时拖顶栏会移动窗口。两者均非 spike 可修，Path 1 仅作为 Path 2 真机不可用时的回退方案记录于此。

### D4 ☰ 落位：标题条吸收整个 ☰ 行

≥1000vp 自由窗：StreamHome 头部 ☰ 行（☰ + 尾部计数副题）整行上移——☰ 进标题条左缘（沿用 navigation-shell 图标状态映射与无障碍语义），计数副题进标题条尾部（避让区左侧，复用 SubtitleStatus，随 refreshTick 刷新）；StreamHome 该行以 `folderDocked && !freeWindow` 门控隐藏。平板全屏（非自由窗）该行原样保留。

- 备选（条内仅放 ☰，StreamHome 保留行只去 ☰）：否决——顶部出现「条 + 行」双行结构，只剩一个计数的行视觉密度过高。
- 备选（条内 ☰ 旁加品牌「流笺」小字）：否决——与 StreamHome 34fp 品牌重复；窗口身份已由 `setWindowTitle('流笺')` 覆盖。

### D5 真全屏（FULL_SCREEN）态：隐藏标题条，靠 hover 悬浮栏

拖顶进入 FULL_SCREEN 时不渲染标题条，窗口控制由系统 hover 悬浮标题栏提供（`setTitleAndDockHoverShown` 默认开启）。spike 验证 decor 已隐藏时悬浮栏是否仍弹出且三键可用；不成立则回退为「FULL_SCREEN 也渲染标题条」并修订 spec delta（实现任务内置该分支）。

- 备选（FULL_SCREEN 也常显标题条）：否决——放弃真全屏沉浸，且该态本就以系统悬浮栏为标准交互；仅当悬浮栏被证实不可用时才接受常显折衷。

### D6 架构落线：Ability 调 API + AppState 驱动渲染

- `EntryAbility.onWindowStageCreate` 的 `loadContent` 回调内（官方要求 Stage 模型在 setUIContent 生效后调用），按官方 FAQ 示例顺序：

```text
setWindowDecorHeight(40) → setWindowDecorVisible(false) → setWindowTitleMoveEnabled(false)
→ setWindowTitle('流笺') → setDecorButtonStyle(...) → 挂三个监听
```

- 监听 `windowStatusChange` / `freeWindowModeChange` / `windowTitleButtonRectChange` 写入 `AppState`（V2 `@Trace freeWindow / windowStatus / titleButtonRight+Width`），UI 只读 AppState。
- 新组件 `entry/src/main/ets/components/WindowTitleBar.ets`：结构为 `Row[☰ | 拖拽区(Blank) | SubtitleStatus | 避让 Spacer]`，高 40vp、paper 背景、无分隔线。
- `Index.ets` 条件包裹挂载：自由窗时 `Column { WindowTitleBar; 现有根 Stack }`，非自由窗时维持现有根 Stack 原样——现有根 Stack（含 `expandSafeArea`、`bindContentCover`、toast 等）零结构改动。
- `StreamHome.ets` 仅改 ☰ 行门控一处。

- 备选（窗口逻辑塞进 Index 组件内直接调 window API）：否决——Ability 生命周期与窗口句柄获取天然在 EntryAbility，UI 组件持 window 依赖会污染渲染层并难测试。

### D7 状态谓词提纯为纯函数

`showStrip = f(freeWindow, windowStatus)` 与避让宽度计算（`TitleButtonRect` → 保留宽度）提取为无 UI 依赖的纯函数放 `common/`，ohosTest 直测矩阵（FLOATING/MAXIMIZE/FULL_SCREEN/SPLIT/全屏 App 模式 × 断点）；组件只消费谓词结果。

- 备选（谓词散落在组件 @Computed 内）：否决——窗口状态组合分支多，不可直测则全靠真机回归。

### D8 深色处理：不 pin colorMode，跟随系统

`DecorButtonStyle.colorMode` 不显式设置（默认跟随系统深浅色），应用无独立主题开关，无需 `onConfigurationUpdate` 重放；深色效果列为 spike 目检项。可选 polish：`buttonBackgroundCornerRadius` 4→6 对齐应用圆角。

- 备选（显式设 colorMode 并随配置变化重放）：否决——应用主题与系统一致，额外链路只引入不同步风险。

## Risks / Trade-offs

- [spike：`startMoving` 手感/贴边吸附未知] → 真机 2in1 验证拖拽跟手与拖至屏幕边缘是否触发系统贴边/分屏；不可用则回退 D3 的 Path 1（接受 ☰ 双击与阅读拖拽两缺陷）或仅保留双击最大化。
- [spike：MAXIMIZE 态 `isInFreeWindowMode` 返回值未证实] → 若为 false，谓词补 `windowStatus == MAXIMIZE` 分支（D7 纯函数单行修改）。
- [spike：FULL_SCREEN 态 hover 悬浮栏可能在 decor 隐藏后不弹出] → 回退 D5 常显标题条，同步修订 spec delta 再继续。
- [spike：跨断点 resize 平滑性] → mediaquery 驱动为既有机制，标题条内容切换为纯条件渲染；实测卡顿再评估转场。
- [spike：`TitleButtonRect` 单位（px/vp）与字段语义] → 官方适配示例将其与 vp 值混算，实现以真机 dump 为准，收敛在 D7 纯函数内。
- [spike：双击与拖拽手势互抢] → 拖拽以 Move 触发、双击为独立 TapGesture，真机连点两下验证不误拖。
- [spike：深色三键视觉] → 目检；异常再补显式 colorMode。
- [窗口在 <1000vp 自由窗下顶部多 40vp] → 接受：窗口 chrome 的固有成本，换取所有尺寸下控制可达与统一解剖。
- [阅读全屏层内标题条被覆盖不可见] → 预期行为：窗口控制由 decor 层三键承担；拖拽已全局禁用，无误拖。真机目检补充发现：阅读层顶栏（bindContentCover 全窗覆盖，工具栏进入 40vp 按钮带）尾部「阅读/⋯」与下沉三键重叠（⋯ 右缘距窗口右缘仅 ~15.8vp）——修复为 TopBar 行补 `sunkButtonAvoidance` 右内边距（仅自由窗，复用避让数学与 12vp 间距；spec delta「阅读层三键可用」场景同步加不重叠断言）；AddressBar 行在按钮带之下，不参与避让。

## Migration Plan

- 纯 UI 层变更：无数据迁移、无 schema 改动、无配置改动；RDB/preferences/同步零影响。
- 实施顺序见 tasks.md：先 Ability 接线与 AppState（不接 UI 即无视觉变化），再挂标题条，最后收 StreamHome 门控——每步均可独立构建验证（`check_ets_files` + `hvigorw assembleHap`）。
- 回滚：revert 对应提交即可，无残留状态（窗口装饰 API 均为进程内运行时调用，不落盘）。

## Open Questions

- `setWindowDecorHeight(40)` 与 `setWindowDecorVisible(false)` 的先后是否影响隐形条高度（官方 FAQ 示例先 height 后 hide，实现按示例顺序，spike 顺带确认）。
- 避让区在 `TitleButtonRect` 之外是否需固定呼吸边距（视觉间距，实现时微调，不影响契约）。
