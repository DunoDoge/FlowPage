# Tasks

## 1. 可撤回 toast 基建

- [x] 1.1 `entry/src/main/ets/common/AppState.ets`：toast 支持可选操作（显式 class 承载操作标签与回调，禁裸对象字面量）；带操作停留 5000ms、纯文本维持 2400ms；点击操作即执行回调并清空。在 `entry/src/ohosTest/ets/test/` 扩展或新增套件验证状态流转（带操作超时前不清空、点击后清空、新 toast 覆盖旧 toast），`hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap` 后真机 `aa test` 全绿
- [x] 1.2 `entry/src/main/ets/pages/Index.ets`：常驻 toast 节点升级——带操作时渲染 Row（文案 + 分隔 + 「撤回」按钮），仅按钮 hit-test 放开、其余区域保持 `None`；浮现动效沿用 180ms `FastOutSlowIn` rise-only。`check_ets_files` 校验改动文件 + `hvigorw assembleHap` 通过 + codelinter 0 error

## 2. 行内菜单单列化与操作集收敛

- [x] 2.1 `entry/src/main/ets/components/StreamHome.ets`：`QuickActionPanel` 从 `Flex wrap` 改 `Column` 单列（行高 ≥44vp、`onHover`/`onTouch` 驱动 `surface_alt` 反馈、危险项红字、键盘可达）；移除「打开」「加星标/取消星标」，非回收站集合 = 分享/多选/移动到文件夹/归档（或取消归档）/标记已读（或未读）/删除，回收站集合 = 恢复/彻底删除/多选。`check_ets_files` + `hvigorw assembleHap` 通过；模拟器目检：单列排布、归档/已读标签随状态切换、菜单行反馈无残留

## 3. 全屏文件夹选择页

- [x] 3.1 `entry/src/main/ets/components/FolderPicker.ets`：新增 `confirmMode` 参数——开启后 `pick()` 只做高亮暂存 + 下钻（含根目录行），MUST NOT 触发 `onPick`；详情编辑器/文件夹面板/批量栏三个既有使用点不传参、行为零变化。`check_ets_files` + `hvigorw assembleHap` 通过；目检三处内联选择器点击仍即时生效
- [x] 3.2 新增 `entry/src/main/ets/components/FolderPickerPage.ets`：标题栏（书签名 + 关闭）、`confirmMode` FolderPicker、底部「移到这里」确认条（未选中禁用、选中显示目标路径）；确认后经 `FlowRepository.setBookmarkFolder` 提交并 toast 结果。`check_ets_files` + `hvigorw assembleHap` 通过
- [x] 3.3 接线：`entry/src/main/ets/common/AppState.ets` 增加 `folderPickOpen` / `folderPickBookmark`（持有完整 Bookmark 对象而非裸 id：选择页需要标题与当前归属做同步初值，免挂载期异步查询；意图语义与 `folderPickBookmarkId` 等价）；`entry/src/main/ets/pages/Index.ets` 根部 `bindContentCover` 挂载选择页（`onWillDismiss` 支持系统返回，未确认离开零写入）；`StreamHome.ets` 菜单「移动到文件夹」改为关弹层开覆盖页，移除单笺 `bookmarkMoveOpen` 内嵌分支。UI 走查（免键盘路径）：点击层级仅下钻不移动、确认后归属更新并返回发起前界面、可选根目录、键盘可完成下钻与确认

## 4. 左滑快捷操作与二级滑动删除

- [x] 4.1 `entry/src/main/ets/components/StreamHome.ets`：ListItem 挂 `swipeAction`（end = 分享/删除），禁用谓词（回收站视图/批量选择态/已删行 end 为空）；「分享」复用 `ShareOut.shareBookmarks` 与 `shareLinkOf`；swipe 打开时关闭行内菜单弹层。`check_ets_files` + `hvigorw assembleHap` 通过；真机验证滑动与长按拖拽（`FolderDragSession`）不冲突，拖拽后无露出态残留
- [x] 4.2 二级删除与撤回：删除项 `SwipeActionItem.onAction`（长距删除区抬手触发）与删除按钮 onClick 统一走软删（`deleteMany`）+ 带「撤回」操作的 toast（回调走 `restoreMany`，失败 toast「恢复失败，请到回收站找回」）。UI 走查：超阈值抬手直接删除、未超阈值抬手不删除、撤回后书签恢复原位（含文件夹归属）、回收站/批量态不露出操作区、菜单「删除」仍走 AlertDialog 确认

## 5. 集成验证与文档

- [ ] 5.1 全量设备端回归：`hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap` + 双 hap `hdc install` + `aa test`（16 套件）全绿；`hvigorw assembleHap` 产物构建成功
  - 2026-11-15 归档时本机无连接设备（`hdc list targets` [Empty]）：主 hap 与 ohosTest hap 构建均绿、codelinter 0 error；双 hap 安装、`aa test` 与真机目检待有设备时补验——经用户批准延后归档
- [x] 5.2 门禁与易变事实：`codelinter -c code-linter.json5` 0 error；按 AGENTS.md 口径更新易变事实（行内菜单单列与操作集、左滑/二级删除入口、带撤回 toast、文件夹选择页 bindContentCover），`rg` 校对 AGENTS.md 中引用的规格名与 `openspec/specs/` 目录一致
