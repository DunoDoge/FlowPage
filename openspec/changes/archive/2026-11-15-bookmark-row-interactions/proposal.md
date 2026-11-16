# Proposal

## Why

书签行的两处高频交互拖了后腿：行内「…」操作面板把九个操作芯片用 Flex 换行平铺，条目多、命中区小，且「打开」「星标」与行尾常驻按钮/行主体点击重复；「移动到文件夹」在弹层内嵌 Miller 选择器，点击任意层级即触发移动，极易误选。同时列表缺少移动端惯用的左滑快捷操作，删除必须经开面板→确认弹窗两步。本次统一补齐：菜单收敛为单列、移动走独立选择页（下钻与确认分离）、左滑提供快捷操作与二级滑动直接删除、删除即时可撤回。

## What Changes

- **行操作面板改单列**：`QuickActionPanel`（`StreamHome.ets` 的 bindPopup）非回收站视图操作集收敛为：分享、多选、移动到文件夹、归档/取消归档、标记已读/未读、删除；移除「打开」与「加星标/取消星标」（星标仍由行尾星形按钮承担，打开仍由行主体点击承担）。回收站视图保留：恢复、彻底删除、多选。所有操作纵向单列排布，命中区与反馈遵循 interaction-feedback 现行要求。
- **「移动到文件夹」跳转独立选择页**：新增全屏覆盖页（复用 `bindContentCover` 模式）承载 Miller 多列层级浏览；点击层级仅下钻并高亮暂存，不触发移动；底部「移到这里」显式确认后才提交（含根目录选择）。行内菜单不再内嵌 FolderPicker。批量栏「移动到…」、详情编辑器、文件夹面板的内联选择器本次不动。
- **左滑快捷操作**：非回收站、非批量选择态的书签行支持左滑（`ListItem.swipeAction`），露出「分享」「删除」两个快捷操作；继续滑过阈值（二级滑动）抬手直接删除。
- **删除即软删 + 可撤回 toast**：左滑删除（按钮或二级滑动）执行软删除（回收站语义，30 天保留），toast 升级为可带操作按钮的形态，展示「撤回」按钮，点击调用 `restoreMany` 恢复；带操作的 toast 停留时长加长。菜单「删除」维持 AlertDialog 确认流程不变。
- **动效口径**：滑动交互的物理回弹交给系统 `swipeAction`（SwipeEdgeEffect.Spring，非线性）；行内按钮反馈、toast 浮现等仍走应用既有隐式 `FastOutSlowIn` 词汇表。

## Capabilities

### New Capabilities
- `stream-row-actions`: 书签行操作交互——行内「…」菜单的结构与操作集、左滑快捷操作与二级滑动删除、可撤回删除反馈（toast 操作按钮）。

### Modified Capabilities
- `bookmark-folders`: 「经菜单移动书签」的行为变更——行「…」菜单的「移动到文件夹」从弹层内嵌层级选择器（点击即移动）改为打开全屏层级选择页（点击仅下钻，显式确认后移动）；键盘可达性要求随选择页保留。
- `share-out`: 「分享」入口从三处扩为四处——新增书签行左滑操作区的分享按钮，行为与其余入口一致；回收站行仍不提供分享。

## Impact

- **代码**：`components/StreamHome.ets`（QuickActionPanel 重排、swipeAction 挂接、删除路径）、`components/BookmarkRow.ets` 或 List 项包装（swipeAction 配置、回收站/批量态禁用）、`components/FolderPicker.ets`（新增确认模式或新组件 `FolderPickerPage`）、`pages/Index.ets`（新增 bindContentCover、toast 渲染升级）、`common/AppState.ets`（toast 支持操作按钮、文件夹选择页开关状态）、`repository/FlowRepository.ets` 仅复用现有 `deleteMany/restoreMany/setBookmarkFolder`。
- **规格**：`interaction-feedback` 的反馈与热区要求自然延伸覆盖新菜单行与滑动按钮，无需修改其条文；`ui-copy` 文案风格约束照常适用。
- **测试**：`entry/src/ohosTest` 新增/扩展 List 相关套件（toast 操作、选择页确认语义、回收站禁滑）。
- **兼容性**：无数据模型、同步、权限变更；`main_pages.json` 不加路由（覆盖页经 Index 根部挂载）。
