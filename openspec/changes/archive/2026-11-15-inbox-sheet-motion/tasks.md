# Tasks

## 1. 常驻挂载与相位状态机

- [x] 1.1 `entry/src/main/ets/pages/Index.ets`：`if (this.appState.showInbox) { InboxSheet() }` 改为无条件挂载；`InboxSheet.ets` 根 Stack/遮罩/面板按 phase 关闭态逐层 gate（`HitTestMode.None` + `enabled(false)` + `accessibilityLevel('no-hide-descendants')`，抽屉同款）。验证：check_ets_files 通过 + `hvigorw assembleHap` 通过，真机开关面板行为与现状一致（此步尚无动画，纯结构迁移零回归）
- [x] 1.2 `entry/src/main/ets/components/InboxSheet.ets`：新增 `@Local phase`（closed/entering/open/exiting/launching）与 `@Local launchExit`，`@Monitor('appState.showInbox')` 驱动相位迁移；表单播种/清空从 `aboutToAppear` 迁至 Monitor（保留首次挂载播种兜分享直达冷启动）。验证：check_ets_files + assembleHap 通过，真机验证关闭后重开表单全净、分享进入预填新值不残留旧值

## 2. 进出场转场与级联

- [x] 2.1 `InboxSheet.ets` 顶部动效常量组（design.md D3 全表）；遮罩 opacity 绑定 phase：进场 240ms `FastOutSlowIn` 淡入、退场 160ms 淡出，退场开始即撤遮罩命中。验证：check_ets_files + assembleHap，真机目检遮罩两条路径
- [x] 2.2 面板本体转场：进场 `springMotion(0.42, 0.75)` 上滑；普通退场 220ms `EaseIn` 下滑；launch 路径 90ms/+5vp 下顿后 220ms `EaseIn` 上滑离场；退场触发时 `clearFocus()` 收键盘。验证：check_ets_files + assembleHap，真机目检三条关闭路径（遮罩/关闭/保存成功）与键盘弹出态关闭
- [x] 2.3 表单字段级联：phase 翻入 open 时单状态翻转，各字段 `.animation({ delay: 120 + i*35, duration: 200, curve: FastOutSlowIn })` fade + 12vp 上浮；phase 回 closed 时复位（屏外无观感）；exiting 中重开直接 snap 回 entering。验证：check_ets_files + assembleHap，真机目检级联顺序、级联中点击「收下」即时响应、快速连开连关不死锁
- [x] 2.4 `Index.ets` toast 常驻化 + 进场浮现（opacity + 8vp 上浮，180ms `FastOutSlowIn`，`HitTestMode.None` 不吞底层点击）。验证：check_ets_files + assembleHap，真机目检「收下了」toast 浮起且出现期间底层可点

## 3. 面板内条件内容动效

- [x] 3.1 域名提示改常驻节点 + `constraintSize` maxHeight 0↔18vp + clip + opacity，`animateTo` 包状态翻转，出现/收起对称 150ms。验证：check_ets_files + assembleHap，真机目检粘贴合法链接展开、改写失效收起
- [x] 3.2 批量块容器改常驻 + maxHeight 0↔包裹值 + clip + 淡入（180ms），条目级联 30ms/条、上限 6 条其后整组同帧；验证内层 `Scroll` maxHeight:216 嵌套约束插值正常，异常则按 design.md 退化路径处理。验证：check_ets_files + assembleHap，真机目检粘贴 3 条与 20 条两档
- [x] 3.3 dying-set 点条移除：点击即从 `batchUrls` filter（计数/文案即时），url 入 `dyingUrls` 渲染 44vp→0 收缩（160ms），播完清出；phase 离开 open 时强制清空 dying 集合兜底；移除最后一条走整块收起。验证：check_ets_files + assembleHap，真机目检点条补位、移到空整块收起、移除动画未播完即关闭面板无幽灵行

## 4. 回归验收与文档

- [x] 4.1 `codelinter -c code-linter.json5` 全量通过（不高于现状 0 error / 1 性能建议）。验证：命令输出
- [x] 4.2 设备端测试回归：按 AGENTS.md 流程构建 ohosTest HAP 并安装运行（`aa test` …OpenHarmonyTestRunner），16 套件全绿无回归。验证：测试输出 202 用例 0 失败
- [x] 4.3 手工验收：按 `openspec/changes/inbox-sheet-motion/specs/inbox-motion/spec.md` 场景逐条走查（含深浅色、<700vp 手机壳与 ≥1000vp 三栏、2in1 鼠标路径）。验证：逐场景在真机/模拟器复现通过（六轮真机反馈 + 2026-11-15 2in1 收窄窗像素级验证收口；终稿参数：进/出场 400/300ms）
- [x] 4.4 更新 `AGENTS.md` 收笺面板易变事实（常驻挂载、相位状态机、动效常量位置、toast 常驻化）。验证：AGENTS.md 表述与 `InboxSheet.ets`/`Index.ets` 现状一致

## 5. 修订：断点呈现矩阵与轨迹修复（2026-11 走查反馈）

- [x] 5.1 `entry/src/main/ets/components/InboxSheet.ets` + `entry/src/main/ets/pages/Index.ets`：断点呈现矩阵——`Index` 向 `InboxSheet` 传 `@Param isWide/isLarge`（同源断点）；≥700vp 宿主 Stack 对齐切 `Center`、卡片宽 `min(84%, 600vp)` / `min(70%, 720vp)`、四角圆角 16、BOTTOM 安全区扩展收窄为仅遮罩；≥1000vp 标题/标签两栏响应式（各 `layoutWeight(1)`，级联次序不变）。验证：check_ets_files + `hvigorw assembleHap`，模拟器宽窗目检居中/宽度档/两栏与手机壳底部形态不回归
- [x] 5.2 `InboxSheet.ets` 轨迹单位自洽：手机端外层 translate `'100%'↔'0%'↔'-100%'` 百分比全程（`'0%'` 非裸 `'0'`）、`+5vp` 下顿迁至内层嵌套节点（vp）；宽屏居中卡外层固定 `WIDE_TRAVEL_VP`（2000vp）同单位离屏 + 进场 scale 0.97→1 点缀，面板全程无 opacity（安全组件祖先链约束）。验证：check_ets_files + assembleHap，逐断点目检进场滑动与发射全程位移连续（不再瞬移）
- [x] 5.3 发射可见性与回归收口：`INBOX_LAUNCH_RISE` 220→260ms；`codelinter -c code-linter.json5` 0 error；ohosTest 全套回归（225 用例 0 失败）；更新 `AGENTS.md` 断点矩阵与单位自洽事实。验证：命令输出 + 测试输出

## 6. 修订：数值位移状态与发射节奏（二轮走查反馈）

- [x] 6.1 `entry/src/main/ets/components/InboxSheet.ets` 数值位移重构：面板位移改 `@Local panelOffsetY: number` 数值状态直绑（`.translate({ y: this.panelOffsetY })`），`beginEnter/beginDismiss/beginLaunch` 的 `animateTo` 闭包写数值目标（0 / 手机 `INBOX_TRAVEL_PHONE`=900vp / 宽屏 `WIDE_TRAVEL_VP`=2000vp 及负值）；**删除关闭态 `Visibility.None`**（几何离屏即隐藏，gate 不变）；百分比字符串路径全部移除。验证：check_ets_files + `hvigorw assembleHap`，设备目检进场为连续滑动（不再瞬移）
- [x] 6.2 发射节奏重调：`INBOX_LAUNCH_DIP` 90→70ms；`INBOX_LAUNCH_RISE` 260ms `EaseIn` → 300ms `curves.cubicBezierCurve(0.2, 0.7, 0.4, 1)`（快起）；launch 口味遮罩淡出 160→200ms（dismiss 维持 160ms）。验证：check_ets_files + assembleHap，设备目检发射起步即走、全程舒展
- [x] 6.3 帧采样客观验证 + 回归：打开面板后 ~150ms `uitest dumpLayout` 应捕获半入屏面板（bounds 在屏内但非终位，证明动画存在而非瞬移）；codelinter 0 error；ohosTest 全套 0 失败；更新 `AGENTS.md`（数值位移状态、禁 Visibility/百分比、发射曲线）。验证：dump 输出 + 命令输出。（注：dumpLayout 看不见渲染侧 translate，帧采样方法学失效，改 onFinish 探针——但探针误测了伴随 scale，见组 7）

## 7. 修订：隐式 .animation 驱动与去弹簧（三轮走查反馈）

- [x] 7.1 `InboxSheet.ets` 机制切换：外层节点挂相位参数化 `.animation(this.motionParams())`（进场 320ms `FastOutSlowIn` / 退场 220ms `EaseIn` / 发射 300ms 快起贝塞尔），`animateTo` 降级为相位交接兜底；删除弹簧常量与 `wideScale()`（1s 伴随弹簧重绘=级联卡顿源）；下顿节点补隐式动画；级联收紧 90/30/180ms。验证：check_ets_files + `hvigorw assembleHap`，真机目检面板自屏下滑入、级联顺滑不卡
- [x] 7.2 回归收口：ohosTest 225 用例 0 失败、codelinter 0 error、`AGENTS.md` 更新（隐式驱动事实、animateTo 面板级失效教训、探针方法学局限）。验证：命令输出
- [x] 7.3 归位零时长与确定性时序（四轮反馈「先向上又向下滑动」）：`motionParams()` 增加 CLOSED 分支 `duration: 0`（发射终位 -hidden 与归位 +hidden 跨 4000vp 的屏外跳变曾被隐式动画当成转场播成"向下滑过屏幕"）；`beginEnter/beginDismiss/beginLaunch` 全部改纯状态写 + 带守卫 setTimeout 链，退役残余 `animateTo`（onFinish 计时不可靠）。验证：check_ets_files + assembleHap + ohosTest 225 用例 + 设备冒烟（发射退场/遮罩关闭/重开/无 jscrash）
- [x] 7.4 深潜发射（五轮反馈「底部割裂感」）：下顿改断点分档（手机 32vp / 宽屏 6vp）、时长 100ms `FastOutSlowIn`（压缩蓄力），上飞维持 320ms 与进场同速；宽屏形态不变。验证：check_ets_files + assembleHap + ohosTest 225 用例 + 设备冒烟（发射退场/toast/无 jscrash/安全组件 0 失败）
- [x] 7.5 手机贴底悬浮卡（六轮反馈「方角起飞突兀」）：面板四角 16 圆角 + 左右/底 12vp 留边（`panelMargin()`）、去面板 `expandSafeArea` BOTTOM（遮罩独自沉浸）、`panelRadius()` 移除统一 `.borderRadius(16)`；新增 `specs/immersive-ui/spec.md` MODIFIED delta（收笺面板移出屏幕边缘容器清单）。验证：check_ets_files + assembleHap + ohosTest 225 用例 + codelinter 0 error
