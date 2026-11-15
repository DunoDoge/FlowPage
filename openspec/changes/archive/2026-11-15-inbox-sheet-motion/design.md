# Design

## Context

收笺面板（`components/InboxSheet.ets`，320 行）当前经 `Index.ets:409` 的 `if (this.appState.showInbox)` 条件挂载，开关瞬间切换无动画。项目已有两套实测动效先例：`FolderDrawer`（常驻挂载 + translate/opacity 状态驱动，240ms `FastOutSlowIn`）与 `PaneEntrance`（design D11：挂载时 onAppear 翻转 + fade/12vp 上浮）。AGENTS.md 明确记录：条件渲染 + `transition` 实测不动画（抽屉教训），勿回退该方案。本设计把抽屉模式移植到收笺面板，并按用户拍板的 C 档编舞（弹簧 0.75 轻俏 / β 发射感 / 参数局部常量）展开。

首轮实现走查反馈（2026-11，模拟器宽窗）：其一，进场"直接出现"、发射"几乎看不到"——根因是 translate 插值跨单位（`'100%'↔'0'`、`'5vp'↔'-100%'`）回退离散切换，状态机正确但动画不可见；其二，宽断点（折叠屏展开/平板/PC）面板仍底部停靠全宽，要求屏幕居中卡片 + 更宽自适应布局。本修订以 D3 单位自洽规则与 D8 呈现矩阵收敛。

二轮走查反馈（2026-11）：单位修正后面板进场**仍然瞬移**、保存发射退场**生硬**。复查代码两个根因假设：其一（主），关闭态 `Visibility.None` 兜底使面板在 None 期间不参与渲染，进场帧"重新出现 + 位移"同帧发生，渲染服务无旧几何可插值、直接快照——任何轨迹写法都被它废掉；其二（从），百分比字符串 translate 插值从未在本项目验证过（全项目唯一生产在动的 translate 动画是抽屉的**数值**位移）。本修订以 D3「数值位移状态 + 全生命周期无 Visibility 切换」收敛。

三轮走查反馈（2026-11）：数值化后进场**依旧瞬移**、级联**变卡**。onFinish 探针（settle 1001ms）测到的其实是同闭包里 **scale 0.97→1 的伴随弹簧**——面板 translate 从未被 `animateTo` 捕获（探针方法学错误：dumpLayout 看不见渲染侧 translate，onFinish 不区分属性）；且该 1 秒 scale 使整面板逐帧重绘，正是级联卡顿源。收敛结论：**全项目所有在生产中会动的面板 translate（抽屉、PaneEntrance）都由节点隐式 `.animation()` 驱动，没有任何一处在面板本体上成功使用 `animateTo`**——本轮把外层节点改挂相位参数化的隐式 `.animation`（抽屉同款），删除弹簧与 scale 点缀，进场回归家族曲线 `FastOutSlowIn`（非线性缓动，满足"非线性动画"诉求），级联同步收紧。

## Goals / Non-Goals

**Goals:**

- 面板进/出场 + 成功退场三条转场路径全部动画化，出场依赖常驻挂载
- 断点呈现矩阵：<700vp 底部停靠面板；≥700vp 屏幕居中卡片（600/720vp 宽度档 + ≥1000vp 两栏响应式表单）
- 转场位移全程同单位插值、肉眼可感知（首轮跨单位跳变教训）
- 表单字段级联进场，复用 D11 词汇（fade + 12vp 上浮 + `FastOutSlowIn`），仅面板本体引入弹簧
- 域名提示、批量块、点条移除三类内部状态变化纳入动效
- 级联/退场期间交互可用，重开面板状态干净

**Non-Goals:**

- 下滑手势关闭面板（跟手 + 速度判定，独立变更）
- 抽屉/停靠栏/页签迁移到弹簧曲线（维持 240ms `FastOutSlowIn`，无迁移计划）
- 全局 Motion token（参数收在 `InboxSheet.ets` 顶部常量，等第二个弹簧场景再提炼）
- toast 退出动画、toast 队列改造（仅补进场浮现）

## Decisions

### D1: 常驻挂载 + 相位状态机（否决：条件挂载 + transition、延迟卸载）

`Index.ets` 的 `if (showInbox) { InboxSheet() }` 改为无条件挂载，`InboxSheet` 内部以 `@Local phase` 驱动：`closed → entering → open → exiting|launching → closed`。`AppState.showInbox` 保持唯一意图源，`openInbox/closeInbox` 签名不变——所有现存关闭路径（遮罩、「关闭」、保存成功）无需改调用方。

- 否决**条件挂载 + `TransitionEffect`**：抽屉实测面板本体不动画（AGENTS.md 记录在案）。
- 否决**动画完成后 setTimeout 卸载**：卸载时机与 `showInbox` 真值脱钩，快速重开需取消卸载定时器，状态机分散在组件内外，竞态面更大；且常驻方案在抽屉上已验证可靠。
- 关闭态逐层 gate 复用抽屉手法：根 `HitTestMode.None` + 面板 `enabled(false)` + `accessibilityLevel('no-hide-descendants')`；**退场开始即**撤遮罩命中（`HitTestMode.None`），底层立即可交互，不等动画播完。

### D2: 退场口味是 InboxSheet 内部状态（否决：AppState 加 exitFlavor）

「发射感」（launch）与普通退场（dismiss）的区分只在 `InboxSheet` 内部：`@Local launchExit: boolean`。`save()/saveBatch()` 成功路径置 `launchExit = true` 后调 `appState.closeInbox()`；遮罩/「关闭」路径保持 false。`@Monitor('appState.showInbox')` 观察到 true→false 时按口味进入 `launching` 或 `exiting`。

- 否决**AppState 增加 `inboxExitFlavor`**：`closeInbox()` 的全部调用方都在 `InboxSheet` 内部，口味不是跨组件事实，放进 AppState 是把视图编排细节泄漏进全局状态。

### D3: 动效参数（局部常量，`InboxSheet.ets` 顶部）

```
INBOX_ENTER         400ms FastOutSlowIn        面板进场（全断点屏下滑入，家族曲线；弃弹簧——1s settle 拖沓且伴随 scale 重绘卡顿；六轮反馈放缓，原 320ms）
INBOX_SCRIM_IN      240ms FastOutSlowIn        遮罩淡入（与抽屉同时长）
INBOX_EXIT          300ms EaseIn               普通退场下滑出屏（加速离场；六轮反馈放缓，原 220ms）
INBOX_LAUNCH_DIP    100ms FastOutSlowIn        发射前下顿蓄力（嵌套内层节点；深潜断点分档：手机 32vp / 宽屏 6vp）
INBOX_LAUNCH_RISE   400ms FastOutSlowIn        上滑离屏（=进场同速同曲线；四~六轮迭代曾试 300ms 快起贝塞尔，终稿回归家族曲线——与进场同构读作「反向打开」）
INBOX_SCRIM_OUT     160ms FastOutSlowIn        遮罩淡出（dismiss 口味）
INBOX_SCRIM_LAUNCH_OUT 200ms FastOutSlowIn    遮罩淡出（launch 口味，慢半拍离场衬托发射）
INBOX_TRAVEL_PHONE  900vp                      手机隐藏位移（数值；覆盖含批量块的最大表单高，底部停靠下必出屏）
WIDE_TRAVEL_VP      2000vp                     宽屏离屏位移（数值；居中卡自高百分比清不干净）
WIDE_CARD_W_MID     min(84%, 600vp)            700–999vp 居中卡片宽
WIDE_CARD_W_LARGE   min(70%, 720vp)            ≥1000vp 居中卡片宽
CASCADE_DELAY       120ms                      面板动身后首字段延迟启动（进场放缓后回调 120，保持与面板运动的观感比例；三轮曾收紧 90）
CASCADE_STEP        30ms                       字段级联步进（三轮收紧，原 35ms）
CASCADE_FIELD       180ms FastOutSlowIn, 12vp  单字段 fade+上浮（D11 词汇；三轮收紧，原 200ms）
BTN_PULSE           90ms, scale 0.96→1         提交按钮压缩回弹（三轮收紧，原 120ms）
HINT_MOTION         150ms FastOutSlowIn        域名提示高度+fade 对称
BATCH_REVEAL        180ms FastOutSlowIn        批量块容器展开
BATCH_STEP          30ms，上限 6 条             条目级联，第 7 条起整组浮现
ROW_COLLAPSE        160ms FastOutSlowIn        被点行高度 44→0 收缩
```

- 否决 **`Curve.Spring*` 预设**：参数不可调，无法落在 0.75 阻尼这一指定性格档。
- 否决**自定义 `cubicBezierCurve` 模拟弹簧**：用户明确要物理弹簧；贝塞尔模拟过冲在打断重放时速度不连续，真机上打断（快速连开连关）会露馅。
- **隐式 .animation 驱动（三轮走查修订，抽屉逐字复刻）**：外层节点挂相位参数化的 `.animation(this.motionParams())`（进场 400ms `FastOutSlowIn` / 退场 300ms `EaseIn` / 发射 = 进场 400ms `FastOutSlowIn`），`animateTo` 已退役（其事务从未捕获过面板本体 translate，三轮实测），隐式动画是本仓库唯一在产的 translate 驱动；面板本体禁 scale/opacity（scale 弹簧曾致整面板 1s 逐帧重绘，是级联卡顿源）。
- **归位零时长 + 定时器时序（四轮走查修订）**：`motionParams()` 的 CLOSED 分支返回 `duration: 0`——发射终位（-hidden，屏上）与归位隐藏位（+hidden，屏下）之间 2×hidden 的屏外跳变，必须瞬移而非被隐式动画播成"重新向下滑过屏幕"（四轮实锤）；三条转场入口全部改为纯状态写 + 带守卫 `setTimeout` 链（相位交接与 dip→rise 时序不依赖 `onFinish`，其触发时机在该节点上不可靠）。
- **数值位移状态（二轮走查修订，对齐抽屉已验证模式）**：面板位移由 `@Local panelOffsetY: number`（纯数值状态）承载，转场入口纯状态写数值目标（0 / `INBOX_TRAVEL_PHONE` 或 `WIDE_TRAVEL_VP` / 负同值；四轮起 `animateTo` 已退役，见上条），`.translate({ y: this.panelOffsetY })` 数值直绑——与 `FolderDrawer` 生产在跑的数值 translate 同构，插值路径最强。**全断点禁用百分比字符串与 `Visibility` 切换**：`Visibility.None` 会让关闭态节点脱离渲染，进场帧"重现 + 位移"同帧发生时无旧几何可插值而快照（二轮"仍瞬移"的主因假设）；隐藏完全靠几何离屏（底部停靠 +900vp / 居中 ±2000vp），命中与无障碍由既有逐层 gate 负责。下顿由内层嵌套数值节点承担（深度断点分档，见 D3）。**面板本体（含外层运动节点）全程不做 opacity 动画与 scale 点缀**（PasteButton 祖先链约束，D4 实测；scale 点缀三轮已删——逐帧重绘卡顿源）。发射上滑终稿与进场同速同曲线 `FastOutSlowIn`（发射感由下顿蓄力与方向差承担；快起贝塞尔曾是四~五轮方案，六轮弃）。
- 级联只给字段、不给弹簧：弹簧仅属于面板本体这一层级，字段维持全应用统一 D11 词汇，避免收笺页变成动效语言孤岛。
- toast 浮起：`Index.ets` 的 toast Text 改常驻 + opacity/8vp 上浮绑定 `toastText.length > 0`，180ms `FastOutSlowIn`，`HitTestMode.None`。这是全应用可见的最小增益（所有 toast 一致受益），β 编舞要求它在退场中浮起。

### D4: 级联用单状态翻转 + 每节点 delay（否决：每字段定时器）

`phase` 翻入 open 时所有字段的 `appeared` 绑定值同帧翻转，各字段 `.animation({ delay: CASCADE_DELAY + i * CASCADE_STEP })` 挂不同延迟——抽屉内容延迟跟进（`Index.ets:506`）同款手法。无 setTimeout、无中断清理。

- 否决**每字段 `setTimeout` 依次置位**：5 个定时器要管理取消与快速重开竞态；单翻转 + delay 由渲染框架打断重放，免费获得正确性。
- **URL 行仅上浮、不淡入（实测修正）**：PasteButton 是安全组件，祖先透明度非 1 时注册直接失效（`SecurityComponentCheckFail`，模拟器日志实测）；淡入只给其余四个字段，URL 行透明度恒 1。若把淡入拆到 TextInput 单体、PasteButton 静止，会造成行内视觉不同步，已否决。
- 重置时机：`phase` 回到 `closed`（面板已在屏外）时把字段 `appeared` 复位为 false——面板不可见，复位动画无观感。
- 快速重开（exiting 中 showInbox 又翻 true）：直接从当前位置 snap 到 closed 再走 entering，接受一次无动画跳变（罕见路径，正确性优先于连续性）。

### D5: 域名提示与批量块用「常驻 + 动画高度 + clip」（否决：条件插入 + 高度动画）

两类条件内容都改为**常驻节点 + `constraintSize` maxHeight 0↔上限 + opacity + clip(true)**，状态翻转包 `animateTo`（布局属性动画）：

- 域名提示：maxHeight 0↔18vp，对称 150ms。
- 批量块：外层 maxHeight 0↔包裹值（展开 180ms）+ 淡入；内部条目按 D4 手法级联（30ms/条，>6 条整组同帧）。内层 `Scroll` 的 `maxHeight: 216` 保持不动。

- 否决**条件插入后对高度做 animateTo**：条件插入帧没有旧值可插值，高度从 0 跳变即 AGENTS.md 记录的「条件渲染不动画」同族问题；常驻 + clip 是官方手风琴 FAQ 的推荐形态。
- 点条移除用 **dying-set**：点击时 `batchUrls` 立即 filter（计数/按钮文案即时更新，满足"数据即时生效"），同时把 url 放进 `dyingUrls`，渲染列表 = `batchUrls + dyingUrls`，dying 行经 `.animation` 把高度 44→0 + 淡出，播完后清出 dying 集合；其余条目因高度布局动画自然上滑补位。移除最后一条走批量块整体收起（maxHeight 回 0）。
- 否决**迁移 `List` + `animateDelete`**：为一处删除动画把 Scroll/Column 换 List，引入 List 自身布局语义（sticky/edgeEffect/嵌套滚动），影响面不成比例。

### D6: 键盘与焦点（维持现状 + 一处补口）

不自动聚焦（现行为），键盘仅用户点击输入行后弹起，级联期间点击即聚焦（满足规格"级联期间可交互"）。退场开始时若键盘仍弹出，`getUIContext().getFocusController().clearFocus()` 主动收键盘——常驻挂载后 TextInput 不会随卸载自动失焦，这是条件挂载时代"免费"获得、迁移后必须显式补上的一步。

### D7: 表单重置迁移到 @Monitor

删 `aboutToAppear` 里的 `urlText` 播种，改 `@Monitor('appState.showInbox')`——false→true 时播种 `inboxUrl`、清空标题/标签/备注/批量/`launchExit`。`aboutToAppear` 仅保留首次挂载播种（常驻挂载时 `showInbox` 可能已为 true，如分享直达冷启动）。

### D8: 断点呈现矩阵与响应式表单（走查反馈修订；否决：全断点统一居中、全断点统一底部）

- <700vp（含折叠屏合拢）：**贴底悬浮卡**（六轮反馈修订）：四角 16 圆角 + 左右/底 12vp 留边 + 去面板 BOTTOM 安全区扩展（遮罩独自承担沉浸）——方角全宽板起飞读作"掀幕布"（板 vs 物），圆角物化后发射自然；转场不变（下滑退场 / 深潜发射）。
- ≥700vp（折叠屏展开/平板/PC）：宿主 Stack 对齐由 `Bottom` 切 `Center`，卡片宽度档 700–999vp `min(84%, 600vp)`、≥1000vp `min(70%, 720vp)`；居中卡片圆角四角统一 16（底部停靠仅上圆角的现状只属于手机形态），`expandSafeArea` 的 BOTTOM 扩展收窄为仅遮罩持有（居中卡不贴屏底）。
- ≥1000vp 响应式表单：标题/标签并排一行（各 `layoutWeight(1)`），URL 行、备注、收下按钮通栏；两字段仍按原级联次序（i=1/i=2），仅空间并排。断点经 `@Param isWide/isLarge` 由 `Index.ets` 传入（同源断点），勿在组件内重建媒体查询。
- 转场轨迹全断点同构（家族曲线滑入 / 加速滑出 / 与进场同速上滑发射），位移载体统一为数值状态 `panelOffsetY`（见 D3）：手机隐藏 +900vp、宽屏 ±2000vp；面板本体无 scale/opacity 参与（三轮已删 scale 点缀）。**关闭态不做 `Visibility.None` 兜底**（二轮根因），几何离屏即隐藏；命中/无障碍沿用逐层 gate。**不使用面板级透明度**——面板是 PasteButton 祖先链，淡入会触安全组件约束（spec 双需求矛盾的收敛方案，亦是用户"滑动进入/向上发射"的字面诉求）；内容淡入由字段级联承担，下顿走嵌套内层数值节点。
- 否决**全断点统一居中**：手机单手拇指可达性要求底部停靠（HDS 半模态惯例）；否决**统一底部**：大屏底部停靠卡片浪费纵向空间且视觉重心过低（走查反馈）；否决**居中卡 vp 浮入 + 面板淡入淡出**：违反 PasteButton 祖先链透明度约束。

## Risks / Trade-offs

- [快速连开连关出现 snap 跳变] → D4 已定义：exiting 中重开直接 snap 回 entering；正确性优先，罕见路径不做插值补间。
- [常驻挂载后键盘不自动收起] → D6 退场即 `clearFocus()`；验收用例须含"键盘弹出状态下点遮罩关闭"。
- [批量块外层动画高度与内层 Scroll maxHeight:216 嵌套约束] → 实现时先验证嵌套 `constraintSize` 的插值表现；若外层动画异常，退化为外层不做高度动画、仅 opacity + `translate` 遮掩（视觉近似展开）。
- [dying 行播完未清理导致幽灵行] → dying 集合清理走与 ROW_COLLAPSE 等长的 setTimeout，且 phase 离开 open 时强制清空兜底。
- [弹簧 `.animation` 在 V2 隐式动画下的打断重放] → `springMotion` 官方支持用于 `animateTo`/`.animation`；实现后在真机验证连点开关的速度连续性。
- [toast 常驻化影响 Index 布局] → toast 常驻后必须 `HitTestMode.None` 且不占布局（Stack 内绝对定位语义不变），验收覆盖 toast 出现期间底层可点。
- [级联延迟期间用户已可点「收下」] → 规格允许（D4 仅视觉延迟）；空 URL 点击仍走现有校验 toast，无新增路径。
- [translate 跨单位插值回退离散（首轮已踩）+ Visibility.None 重现快照（二轮嫌疑主因）] → D3 数值位移状态全断点直绑 + 全生命周期禁用 Visibility 切换；组 6 任务含帧采样客观验证（点击后 ~150ms dump 应捕获半入屏面板），若数值直绑后仍瞬移，升级为渲染属性绑定层问题、单独立案。
- [发射退场生硬] → 下顿蓄力 + 与进场同速上滑 + launch 口味遮罩 200ms 慢离场；参数历经四~六轮设备调参，终值见 D3。
- [平板居中卡片被软键盘遮挡] → 先依赖窗口默认避让；验收含「平板点击备注行弹键盘」用例，避让不足再单点引入 KeyboardAvoidMode 调整。
- [两栏字段的级联与安全组件约束] → 标题/标签仍按原级联次序仅并排布局；URL 行始终通栏（PasteButton 祖先链约束不变）。

## Migration Plan

单 HAP 无数据迁移；改动集中在 `InboxSheet.ets`（主要）、`Index.ets`（挂载点 + toast）、`AppState.ets`（无签名变化，可能零改动）。回滚 = revert 单次提交。

## Open Questions

- 系统级"减弱动画"无障碍设置是否需要跟随（当前应用无任何动效跟随该设置的先例；若要跟随应作为全应用动效统一变更，不属本变更）。
