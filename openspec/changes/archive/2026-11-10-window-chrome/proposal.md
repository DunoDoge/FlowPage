# Proposal

## Why

2in1 与平板自由多窗（自由窗口）下，应用使用系统默认标题栏：沉浸式 paper 纸面之上叠一条系统灰白栏，与应用视觉语言割裂；大屏（≥1000vp）侧边栏展开/收起入口 ☰ 被压在内容头部第二行，窗口顶部空间未被利用。官方 HDS 电脑端设计明确推荐「应用工具栏与窗口标题栏合一」，HarmonyOS 已提供完整的窗口装饰定制 API（所需最高 API 22，项目 API 26 全覆盖），当前实施成本最低。

## What Changes

- 新增 `window-chrome` 能力：自由窗（`isInFreeWindowMode`，覆盖 2in1 与平板/手机自由多窗）隐藏系统标题栏（`setWindowDecorVisible(false)`，非自由窗自动无效可无条件调用），改为应用自绘 40vp 全宽标题条：
  - **≥1000vp**：左缘 ☰（沿用 open_sidebar/close_sidebar 状态语义）、尾部计数副题「N 条 · 今天收下 N 条」、右缘系统三键避让区；StreamHome 原 ☰ 行被标题条吸收移除。
  - **<1000vp**：仅拖拽面 + 右缘三键避让（资料库入口仍归 HdsTabs 迷你栏，不引入 ☰）。
  - **任意断点**：拖拽面走 `setWindowTitleMoveEnabled(false)` + `startMoving()`（onTouch Move 触发）；双击标题条空白区最大化/还原（自绘手势，按 `getWindowStatus()` 切换 `maximize()`/`recover()`）。
- 系统三键保留（隐藏标题栏后下沉右上，`setDecorButtonStyle` 主题化），不自绘窗口控制按钮；阅读全屏层（`bindContentCover`）零改动——decor 层在窗口管理器，三键不被内容覆盖层遮挡。
- FULL_SCREEN（拖顶真全屏）态不渲染标题条，靠 hover 悬浮标题栏提供窗口控制（真机 spike 验证，不成立则回退为常显标题条）。
- `EntryAbility` 挂 `windowStatusChange` / `freeWindowModeChange` / `windowTitleButtonRectChange` 监听，写入 AppState（V2 `@Trace`）驱动条件渲染。
- 明确范围外：ShareAbility（系统分享面板宿主，窗口 chrome 归系统）、阅读专注模式（ENTER_IMMERSIVE 真全屏阅读，后置另立 change）。

## Capabilities

### New Capabilities

- `window-chrome`: 自由窗窗口装饰行为契约——标题条解剖（☰/计数副题/三键避让）、系统标题栏隐藏与三键下沉避让、拖拽与双击手势、窗口状态谓词（FLOATING / MAXIMIZE / FULL_SCREEN / 分屏 / 全屏 App 模式下的渲染规则）。

### Modified Capabilities

- `navigation-shell`: ≥1000vp 自由窗下，☰ 及其所在头部行从 StreamHome 迁至窗口标题条（平板全屏等非自由窗形态不变）；计数副题随行迁入标题条尾部。

## Impact

- **代码**：`entry/src/main/ets/entryability/EntryAbility.ets`（窗口装饰 API 调用链 + 三个监听）、`entry/src/main/ets/common/AppState.ets`（新增 `@Trace freeWindow / windowStatus / titleButtonRect` 类字段）、新组件 `entry/src/main/ets/components/WindowTitleBar.ets`、`entry/src/main/ets/pages/Index.ets`（根部条件挂载标题条）、`entry/src/main/ets/components/StreamHome.ets`（☰ 行加自由窗门控）。
- **依赖**：零新增运行时依赖；仅用 `@kit.ArkUI` 既有 window / mediaquery 能力。
- **规格**：新建 `openspec/specs/window-chrome/spec.md`；`navigation-shell` 出 delta。
- **风险**：7 项真机 spike（`startMoving` 手感与贴边吸附、MAXIMIZE 态谓词取值、FULL_SCREEN 态 hover 悬浮栏、跨断点 resize 平滑性、`TitleButtonRect` 单位、深色三键目检、双击与拖拽不互抢），全部纳入实现任务。
- **不受影响**：阅读链路与 `bindContentCover` 不变量、同步、桌面卡片、ShareAbility、`module.json5`（`supportWindowMode` 默认已含 floating，无需改动）。
