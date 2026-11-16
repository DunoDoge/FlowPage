# Design

## Context

现状（见 proposal.md - Why）：`StreamHome.ets` 的行内操作面板是 `bindPopup` + `Flex wrap` 芯片，九项操作换行平铺；「移动到文件夹」在弹层内切换为内嵌 `FolderPicker`（Miller 多列），`pick()` 点击即触发 `onPick` 提交移动；toast 为纯文本常驻节点（`HitTestMode.None`、2400ms 自清）；删除只有菜单→AlertDialog 确认一条路径。约束：应用动效词汇表统一为「隐式 `.animation` + `FastOutSlowIn`」（抽屉、toast、PaneEntrance、InboxSheet 全部如此）；`main_pages.json` 仅 2 路由、手机 `Navigation` 只 push `detail`；全屏层只有阅读层走 `bindContentCover` 先例。

## Goals / Non-Goals

**Goals:**
- 菜单单列 + 操作集收敛，交互入口与高频手势（左滑）各归其位
- 下钻与确认分离的全屏文件夹选择页，消除误移动
- 左滑删除全路径可撤回，且滑动动效非线性、与应用词汇表口径可解释
- 改动限定在 UI 层与既有 Repository API（`deleteMany` / `restoreMany` / `setBookmarkFolder` / `ShareOut.shareBookmarks`）

**Non-Goals:**
- 批量栏「移动到…」、详情编辑器、文件夹面板的内联选择器不改（维持点击即选）
- 菜单「删除」不改为撤回模式（维持 AlertDialog 确认）
- 不新增路由页、不改 `main_pages.json`、不动数据模型与同步

## Decisions

### D1 左滑用内建 `ListItem.swipeAction`，不自研手势
`ListItem.swipeAction({ end: [分享, 删除] })`，删除项配 `SwipeActionItem.onAction`（进入长距删除区抬手触发，默认阈值 56vp，可 `actionAreaDistance` 调整）实现二级滑动直接删除；`edgeEffect` 保持默认 `Spring`——展开/回弹即系统弹簧曲线（非线性）。
- 备选（否决）：自研 `PanGesture` + `translate` + 隐式 `FastOutSlowIn` 吸附。曲线可与词汇表完全统一，但需自行解决与 List 纵向滚动的手势仲裁、与行内 `draggable`（长按拖拽）的共存、弹层互斥、键盘/读屏可达，全是系统已解的问题；InboxSheet 的教训也表明自管位移动画在该代码库易踩事务捕获坑。手势物理交给系统，应用词汇表管周边反馈（菜单行、按钮、toast），两者职责不同、不冲突。
- 官方 FAQ 已确认 `onAction` 的长距删除区行为即「继续滑动撑满后抬手触发」，与二级滑动诉求天然一致。

### D2 可撤回 toast = 扩展现有 AppState.toast，不另建组件
`AppState` 增加带操作的签名（文本 + 操作标签 + 回调，ArkTS 用显式 class 而非裸对象字面量）；`Index` 的常驻 toast 节点升级：有操作时渲染 `Row`（文案 + 分隔 + 「撤回」按钮），仅此时放开 hit-test（按钮 `Default`，其余区域仍 `None`），停留时长从 2400ms 加长到 5000ms（真机可调），点击「撤回」立即执行回调并清空。浮现动效沿用现有 180ms `FastOutSlowIn` rise-only。
- 备选（否决）：独立 snackbar 组件。多一套常驻基础设施与动效词汇，且现有 toast 已常驻挂载、改造点极小（文案节点换 Row + 条件 hit-test）。
- 撤回实现直接调 `FlowRepository.restoreMany`（已含文件夹链恢复），恢复后经 `notify()` → `refreshTick` 走常规刷新，`ForEach` 键含 `rev|updatedAt`，行自然回位。

### D3 菜单改 Column 单列，操作集收敛
`QuickActionPanel` 从 `Flex wrap` 改 `Column`，每行全宽、高 ≥44vp、`onHover`/`onTouch` 驱动 `surface_alt` 反馈（沿用现行手法）；移除「打开」「加星标」两项，其余保持既有 `ActionChip` 语义（危险项红字）。
- 备选（否决）：系统 Menu/ContextMenu。项目无先例，样式与单列口径不可控，且右键入口已与 `bindPopup` 同源（bookmark-folders 规格），换载体属无关扩散。

### D4 文件夹选择页 = FolderPicker 确认模式 + Index 根部 bindContentCover
`FolderPicker` 增加 `confirmMode` 参数：开启时 `pick()` 只做「高亮暂存 + 下钻」（含根目录行），不触发 `onPick`；由新组件 `FolderPickerPage` 提供标题栏（书签名 + 返回）、Miller 列表区、底部「移到这里」确认条（未选中前禁用，选中显示目标路径）——确认时才提交 `onPick` 并关闭页面。三个内联使用点不传该参数，行为零变化。
- 挂载点：`Index` 根部 `bindContentCover`（与阅读层同模式），`AppState` 增加 `folderPickOpen` + `folderPickBookmarkId` 意图状态；各断点均全屏覆盖（用户已选）。
- 备选（否决 1）：push 进 Navigation 栈——破坏「手机 Navigation 只 push detail」与 `main_pages.json` 双路由约定，宽断点还需另想宿主。
- 备选（否决 2）：半模态 Sheet——手机习惯但宽屏形态分裂，且与全屏 Miller 多列浏览（列多时横向滚动）不匹配。
- 弹层互斥：点「移动到文件夹」先关 `bindPopup` 再开覆盖页；`onWillDismiss` 支持系统返回手势，未确认离开不产生任何写。

### D5 禁用与互斥的单一谓词
左滑可用性收敛为一个谓词（非 `TRASH` 视图 && 非批量选择态 && 行未删除），`swipeAction` 的 options 据此构造（禁用时 `end` 为空并保持无手势）；`FolderDragSession` 活跃或菜单弹层打开时不响应（实测确认系统手势仲裁后，兜底在 swipe `onStateChange` 打开时置 `showActions=false` 关菜单）。
- 备选（否决）：双分支渲染两套 ListItem。列表项代码翻倍且键值维护成本高。

## Risks / Trade-offs

- [swipeAction 与 draggable 手势竞争] → 系统仲裁：swipe 消费横向 pan、拖拽需长按起手，理论不冲突；真机验证「先滑出再长按拖拽」路径，必要时拖拽会话开始时 `closeAllSwipeActions()` 收起所有露出态。
- [禁用态下 end 空数组是否残留微滑动] → 真机验证；不满足则该行退化为条件渲染两套 `swipeAction` 配置（仅 options 不同，行主体仍单份）。
- [撤回窗口内书签被同步删除/覆盖] → `restoreMany` 幂等；失败时 toast「恢复失败，请到回收站找回」兜底。
- [toast 放开 hit-test 遮挡底部] → 仅带操作时放开、节点尺寸小、5s 超时自动收回；按钮以外区域保持 `None` 不拦截。
- [弹层与滑动同时触发的状态错乱] → swipe 开始即关菜单；菜单打开时滑动视为「点外部」由 `autoCancel` 关闭，两向互斥。
- [系统弹簧曲线 ≠ 应用 FastOutSlowIn] → 有意取舍：手势物理属系统交互惯性（与系统列表一致），周边反馈仍走应用词汇表；在 AGENTS.md 动效口径处补一句说明。

## Migration Plan

纯 UI 行为变更，无数据/权限/路由迁移。回滚 = 还原涉及文件（`StreamHome` / `BookmarkRow` / `FolderPicker` / `Index` / `AppState` / 新增 `FolderPickerPage`）即可，Repository 零改动。

## Open Questions

- 带操作 toast 的停留时长（拟定 5000ms）与撤回按钮文案（「撤回」）——真机手感可微调，不影响规格。
- `actionAreaDistance` 是否需要显式钉值（默认 56vp）——实现时按真机手感定。
