# Proposal

## Why

浏览器书签导入导出对文件夹的处理是失真的：导入时把整条文件夹路径（如 `书签栏/开发/前端`）当成一个标签写入标签表，污染标签列表；导出时又不拆分路径，输出一个名字里带斜杠的扁平文件夹，浏览器的原始书签结构被破坏。而文件夹结构在 `bookmark.folder_path` 里其实已完整保存、随同步走，只是从未在应用内露出。

用户已确认两个硬需求：**导入→导出 round-trip 结构无损**、**应用内可按文件夹浏览**。因此本变更把文件夹机制升格为一等公民，与标签共存：文件夹承载结构（来自浏览器、可回传），标签承载语义（用户手工标注）。

文件夹能力落地后暴露出第二个问题：独立文件夹页把「浏览流」和「浏览文件夹」拆成两个界面，用户整理文件夹必须离开流、在两个页面间来回跳转，而主页才是日常停留的地方。本变更随后把文件夹管理收进流笺主页，用长按拖拽直接改归属，消除这个第二浏览面。首版把树面板叠在流列表上方，走查反馈它占用流的可用高度、层级一深就挤压列表；因此把文件夹树移到最左侧页面栏，宽度不足时改用左上角按钮打开的左侧抽屉。

## What Changes

- **BREAKING**（开发期，无存量迁移负担）：新增 `folder` 表（`id` / `parent_id` / `name` / `position` / 同步脏标记列）作为文件夹唯一事实源；`bookmark.folder_path` 移除，改为 `bookmark.folder_id` 引用。
- **BREAKING**：`SyncRecord` schema 2 → 3：书签字段 `folderPath` 替换为 `folderId`。
- 文件夹成为第三种同步实体：远端新增 `FlowPage/v1/folders/` 集合，沿用既有 LWW + 墓碑机制（墓碑目录按 uuid 共用）。改名/移动文件夹只脏 1 行、1 次上传。
- 导入（Netscape HTML）：文件夹路径逐段 find-or-create 到 folder 表；**不再自动生成路径标签**；`ADD_DATE` 写入 `createdAt` 以保留排序信息。
- 导出（Netscape HTML）：按文件夹树嵌套重建 `<DL><H3>`（文件夹按 `position` 序、书签按 `createdAt` 序），round-trip 结构无损。
- 浏览器语义标记保真（6.2 round-trip 验收反馈）：导入捕获顶层 H3 的 `PERSONAL_TOOLBAR_FOLDER` / `UNFILED_BOOKMARKS_FOLDER` 记入 `folder.kind`（随 `FolderSyncRecord` schema 2 同步），导出回写标记属性——否则识别该标记的浏览器（Firefox/Edge 系）再导入时把「书签栏」嵌进自身书签栏，逐轮加深。
- 应用内文件夹管理并入流笺主页（**取代**已实现的独立文件夹页）：移除 `Pane.FOLDERS`、`FoldersPage` 与左侧导航的文件夹入口。文件夹树固定在最左侧页面栏：≥1000vp 停靠在既有导航栏内（导航项下方，栏宽 240→280vp，不新增列）；<1000vp 隐藏侧栏，主页左上角提供按钮打开左侧抽屉——抽屉顶部是与侧栏一致的主导航项（流笺/标签/同步/设置，文字与 ☰ 按钮同 20vp 缩进对齐），下方是同一棵树（抽屉宽 min(320vp, 84%)、全高、遮罩，点外部/返回/导航跳转/选中叶子文件夹后关闭）。主页头部不再显示 标签/同步/设置，只保留 ☰（窄屏）与「批量」。树占侧栏剩余高度并内部滚动，不设 40% 高度上限。树节点显示自身及全部子孙内的书签计数；点击任意文件夹行统一把流过滤到该文件夹的直属书签（不显示子文件夹内的书签，子孙内容经对应子文件夹行下钻到达），有子文件夹的行同时展开、再次点击收起且过滤保留（树中不显示展开箭头）；点根/全部清除过滤，「…」菜单的「在流中查看」保留为等价入口。
- 长按拖拽改归属：长按书签行或文件夹行直接进入拖拽；该行属于当前多选集合时拖整组，否则只拖该行。拖到文件夹行 = 移入该文件夹，拖到「根目录」投放区 = 移出到根；文件夹连同子树移动，书签只改 `folderId`。目标是所选文件夹自身或其后代时跳过并提示，目标等于当前父级视为无操作。**拖拽不改变同级排序**：书签仍按 `createdAt`、文件夹仍按 `position`。
- 行内操作入口重排：长按只负责拖拽，不再弹快捷操作；书签与文件夹行的操作改由行尾「…」按钮打开锚定面板（桌面右键打开同一面板）。文件夹操作面板承担新建子文件夹、改名、移动、删除、在流中查看；树底部提供根级「新建文件夹」。
- 主页多选同时覆盖书签与文件夹：可跨类型混合选择，拖拽已选行携带整组；批量栏保留移动到指定文件夹、移出一级、删除（一次确认汇总数量，级联走回收站）。
- 详情往返保留侧栏状态：从主页打开书签详情后返回，展开集合、树滚动位置与流位置保持不变；窄屏抽屉保持进入前的开合状态（不强制打开）；宽屏详情与主页并存时主页不得重建。
- 删除语义：删除文件夹级联软删除其中书签（确认弹窗），走既有回收站 + 墓碑机制。
- 树构建容忍最终一致性：悬空 `folder_id`（父未到达）暂不显示、导出落根目录；检测到环（双端同时互移）丢弃后更新边。

## Capabilities

### New Capabilities

- `bookmark-folders`: 文件夹树机制——本地存储与引用模型、主页最左栏文件夹树与窄屏抽屉、过滤、长按拖拽改归属、改名/移动/删除语义、作为同步实体的 LWW 与墓碑行为、悬空引用与环的容忍规则。
- `bookmark-transfer`: 浏览器书签导入导出——HTML 解析为文件夹树引用、不派生路径标签、嵌套结构导出、ADD_DATE 保真，round-trip 结构无损契约。

### Modified Capabilities

（无——现有规格仅 `docs-governance`，与本题无关。）

## Impact

- **数据层**：`entry/src/main/ets/core/db/Database.ets`（建表/索引/唯一约束 `UNIQUE(parent_id, name)`）、`BookmarkDao.ets`（folder_id 读写）、新增 `FolderDao`。
- **模型**：`Bookmark.ets`（`folderPath` → `folderId`）、`ImportResult.ets` / `ImportPreview.ets`（文件夹计数语义调整为文件夹数）。
- **同步**：`SyncRecord.ets`（schema 3）、`SyncEngine.ets`（文件夹集合的第二轮循环）、`WebDavTransport.ets`（`folders/` 的 list/get/put）、`SyncPlanner` 复用、`FlowRepository.upsertFromRemote` / `carryLocalFields` 适配。
- **解析**：`BookmarkHtmlParser.ets`（`ADD_DATE` 提取）。
- **仓库层**：`FlowRepository.ets` 的 `previewHtml` / `importHtml` / `exportHtml` / `exportJson`，及批量书签/文件夹操作方法（合并 notify）。
- **UI**：删除 `pages/FoldersPage.ets` 与 `Pane.FOLDERS`；新增 `components/FolderPanel.ets`（双形态文件夹树：侧栏停靠 / 窄屏抽屉，行「…」菜单、拖拽投放）；`NavigationRail.ets`（承载树、栏宽 280vp）、`Index.ets`（抽屉宿主、移除文件夹路由与详情返回 pane）、`StreamHome.ets`（移除内联面板、左上角抽屉按钮、流与拖拽会话）、`BookmarkRow.ets`（拖拽、行尾「…」入口）、`AppState`（抽屉开合、展开/滚动、跨列多选状态，移除文件夹页状态）；`FolderPicker.ets`（菜单/批量栏的移动入口，保留）、`DetailContent.ets`（文件夹 chips）、`TagsPage.ets`（文案）、`BookmarkQuery` / DAO 查询（直属等值过滤；子树 id 集仍用于级联删除与拖拽校验）。
- **测试**：`entry/src/ohosTest` 现有导入导出/同步套件随 schema 调整，新增文件夹 CRUD/树/同步/round-trip 用例；本次 UI 重构补设备端回归与手动走查（拖拽无纯函数测试入口时至少覆盖落点校验纯函数）。
