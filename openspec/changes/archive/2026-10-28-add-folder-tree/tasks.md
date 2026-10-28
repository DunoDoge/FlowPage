# Tasks

## 1. 数据层 schema

- [x] 1.1 在 `entry/src/main/ets/core/db/Database.ets` 新增 `SQL_FOLDER` 建表（id/parent_id/name/position/created_at/updated_at/rev/dirty/remote_etag/deleted），`SQL_BOOKMARK` 以 `folder_id TEXT NOT NULL DEFAULT ''` 替换 `folder_path`，新增部分唯一索引 `idx_folder_parent_name`（`WHERE deleted = 0`，下发失败吞异常并回退应用层查重）、`idx_bookmark_folder`，`applySchema` 加吞异常 `DROP COLUMN folder_path` 兜底，`reset` 清空 folder 表；以 `entry/src/ohosTest` 现有数据库/同步套件通过 + check_ets_files + hvigorw assembleHap 收尾
- [x] 1.2 在 `entry/src/ohosTest` 为 folder schema 补用例：建表幂等、部分唯一索引生效（软删后可重建同名）、旧库列兜底不抛错；以该套件 hdc 设备端运行通过收尾

## 2. 模型与 DAO

- [x] 2.1 新增 `entry/src/main/ets/model/Folder.ets`（`@ObservedV2 Folder` 与树节点 `FolderNode`：folder + children + 递归计数），`entry/src/main/ets/model/Bookmark.ets` 以 `folderId` 替换 `folderPath`；check_ets_files + hvigorw assembleHap 收尾
- [x] 2.2 新增 `entry/src/main/ets/core/db/FolderDao.ets`：CRUD、`findOrCreate(parentId, name)`（带 `Map` 缓存供导入批处理）、树构建纯函数（悬空子树过滤、环检测断较新边）、子树 id 集收集、改名/移动（拒绝移入自身子孙）、级联软删除（子孙 + 成员书签 + 墓碑）；在 `entry/src/ohosTest` 补树构建单测（空树/深树/悬空/环/级联删除/同父同名拒绝）并设备端跑通，check_ets_files + hvigorw assembleHap 收尾
- [x] 2.3 `entry/src/main/ets/core/db/BookmarkDao.ets`：行读写改 `folder_id`，查询对象与 SQL 支持 `folder_id IN (?)` 子树过滤，级联软删除/恢复接入 FolderDao 语义；相关 ohosTest 用例更新通过，check_ets_files + hvigorw assembleHap 收尾（子树过滤查询口径已在 15 节修订为直属等值）

## 3. 同步层

- [x] 3.1 `entry/src/main/ets/core/sync/SyncRecord.ets` schema 2→3（`folderPath` → `folderId`，`parse` 对 schema<3 回退空 folderId），新增 `FolderSyncRecord`（schema/id/parentId/name/position/createdAt/updatedAt/rev/deviceId 及 parse/toJson），`FlowRepository.carryLocalFields` 分支简化；schema 回退用例进 ohosTest，check_ets_files + hvigorw assembleHap 收尾
- [x] 3.2 `entry/src/main/ets/core/sync/WebDavTransport.ets`：`ensureBase` 增 `FlowPage/v1/folders/` MKCOL，新增/泛化 folders 集合的 list/get/put（复用 etag 回填与 If-Match），墓碑沿用现有目录；check_ets_files + hvigorw assembleHap 收尾
- [x] 3.3 `SyncEngine.ets` 抽出单实体类型同步 worker（书签/文件夹注入各自回调），文件夹走同构 plan/upload/download 流程，墓碑和解合并扫描两种 id；`FlowRepository` 增加 `upsertFolderFromRemote`（LWW + etag 回填竞态防护，同书签 rev/updatedAt 模式）；在 `entry/src/ohosTest` 同步套件补文件夹 LWW 改名、删除墓碑、乱序到达（书签先于文件夹）用例并设备端跑通，check_ets_files + hvigorw assembleHap 收尾

## 4. 导入导出

- [x] 4.1 `entry/src/main/ets/core/parser/BookmarkHtmlParser.ets`：提取 `ADD_DATE` 到 `ImportedBookmark`（`entry/src/main/ets/model/ImportResult.ets`）新增字段，文件夹段解析保持逐段输出；解析用例更新，check_ets_files + hvigorw assembleHap 收尾
- [x] 4.2 `FlowRepository.previewHtml/importHtml`：路径段经 `FolderDao.findOrCreate` 落 folder 表、书签赋 `folderId`、删除自动打标逻辑与 `ImportOptions.keepFolders`、`createdAt` 取 ADD_DATE，`ImportPreview/ImportResult` 计数改为文件夹链计数；ohosTest 导入用例更新（嵌套建链、同父同名合并、不派生标签、ADD_DATE 保真），check_ets_files + hvigorw assembleHap 收尾
- [x] 4.3 `FlowRepository.exportHtml/exportJson`：按内存树嵌套输出（文件夹 position 序、书签 createdAt 序、悬空落根、名字转义），JSON 导出携带文件夹路径；ohosTest round-trip 用例（导入→导出层级与名字无损、斜杠名文件夹原样、标签不进 HTML），check_ets_files + hvigorw assembleHap 收尾

## 5. UI

- [x] 5.1 `entry/src/main/ets/common/Constants.ets` 增 `Pane.FOLDERS`、`AppState` 增 `folderFilter`（与 tagFilter 同构），`pages/Index.ets` 手机端 push / 宽屏 pane 路由，`components/NavigationRail.ets` 增文件夹入口；check_ets_files + hvigorw assembleHap 收尾（`Pane.FOLDERS` 与导航入口已在 13.1 移除，`folderFilter` 保留）
- [x] 5.2 新增 `entry/src/main/ets/components/FolderPicker.ets` 层级选择器（逐层级列展示，书签编辑与移动文件夹目标共用；移动目标禁用自身及子孙；支持选根/清除/新建）；`components/DetailContent.ets` 编辑器文件夹 chips 改为路径面包屑 + `bindSheet` 弹 FolderPicker，查看态文件夹 chip 保持设 `folderFilter`；`pages/TagsPage.ets` 文案改为双机制并存表述；手动走查详情页改文件夹后流过滤即时生效，check_ets_files + hvigorw assembleHap 收尾（实际以内联 FolderPicker 替代 bindSheet；走查并入 6.2 端到端验收）
- [x] 5.3 重写 `entry/src/main/ets/pages/FoldersPage.ets` 为多列层级视图：横向 Scroll + 定宽列（手机约 72% 屏宽、宽屏自适应多列），每列子文件夹（position 序、子孙计数）+ 直属书签（createdAt 序），根列显示根书签；点文件夹展开下一列并高亮选中链、点祖先列回退；点书签打开详情（手机 push / 宽屏切 `Pane.DETAIL`）；列头「在流中查看」设 `folderFilter` 并回详情 pane；列尾「新建文件夹」（同父同名拒绝提示）；改名/删除沿用行内编辑、移动目标走 FolderPicker（5.2）；`FlowRepository` 新增直属书签列表查询（folder_id 等值、非子树）；模拟器/真机手动走查列浏览/回退/过滤/新建/移动，check_ets_files + hvigorw assembleHap 收尾（走查并入 6.2 端到端验收；设备端 152 用例通过；6.2 验收发现最深层列装载与选中高亮未可靠生效，修复见 7.1/7.2；独立页形态已被 13.1–13.3 取代）

## 6. 集成验证

- [x] 6.1 全量设备端回归：`hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap` 构建并按 AGENTS.md 流程安装运行 12+ 套件（含新增文件夹/同步/round-trip 用例）全部通过
- [x] 6.2 端到端 round-trip 手动验收：真实浏览器导出 HTML → 导入 → 主页文件夹树结构一致 → 导出 HTML → 浏览器导入，层级与文件夹名无损；并完成主页交互走查（左侧栏树：宽屏停靠、窄屏左上角按钮抽屉，展开/收起/过滤、新建/改名/删除、单条与多选拖拽（书签与文件夹、根区、非法落点、取消）、详情往返保留展开与滚动、宽屏与手机布局），`codelinter -c code-linter.json5` 0 error 收尾

## 7. 验收修复与批量/快捷操作（6.2 反馈）

- [x] 7.1 修复最深列直属书签装载：`FoldersPage.ets` 的 `FolderColumn` 响应式化（@ObservedV2 + @Trace books/booksLoaded 或等价手段），`loadBooks` generation 早退后不得静默放弃未装载列；走查任一深层点选首切即显示直属书签；check_ets_files + hvigorw assembleHap 收尾
- [x] 7.2 修复选中链高亮：换用与列底色可辨的选中背景 token（base/dark 成对维护），确保 chainIds 变更驱动各列文件夹行重绘；走查下钻/回退后高亮链正确；check_ets_files + hvigorw assembleHap 收尾
- [x] 7.3 `FlowRepository.ets` 批量方法（batchMove / batchMoveOut / batchDelete：书签与文件夹混合、移出一级=父级的父级、目标为所选文件夹自身或子孙时跳过提示、删除一次确认汇总、单次 notify）；ohosTest 补批量用例（混合移动、移出一级含根跳过、批量级联删除墓碑完整）；check_ets_files + hvigorw assembleHap 收尾
- [x] 7.4 `FoldersPage.ets` 多选模式（页面级「批量」入口、勾选独立点击区、行点击保留原行为）与操作栏（移动/移出/删除/完成）；check_ets_files + hvigorw assembleHap 收尾
- [x] 7.5 `FoldersPage.ets` 行级快捷菜单：bindContextMenu（RightClick + LongPress 同一菜单），文件夹行（改名/移动/删除/在流中查看/新建子文件夹）与书签行（打开/移动到文件夹/删除/复制链接），复用既有处理函数；check_ets_files + hvigorw assembleHap 收尾（该功能经三轮走查取消，清理见 10.1）

## 8. 同层多展开（走查后修订）

- [x] 8.1 `FoldersPage.ets` 展开模型从单选中链（chainIds）改为展开集合（expandedIds）：列 = 根列 + 每个已展开文件夹一列、按树 DFS 序插入（子列紧随父列），点未展开文件夹展开、点已展开文件夹收起其列连同已展开子孙列，滚动定位到新展开列（替换固定 scrollEdge End），移动/新建后的选中维护改为对 expandedIds 的展开操作；7.1 的 FolderColumn 响应式与全列装载不得回退；check_ets_files + hvigorw assembleHap 收尾（DEVECO_HOME 缺失致 check_ets_files 不可用，以 hvigorw assembleHap 全量类型检查 + codelinter 0 error 替代；列 ForEach 键改为 column.id 保证 DFS 重排下复用列实例）
- [x] 8.2 展开态高亮复用 7.2 的可辨背景 token（base/dark 成对），expandedIds 变化驱动各列文件夹行重绘；走查同层多展开并存、收起连带子孙、深树下钻后高亮与直属书签装载正确；check_ets_files + hvigorw assembleHap 收尾（走查并入 6.2 端到端验收）

## 9. 同层分段共列与快捷菜单修复（二轮走查反馈）

- [x] 9.1 `FoldersPage.ets` 列模型从「每个已展开文件夹一列（DFS 序）」改为「每层一列、列内分段」：LevelColumn（按深度复用）持有 FolderSegment（按文件夹 id 复用，沿用 @ObservedV2 + @Trace），层级 k 列 = 全部已展开第 k 层文件夹按树序分段（段头=文件夹名+在流中查看，段内=子文件夹+直属书签+新建文件夹行），点未展开文件夹在其层级列追加段、列不存在则右侧新建，点已展开文件夹移除其段连同子孙段，滚动定位到目标层级列（scrollToSegment）；7.1 的响应式与全段装载语义不变（loadBooks 改按段装载）；hvigorw assembleHap + codelinter 0 error 收尾（DEVECO_HOME 缺失致 check_ets_files 不可用，同 8.1 以全量类型检查替代）
- [x] 9.2 修复行级快捷菜单不弹出：根因是连续两次 bindContextMenu 后调覆盖先调（RightClick 绑定被 LongPress 覆盖）且 ResponseType 不支持鼠标长按，鼠标场景两类触发全部失效；改用 bindContextMenuWithResponse 单次绑定（API 23+，Builder 零参闭包即可满足 CustomBuilderT<ResponseType>，长按+右键触发同一菜单），文件夹行与书签行同改；hvigorw assembleHap + codelinter 0 error 收尾（真机/模拟器右键与触屏长按走查并入 6.2 端到端验收）（修复后仍不可靠弹出，经三轮走查取消，清理见 10.1）

## 10. 三轮走查反馈（详情往返、列对齐、取消快捷菜单）

- [x] 10.1 取消行级快捷菜单：移除 `FoldersPage.ets` 两处 `bindContextMenuWithResponse` 绑定（FolderRow / BookRow）与 `FolderMenu` / `BookMenu` Builder，及仅菜单使用的处理函数（`viewNodeInStream` / `createChildOf` / `startBookMove` 等，页面内既有入口保留的不动）；hvigorw assembleHap + codelinter 0 error 收尾
- [x] 10.2 详情往返保留浏览状态：`expandedIds`（与横向滚动位置）提升至 AppState（@Trace）或等价保活手段，手机滑动/系统返回与 2in1 ESC（详情返回目标为进入前的 FOLDERS pane）均回到文件夹页且展开分段、直属书签装载不回退；7.1/8.x 的响应式与全段装载语义不得回退；真机/模拟器走查手机往返 ≥2 次与 2in1 ESC；check_ets_files（不可用时以全量类型检查替代）+ hvigorw assembleHap 收尾（真机/模拟器走查并入 6.2 端到端验收）
- [x] 10.3 列对齐修正：外层横向 Scroll 与列内纵向 Scroll 显式靠左/顶部对齐（ArkUI Scroll 内容小于视口时默认整体居中），列总宽不足一屏时贴左、列内短分段自顶部排列；走查根列/多列/短列三种形态；check_ets_files（不可用时以全量类型检查替代）+ hvigorw assembleHap 收尾（走查并入 6.2 端到端验收）

## 11. 浏览器语义标记保真（6.2 round-trip 验收反馈，D13）

- [x] 11.1 `Database.ets` SQL_FOLDER 加 `kind TEXT NOT NULL DEFAULT ''` 列 + `applySchema` 吞异常 ALTER（folder 版 addColumn），`model/Folder.ets` 加 kind 字段，`FolderDao.ets` 行读写 kind 与幂等 `setKind`（kind 不变不 bump rev/updatedAt/dirty）；ohosTest 建表幂等与旧库加列用例更新，check_ets_files + hvigorw assembleHap 收尾
- [x] 11.2 `BookmarkHtmlParser.ets` 顶层 H3（栈深 ≤1）捕获 `PERSONAL_TOOLBAR_FOLDER` / `UNFILED_BOOKMARKS_FOLDER` 到 `ParsedBookmarks.topMarks`（同名首个生效、深层忽略）；`FlowRepository.importHtml` 对 `segments[0]` 命中者 setKind（幂等）；ohosTest 导入用例补标记捕获与二次导入不增 rev，check_ets_files + hvigorw assembleHap 收尾
- [x] 11.3 `FolderSyncRecord.ets` schema 1→2 加 kind（parse 旧记录回退 ''），`exportHtml` emitFolder 按 kind 回写标记属性、exportJson 的 ExportFolder 携带 kind；ohosTest 补 round-trip 标记用例（含标记导出带属性、无标记不携带）与 kind 同步用例，check_ets_files + hvigorw assembleHap 收尾（设备端 163/163 通过）

## 12. 验收修复：恢复书签连带恢复文件夹链（6.2 反馈）

- [x] 12.1 修复删除文件夹后恢复书签丢失归属：`FolderDao.restoreChain`（沿祖先链复活软删除文件夹、同父同名占用时去重名、缺行/环容忍），`FlowRepository.restore/restoreMany` 去重后逐链复活，`upsertFromRemote` 落地存活书签记录时同样复活链（不 notify，随 afterSync 刷新）；ohosTest 补 6 用例（链恢复、共享祖先单次复活 rev 校验、同名去重、悬空容忍、活文件夹不动、远端恢复记录）；169/169 设备端通过，hvigorw assembleHap + codelinter 0 error 收尾
- [x] 12.2 修复文件夹页计数不随批量删除/移动/回收站恢复即时刷新：load() 重建 FolderNode 对象但 ForEach 键（folder.id/book.id）不变，ArkUI 复用旧行致 totalCount/名称陈旧；文件夹行键改为 `id|name|totalCount`、书签行键改为 `id|title`，显示内容变化即重建行（顺带修复行内改名与书签标题陈旧）；hvigorw assembleHap + codelinter 0 error 收尾（纯渲染修复、无数据层变化，计数即时性并入 6.2 走查复核；「移入一级」经确认不做）

## 13. 合并文件夹页到主页与长按拖拽（取代独立页形态）

本节取代以下任务中关于独立 `FoldersPage` 的形态：5.3、7.1、7.2、7.4、8.1、8.2、9.1、9.2、10.1、10.2、10.3、12.2。它们当时已完成，代码在 13.1 删除；数据层、同步、导入导出、`batch*` 方法与 `FolderPicker` 不受影响，继续复用。另：13.2/13.3 的「主页内嵌、与流上下堆叠」形态经走查否决，由第 14 节取代；13.8 的走查口径以 14.6 为准。

- [x] 13.1 移除独立文件夹页：删除 `entry/src/main/ets/pages/FoldersPage.ets`；移除 `common/Constants.ets` 的 `Pane.FOLDERS`、`pages/Index.ets` 两处 FoldersPage 分支与 `detailReturnPane` 文件夹返回逻辑、`components/NavigationRail.ets` 的「文件夹」项、`StreamHome` 头部「文件夹」入口；保留 `FolderPicker`；`check_ets_files` + `hvigorw assembleHap` + `codelinter -c code-linter.json5` 收尾（grep 确认无 FoldersPage / Pane.FOLDERS 残留）
- [x] 13.2 新增 `entry/src/main/ets/components/FolderPanel.ets`：主页内嵌可折叠树面板——根/全部行、缩进树、子树计数、展开/收起、行尾「…」锚定面板（新建子文件夹/改名/移动/删除/在流中查看）、根级新建、删除确认汇总、`FolderPicker` 移动、点行设/清 `folderFilter`、拖拽目标高亮与根投放区；展开集合与面板滚动位置存 `AppState`，刷新时裁掉失效 id；复用 `FlowRepository.folderTree/createFolder/renameFolder/moveFolder/deleteFolderCascade`；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 13.3 `entry/src/main/ets/components/StreamHome.ets` 集成树面板：固定在流列表上方、可折叠（宽屏默认展开、手机默认折叠、展开最高约 40% + 内部滚动），折叠时列表占满；拖拽开始自动展开；`folderFilter` 变化同步过滤态；移除旧「文件夹」页入口；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 13.4 长按拖拽改造：`components/BookmarkRow.ets` 与 FolderPanel 行加 `.draggable(true)` / `onDragStart` / `onDrop`，移除 BookmarkRow 的 `LongPressGesture` 长按浮层入口；未选中行拖单条、已选行拖整组（书签 + 文件夹混合）；拖拽会话用共享类型或模块单例；书签行尾新增「…」按钮打开既有 `QuickActionPanel`，桌面右键同入口；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 13.5 拖拽落点与批量提交：书签→文件夹写 `folderId`、文件夹→文件夹写 `parentId`、→根区移出；自身/子孙目标跳过提示、原父级无操作、取消无变更；一次拖拽走 `FlowRepository.batchMove` 并只 notify 一次；不写 `position`/`createdAt`；面板边缘自动滚动；拖动期间挂起 `refreshTick` 重载；抽落点校验纯函数并在 `entry/src/ohosTest` 补用例（自身、子孙、同父、混合、全跳过），设备端跑通；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 13.6 主页多选扩展：`FolderPanel` 文件夹行与 `StreamHome` 书签行共用选择集合（`bookmarkIds`/`folderIds` 分开、支持混合、勾选独立点击区、行点击保留原行为）；批量栏补「移动到…」（`FolderPicker`）与「移出一级」；删除一次确认汇总复用 `batchDeleteImpact`/`batchDelete`；刷新时只裁剪书签选择、按存活树裁剪文件夹选择；复用 `batchMove`/`batchMoveOut`；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 13.7 无拖拽可达性：书签与文件夹「…」菜单、批量栏均提供移动入口，键盘焦点可达、读屏文案完整；走查键盘 Tab/Enter 完成一次移动；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 13.8 设备端回归与手动验收：按 AGENTS.md 构建并安装 ohosTest 全量套件通过；手动走查宽屏与手机树面板（展开/折叠/过滤/新建/改名/删除）、单条与多选拖拽（书签、文件夹、根区、非法落点、取消、折叠自动展开）、详情往返保留展开与滚动、折叠态列表占满；`codelinter -c code-linter.json5` 0 error 收尾（面板形态由第 14 节取代，形态相关走查以 14.6 为准；本次设备端 175/175 通过，手动走查已通过 2026-10-28）

## 14. 文件夹树迁到最左栏与窄屏抽屉（13.2/13.3 形态修订）

本节取代 13.2（主页内嵌树面板）、13.3（流列表上方堆叠、40% 高度）与 13.8 中关于面板形态的走查口径。数据层、同步、导入导出、`FolderDragSession` / `FolderDropRules`、`batch*` 方法与 `FolderPicker` 不变。

- [x] 14.1 `entry/src/main/ets/components/NavigationRail.ets` 改侧栏容器：栏宽 240→280vp，导航项下方承载 `FolderPanel` 停靠形态（占剩余高度、内部滚动，外层 `clip(false)` 不裁剪弹出层），页脚保持底部；`pages/Index.ets` 传入树状态与拖拽所需事件；`check_ets_files` + `hvigorw assembleHap` + `codelinter -c code-linter.json5` 收尾
- [x] 14.2 `entry/src/main/ets/components/FolderPanel.ets` 双形态：新增 `dock`（无收起标题、填满可用高度、去掉 40% 上限）与 `drawer`（全高）参数，根/全部行与根投放区保留；`StreamHome.ets` 删除内联 `FolderPanel` 实例与折叠标题；树滚动位置由两形态共享；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 14.3 窄屏抽屉与左上角按钮：`pages/Index.ets` 作为抽屉宿主（宽 `min(320vp, 84%)`、全高、遮罩，点外部/返回键关闭），`StreamHome.ets` 头部左上角新增文件夹按钮（仅 <1000vp 显示，需 `Index` 传入断点或等价信号）；点选文件夹后应用 `folderFilter`、必要时 `goPane(Pane.DETAIL)` 并关闭抽屉；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 14.4 跨列多选：`entry/src/main/ets/common/AppState.ets` 提升 `selectionMode` / `selectedBookmarkIds` / `selectedFolderIds`（`@Trace`），`StreamHome` 批量栏与 `FolderPanel` 行勾选读写同一集合；刷新裁剪语义（书签按存活、文件夹按存活树）不变；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 14.5 跨列拖拽：`BookmarkRow` 拖拽开始从 `AppState` 选择集合填充 `FolderDragSession`；`FolderPanel` 投放直接读会话并调用 `FlowRepository.batchMove`（一次 notify），删除 `StreamHome` 的 `onDropOnFolder` 中转链路；窄屏拖拽自动打开抽屉、遮罩放行指针事件、树上下边缘自动滚动；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 14.6 设备端回归与手动验收：按 AGENTS.md 构建并安装 ohosTest 全量套件通过；走查 ≥1000vp 停靠（导航项 + 树、流列宽不变、深树滚动）、700–999vp 与手机左上角按钮抽屉（打开/遮罩关闭/返回键/选文件夹后关闭）、单条与多选拖拽（书签、文件夹、根区、非法落点、取消、自动开抽屉）、详情往返保留展开与滚动；`codelinter -c code-linter.json5` 0 error 收尾（本次设备端 175/175 通过；手动走查已通过 2026-10-28）
- [x] 14.7 走查反馈：移除文件夹树的展开箭头与叶子圆点，行主体点击有子项时展开/收起、无子项时筛选，父级筛选走「…」→在流中查看；树容器左右留 12vp 空白；`StreamHome` 头部只保留右侧「批量」（删除遗留的左侧入口）；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 14.8 走查反馈：主导航项收进左侧栏——`NAV_ITEMS` 从 `NavigationRail.ets` 导出，抽屉顶部渲染同组导航项（含流笺，文字与 ☰ 同 20vp 缩进），点击关闭抽屉并 `openPane`；`StreamHome` 头部移除 标签/同步/设置（宽屏侧栏已含、去重一致）；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 14.9 走查反馈：混合文件夹直属书签不可达——`FolderPanel` 行主体点击统一「筛选 + 展开」：任意文件夹行点击设 `folderFilter`（子树过滤；重复点击同一行不切换清除，取消叶子行 toggle，清除走根/全部行或流头过滤芯片），父级行未展开则展开、已展开则收起且过滤保留；窄屏点叶子行关闭抽屉、点父级行保持抽屉打开；`rowLabel` 读屏文案随新语义更新（展开并筛选/收起/筛选）；「…」→在流中查看保留为等价入口；走查混合文件夹（父级含直属书签 + 子文件夹）点击后直属书签在流中可见、再次点击收起后过滤保留、窄屏父级行下钻不关抽屉；`check_ets_files` + `hvigorw assembleHap` + `codelinter -c code-linter.json5` 0 error 收尾（改动集中在 FolderPanel 的 activateRow/applyFilter/rowLabel/viewInStream，`applyFilter` 增 closeDrawer 参数；「在流中查看」按显式查看意图窄屏关抽屉；走查项并入 6.2/14.6 手动验收；子树过滤口径已在 15 节修订为直属书签）

## 15. 文件夹过滤裁剪为直属书签（用户修订）

本节把 2.3（`folder_id IN (?)` 子树过滤查询）、5.1（`folderFilter`）与 14.9（行主体点击「筛选 + 展开」）中的过滤口径从「含全部子孙」修订为「直属书签」，设计见 D8 修订。级联删除（D5）、拖拽落点校验（D14）、批量删除汇总与树行计数（仍含全部子孙）的子树语义不变。

- [x] 15.1 直属过滤落地：`FolderPanel` 的 `applyFilter` / `viewInStream` 与 `StreamHome` 过滤链路改为 `folder_id = ?` 等值；`BookmarkQuery` / `BookmarkDao` 从子树 `IN` 查询改为等值查询（`IN` 支持若无其他调用方一并移除；级联删除与拖拽校验仍走 FolderDao 子树 id 集）；流头过滤芯片、「在流中查看」等价入口与 `rowLabel` 文案随语义复核；check_ets_files + hvigorw assembleHap 收尾（`BookmarkQuery.folderIds[]` 收敛为 `folderId` 单值，DAO 分块 IN 删除；`rowLabel`/过滤芯片文案未提及范围、保持原文；`applyFilter`/`viewInStream` 本就只写 `folderFilter`，无需改动；`subtreeFolderIds` 保留给级联删除汇总与删除确认计数）
- [x] 15.2 ohosTest 更新并设备端回归：过滤断言改直属（父级行点击只显示直属书签、子孙不出现在流中、叶子行与清除/叠加语义不变），树行计数（含子孙）、树构建、级联删除、拖拽落点子树用例不动；check_ets_files + hvigorw assembleHap 收尾（`queriesByFolderSubtree` 重写为 `queriesByDirectFolderMembership`（直属 1 条 + 子文件夹行可达 + 关键词叠加命中/未命中），`setBookmarkFolderMovesBetweenTreePositions` 改等值查询；设备端 175/175 通过）
- [x] 15.3 走查并入 6.2/14.6：混合文件夹点击后直属书签可见、子孙经子文件夹行下钻到达、再次点击收起后过滤保留（行计数仍为含子孙口径，接受与流条数不一致）；`codelinter -c code-linter.json5` 0 error 收尾（codelinter 0 error / 1 条既有 startIcon 建议；走查项并入 6.2/14.6 手动验收）

## Workflow follow-up

- 按 AGENTS.md 更新易变事实：项目快照（6 表 + 7 索引 → 7 表 + 9 索引）、架构图（文件夹同步实体）、数据库无迁移模式说明（部分唯一索引）；把「文件夹树在主页最左栏（≥1000vp 停靠、窄屏左上角按钮抽屉）、长按拖拽只改归属不排序、行操作走「…」、过滤只显示直属书签」写入 UI 约定，并移除 FoldersPage / Pane.FOLDERS 的描述。
- 评审通过后归档：`/openspec-archive-change`，归档后把删除语义与同步代价表结论吸收进 AGENTS.md。
