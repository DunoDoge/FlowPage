# Tasks

## 1. 状态层与 Ability 接线

- [x] 1.1 `entry/src/main/ets/common/AppState.ets`：新增 `@Trace freeWindow`（boolean，默认 false）、`@Trace windowStatus`（WindowStatusType）、`@Trace titleButtonRight` / `@Trace titleButtonWidth`（number，右缘三键避让）字段；UI 未消费前无视觉影响；以 `check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 1.2 `entry/src/main/ets/entryability/EntryAbility.ets`：`loadContent` 回调内按序调用 `setWindowDecorHeight(40)` → `setWindowDecorVisible(false)` → `setWindowTitleMoveEnabled(false)` → `setWindowTitle('流笺')` → `setDecorButtonStyle(...)`；挂 `windowStatusChange` / `freeWindowModeChange` / `windowTitleButtonRectChange` 三监听写入 AppState，并在挂载后同步读取一次初始值（`isInFreeWindowMode` / `getWindowStatus` / `getTitleButtonRect`）；以 `check_ets_files` + `hvigorw assembleHap` 收尾

## 2. 状态谓词纯函数与设备端用例

- [x] 2.1 `entry/src/main/ets/common/` 新增窗口装饰谓词模块（如 `WindowChrome.ets`）：`showStrip(freeWindow, windowStatus)`（FLOATING/MAXIMIZE 渲染、FULL_SCREEN/SPLIT/非自由窗不渲染）与 `avoidanceWidth(rect, margin)`（TitleButtonRect → 右缘避让宽度）；以 `check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 2.2 `entry/src/ohosTest` 现有设备端套件新增谓词矩阵用例（窗口状态 × 自由窗组合）与避让宽度计算用例；按 AGENTS.md 设备端测试流程构建运行（`hvigorw --mode module -p module=entry@ohosTest ... assembleHap` + `hdc install` + `hdc shell aa test`）全部通过

## 3. 标题条组件与挂载

- [x] 3.1 将 `entry/src/main/ets/components/StreamHome.ets:686` 的 `SubtitleStatus` @Builder 提取为共享组件（保持 refreshTick 刷新链路与现有文案「N 条 · 今天收下 N 条」），StreamHome 两处使用点（787/797）改引共享组件；以 `check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 3.2 新增 `entry/src/main/ets/components/WindowTitleBar.ets`：40vp 全宽 paper 标题条——左缘 ☰（仅 ≥1000vp，沿用 open_sidebar/close_sidebar 状态映射与无障碍语义，写 `appState.sideNavOpen`）、中部拖拽区（`onTouch` Move 触发 `startMoving`）、尾部共享 SubtitleStatus 计数（仅 ≥1000vp）、右缘避让 Spacer（消费 `titleButtonRight/Width`）；双击空白区按 `windowStatus` 调 `maximize()`/`recover()`；交互热区 ≥44vp、hover/按压反馈遵循 interaction-feedback 既有规格；以 `check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 3.3 `entry/src/main/ets/pages/Index.ets`：自由窗（消费 2.1 谓词）时以 `Column { WindowTitleBar; 现有根 Stack }` 条件包裹挂载，非自由窗维持现有根 Stack 原样（`expandSafeArea` / `bindContentCover` / toast 结构零改动）；以 `check_ets_files` + `hvigorw assembleHap` 收尾
  - 实现备注：改为**常驻 Column + 条件条子节点**（`if (stripVisible) WindowTitleBar` 在 Column 内、Stack 永为第二子级、高度 `calc(100% - 40vp)`/`100%` 由 `rootStackHeight()` 切换）。若按字面双分支条件包裹，浮动↔真全屏切换会销毁重建 Stack 子树，违反 spec「状态切换不丢内容」（滚动位置/关键词会丢）。常驻方案下非自由窗渲染与现状值等价（Stack 属性零改动、height 同值 '100%'、expandSafeArea 子组件穿透父容器为官方安全区范式）。
- [x] 3.4 `entry/src/main/ets/components/StreamHome.ets`：≥1000vp ☰ 行（750 行起）加 `folderDocked && !freeWindow` 门控，自由窗时整行（含尾部计数）让位于标题条；平板全屏非自由窗行为不变；以 `check_ets_files` + `hvigorw assembleHap` 收尾
  - 实现备注：else 分支改 `else if (!this.folderDocked)`——若保留裸 else，自由窗 ≥1000vp 会渲染 PageHeader 使计数与标题条重复；自由窗 ≥1000vp 该槽位不渲染（品牌行/搜索行不受影响）。
- [x] 3.5 `entry/src/main/ets/components/ReadingShell.ets`：阅读层顶栏（TopBar 行）尾部补三键避让——真机目检确认自由窗下 ⋯/阅读切换与下沉三键重叠（⋯ 右缘距窗口右缘仅 ~15.8vp，三键区占右缘 152vp）；共享组合函数 `sunkButtonAvoidance`（WindowChrome，自由窗门控 + 复用 `avoidanceWidth` 数学）下沉，WindowTitleBar 同步改引；AddressBar 行在 40vp 按钮带之下不参与避让（保持原 padding）；补 `sunkButtonAvoidance` 设备用例 2 个（209/209 通过）；以 `check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 3.6 用户反馈微调：侧边栏与页签首项文字「流笺」更名「笺流」（`common/Constants.ets` NAV_ITEMS 单源，页签与停靠栏同源生效；品牌标题/窗口标题不变）；≥1000vp 自由窗品牌标题与右栏目的地页标题顶边对齐（StreamHome 自由窗 docked 分支补 26vp 状态带占位——等于 PageHeader 状态行带（12vp padding + 12fp 状态行），对齐差值与 <1000vp 实测一致：品牌节点顶 = 标签节点顶 + 26px）；以 `check_ets_files` + `hvigorw assembleHap` 收尾
  - 实测备注：1100vp 下品牌节点顶 620 = 标签节点顶 594 + 26px（<1000vp 为 432 = 406 + 26px，两端一致）；侧栏首项 [829,620]「笺流」、手机底部页签首项「笺流」生效；设备端套件 209/209（ResultCode 0）、codelinter 0 error（存量 1 warn + 1 suggestion）。

## 4. 真机 spike（2in1）与回退分支

- [x] 4.1 部署 2in1 真机：验证 `startMoving` 拖拽跟手与拖至屏幕边缘的系统行为（贴边/分屏/最大化）；不可用则按 design.md D3 回退 Path 1 并在 design.md 记录结论
  - 实测备注（PC 模式模拟器 127.0.0.1:37565，自由窗原生；2in1 真机复核待设备）：startMoving 拖拽跟手精确（拖拽增量 +358,+281 与窗口位移逐像素一致、尺寸不变）；拖至屏幕顶部触发系统 snap 进入 MAXIMIZE(2)（非 FULL_SCREEN，条保留、双击可还原）；Path 2 成立，无需回退。
- [x] 4.2 真机确认 MAXIMIZE 态 `isInFreeWindowMode` 返回值；为 false 则给 2.1 谓词补 `windowStatus == MAXIMIZE` 分支、2.2 补用例并重跑（收尾同 2.1/2.2）
  - 实测备注：MAXIMIZE 态 `isInFreeWindowMode` 保持 true（freeWindowModeChange 未触发），谓词无需补分支，2.2 无需重跑。
- [x] 4.3 真机确认 FULL_SCREEN（拖顶）态 hover 悬浮标题栏在 decor 隐藏后仍弹出且三键可用；不成立则回退「FULL_SCREEN 也渲染标题条」，同步修订 `openspec/changes/window-chrome/specs/window-chrome/spec.md` 状态谓词需求后重验
  - 实测备注：FULL_SCREEN(1) 经任何 UI 路径均不可达——系统三键键序为 [最大化, 最小化, 关闭]（注意：左键即最大化，非常见 [min,max,close] 序），系统最大化 → MAXIMIZE(2)；拖顶 snap → MAXIMIZE(2)；自绘双击改 `maximize(MaximizePresentation.EXIT_IMMERSIVE)` 后不再落 FULL_SCREEN（默认 presentation 在设备上映射 FULL_SCREEN=1、条谓词假、无按钮、UI 不可恢复——已修）。hover 悬浮栏场景不适用，无需回退分支，spec 无需修订。
- [x] 4.4 真机验证自由窗跨断点 resize（≥1000vp ↔ 700–999vp ↔ <700vp）：标题条内容按断点切换、无闪烁破图；迷你栏、批量态、抽屉、阅读层回归无异常
  - 实测备注：1100vp ↔ 521vp 跨断点往返 resize 无崩溃，手机断点 PageHeader 计数 + 底部悬浮页签正常渲染，回宽断点条计数 + 侧栏智能视图完整恢复。期间发现并修复 3.1 遗留崩溃：trailing lambda 内直接构造自定义组件（`SubtitleStatus({...})`）经 @BuilderParam 机制执行时抛 "class constructor cannot called without 'new'"（此前所有测试均 ≥1000vp 宽、该分支从未渲染），改为 `@Builder CountTrailing()` 中转后崩溃消除。
- [x] 4.5 真机 dump `getTitleButtonRect` 确认单位与字段语义，校准 2.1 避让计算；确认 ≥1000vp 计数副题与三键无重叠
  - 实测备注：单位 vp；真值 right=0（按钮簇右缘贴窗口右缘）、width=140；init 同步读到 0/0 陈旧值、`titleButtonRectChange` 约 90ms 后送真值（实现已兜住）；避让 0+140+12=152vp 与计数文本右缘实测精确吻合（2605−289=2316）；≥1000vp 计数与三键实测 12vp 间隙。
- [x] 4.6 深色模式目检三键与标题条对比度（`DecorButtonStyle` 未 pin colorMode）；异常则补显式 colorMode 并复检（收尾同 2.1）
  - 收尾备注：深色目检通过（用户确认）——三键与标题条在深色 paper 上对比度正常，`DecorButtonStyle` 随系统主题即可，无需 pin colorMode。
- [x] 4.7 真机验证手势不互抢：连点标题条空白两下触发最大化/还原；快速连点 ☰ 两次只切侧栏不最大化；拖动阅读层顶栏窗口不移动
  - 实测备注：双击空白 → MAXIMIZE(2)（EXIT_IMMERSIVE）/ 再双击 → recover() 还原原位 ✓；☰ 连点两次仅侧栏开合、窗口零位移 ✓；阅读层顶栏（TopBar）拖拽窗口不动（两轮复现）✓；计数点击无反应 ✓。

## 5. 集成收尾

- [x] 5.1 对照 `openspec/changes/window-chrome/specs/window-chrome/spec.md` 与 `openspec/changes/window-chrome/specs/navigation-shell/spec.md` 全部场景在真机/模拟器走查（覆盖 2in1、平板自由多窗、平板全屏、手机回归）；`codelinter -c code-linter.json5` 0 error
  - 收尾备注：场景覆盖由 4.1–4.7 实测记录合并承载（PC 模式模拟器自由窗=2in1 形态、1100↔521vp 跨断点往返、手机断点回归 + 崩溃修复复验、手势不互抢、避让校准）；谓词/避让矩阵由设备端套件 209/209 覆盖；codelinter 0 error（存量 1 warn + 1 suggestion）。2in1 真机复核随 4.6 待设备。
- [x] 5.2 按 `openspec/config.yaml` apply 指引更新 `AGENTS.md` 易变事实（自由窗标题条、EntryAbility 装饰调用链、断点矩阵关联说明），全量内链 grep 校对收尾
  - 收尾备注：AGENTS.md 新增「自由窗窗口装饰」条目（调用链/谓词/常驻 Column/EXIT_IMMERSIVE/避让/计数镜像单写者），断点矩阵与品牌条目补 ☰/计数迁移动注与 NAV_ITEMS 首项「笺流」更名，能力规格补 window-chrome 链接。

## Workflow follow-up

- 实现与走查完成后，经 `openspec-archive-change` 流程归档本 change（归档时按 config archive 指引核对 AGENTS.md 吸收无遗漏）。
- 归档后验证：`openspec/changes/` 不再含 window-chrome，主 specs 已合并 delta。
