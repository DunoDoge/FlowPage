# Design

## Context

现状：☰ 为 `Text('☰')`（StreamHome.ets），停靠 SideNav（NavigationRail.ets）与 FolderDrawer（Index.ets）各自渲染一份 NAV_ITEMS（仅 `margin left 22/20` 与顶部 padding 不同）；tags/sync/settings 三页各自手写「返回」页头；`openPane()` 在手机端直接 `pushPathByName` 累加栈；全项目无 hoverEffect/stateStyles/animation；FolderDrawer 无转场。约束：状态管理 V2、无新路由、颜色一律 `$r('app.color.*')` 成对维护、阅读页性能红线不动。

## Goals / Non-Goals

**Goals:**

- ☰ 的图标语义在全断点可预测；抽屉/停靠栏形态一致；子页面可直达侧边栏；导航栈语义干净
- 主要交互点在鼠标/触控下有操作反馈；图标符合系统 Symbol 规范
- 消除导航渲染与页头的重复代码

**Non-Goals:**

- 不动断点阈值（700/1000vp）、不动 `main_pages.json` 路由、不动 detail 页头部、不动工程配置（`code-linter.json5`）
- 不给阅读页（ReaderView/ReadingShell 内部）加反馈效果
- 不做导航项图标化（NAV_ITEMS 加 icon 属后续独立变更）

## Decisions

### D1: ☰ 图标用 SymbolGlyph + 系统符号资源，资源名实现时核对

主选 HarmonyOS Symbol 库的 open_sidebar / close_sidebar 对应 `sys.symbol.*` 资源；图标状态来源直接复用 `AppState.sideNavOpen`（≥1000vp）与 `folderDocked` 参数推导，不新增状态字段。

> **核对结论（已验证）**：对照 SDK 符号表（`ets-loader/sysResource.js` 的 symbol 组，4042 项）确认全部精确名存在，无需降级——☰ 展开 `sys.symbol.open_sidebar`、☰ 收起 `sys.symbol.close_sidebar`、加号 `sys.symbol.plus`、更多 `sys.symbol.more`、关闭 `sys.symbol.xmark`。

- 备选 1：保留文本字形 `☰` —— 否决：跨设备字体渲染不一致，且无状态语义
- 备选 2：`symbolRegister` 自注册 TTF —— 否决：为零第三方依赖的项目引入 rawfile 资产，系统库已有近义图标
- 降级链（首个实现任务内核对）：精确名 → 近义符号（menu / 抽屉类）→ 保留现状并在任务中记录结论

### D2: 抽屉顶部留白取常量 26vp，与停靠栏共用一个口径

`NavList` 组件内持有 `TOP_INSET = 26` 常量，两处渲染同源。

- 备选 1：按窗口高度/断点动态计算 —— 否决：26vp 是停靠栏既定视觉节奏，动态值破坏一致性且无收益
- 备选 2：仅抽屉侧硬编码 —— 否决：两处各自硬编码正是本次留白不一致的根因

### D3: 抽共享 `NavList`，标签缩进统一为 20vp

SideNav 与 FolderDrawer 的两份 NAV_ITEMS 渲染合并为 `components/NavList.ets`（@ComponentV2，`@Param` 当前 pane、`@Event onSelect`）。原 22/20vp 两值统一为 20vp（与主页 ☰ 左缩进同口径，原代码注释即以 20vp 为对齐基准）。

- 备选 1：组件加 `inset` 参数保留 22/20 两值 —— 否决：2vp 差异无感知意义，参数只为兼容历史值而存在
- 备选 2：维持两份代码 —— 否决：重复已导致一次形态漂移（本次留白问题）

### D4: 新增 `PageHeader` 承载子页页头（返回 + ☰）

`components/PageHeader.ets`（@ComponentV2）：可选「返回」与可选 ☰（☰ 仅 `!isLarge` 断点渲染，宽屏下侧栏常驻无入口意义）；tags/sync/settings 换用。detail 页不换（无 ☰ 需求且其页头结构特殊，强套共享件反而加参数分支）。

- 备选 1：改用 Navigation 系统 titleBar —— 否决：全项目 `hideTitleBar(true)` + 自绘页头，引入系统标题栏是更大的视觉变更
- 备选 2：三页各写一份 ☰ —— 否决：又造三份重复，与 D3 矛盾

### D5: 手机端抽屉切换 pane 清栈再进（对齐 `showDetailOnPhone` 模式）

`openPane()` 在 `!isWide` 分支：目标为流笺 → `navStack.clear(false)`；其余 pane → `clear(false)` 后 `pushPathByName`。与既有详情路由的清栈写法保持同构。

- 备选 1：`replacePathByName` —— 否决：只替换栈顶，更深的残留栈清不掉
- 备选 2：维持纯 push —— 否决：抽屉是顶层导航，返回语义应为「回主页」，逐层回退违背直觉（现状 bug）

### D6: 抽屉转场用条件渲染 `transition`（平移 + 淡入）

抽屉列 `transition(translate({x:-侧栏宽}).combine(opacity))`、遮罩 `transition(opacity)`；条件渲染的插入/移除自动播放。若条件分支切换不触发动画，回退方案为把 `folderDrawerOpen` 翻转包进 `getUIContext().animateTo`。

- 备选 1：`bindSheet`/`bindContentCover` —— 否决：阅读层已占用 contentCover，抽屉有拖拽联动与自定义遮罩命中规则，系统容器装不下
- 备选 2：常驻节点 + `translate` 偏移控制 —— 否决：常驻遮罩与命中测试需要额外状态机，复杂度不成比例

### D7: 反馈按官方按压阴影指南实现（hdsEffect.pressShadow + visualEffect + onHover/onTouch 状态机）

依据官方指南（doccenter-capabilities/ui-design-visual-effect-background-color）：交互点挂 `.visualEffect(new hdsEffect.HdsEffectBuilder().pressShadow(状态).buildEffect())`，状态为 `hdsEffect.PressShadowType.BLEND_WHITE`（15% 白混合）/`NONE`，由 `onTouch`（Down→按下、Up/Cancel→抬起）与 `onHover`（进/出）驱动 `@Local`；Button 类组件先 `stateEffect(false)` 关闭内置按压避免双重反馈。覆盖：导航行、☰、chips、收笺、批量、排序、清除筛选、星标、更多、PageHeader 返回/☰。

> **实现修正（两轮实测）**：主选 `stateStyles({hovered, pressed})` 背景 `surface_alt` 在 Text/Row/SymbolGlyph 等 plain 组件上状态机不可靠——按压后背景残留不消失、hover 触发观感成"阴影"、chips 选中背景被覆盖；且本 SDK（API 26）无 `hoverable` 属性。备选 2（手动 onHover/onTouch + @Local）方向正确但自绘背景仍有残留/错位风险，最终落地为该备选与官方指南的结合：手动状态机 + 系统按压阴影效果（不碰背景色，从根上消除残留）。

- 备选 1：`hoverEffect(HoverEffect.Scale/Highlight)` —— 否决：只有整体缩放/系统默认效果，与纸感高亮风格不统一，且不覆盖按压态
- 备选 2：逐组件 `onHover`/`onTouch` + `@Local` 自绘背景 —— 否决（作为最终形态）：背景绘制仍可能与动态背景（chips 选中态）冲突；其状态机部分被采纳为 pressShadow 的驱动
- 备选 3：`attributeModifier` —— 否决：样板代码多于收益，适合大规模主题化而非十几处高亮

### D8: 图标替换映射与热区

`×` → 关闭类符号（保留「清除标签/文件夹筛选」标签）、`+ 收笺` → 加号符号 + 文字、`…` → 省略号/更多符号（保留「更多操作」标签）；`fontSize` 与原文本视觉大小对齐（16-20vp），`fontColor` 沿用 `ink_secondary/ink_tertiary`。弹层「取消」等可视高度 <44vp 的按钮加 `responseRegion` 扩到 44vp。

- 备选：直接放大可视尺寸到 44vp —— 否决：弹层信息密度下降，responseRegion 是零视觉成本方案（项目已有此模式先例）

## Risks / Trade-offs

- [Risk] sys.symbol 无 open_sidebar/close_sidebar 精确资源名 → Mitigation: D1 降级链，首个任务内核对并记录结论，不阻塞后续任务
- [Risk] 抽屉转场与拖拽自动展开（`beginDragFromBookmark`）相互作用导致投放抖动 → Mitigation: 验证拖拽路径；转场不改变 `hitTestBehavior`，若仍有问题在拖拽会话激活时跳过转场参数
- [Risk] `stateStyles.hovered` 在部分非按钮组件不生效 → Mitigation: 补 `.hoverable(true)`；个别仍失败则该点降级 `onHover` + `@Local`
- [Risk] NavList 合并造成 2in1 视觉回归（22→20vp 缩进）→ Mitigation: 2in1 目检四导航项 + 分隔线位置
- [Risk] 清栈语义改变老用户习惯（原可逐层返回）→ Mitigation: 属修 bug 而非破坏——抽屉顶层导航的返回预期即回主页；在 change 归档说明中记录

## Migration Plan

纯 UI 变更、单 HAP，无数据迁移：构建通过 + 设备端目检三断点即可发布；回滚 = revert 对应提交。

## Open Questions

- 无阻塞项。符号精确资源名在首个实现任务内解决（D1 降级链已定）。
