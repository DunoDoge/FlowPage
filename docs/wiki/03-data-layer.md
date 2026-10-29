# 数据层

本篇说明数据模型、RDB 结构、DAO、`FlowRepository` 门面，以及 URL 归一化、导入导出与本地文件。

## 1. 数据模型

[Bookmark.ets](../../entry/src/main/ets/model/Bookmark.ets) 是 `@ObservedV2` 类，全部字段带 `@Trace`，
是 UI 直接观察的数据对象。主要字段分四组：

| 组 | 字段 |
|---|---|
| 标识与内容 | `id`、`url`、`urlKey`、`title`、`description`、`siteName`、`faviconUrl`、`coverUrl` |
| 正文与摘录 | `note`、`excerpt`、`snapshotPath`、`snapshotStatus`、`snapshotAt`、`searchText` |
| 组织与状态 | `tags`、`folderId`（直属文件夹，空串=根）、`source`、`readState`、`starred`、`archived`、`deleted`、`createdAt`、`updatedAt`、`readAt` |
| 同步与链接 | `rev`、`remoteEtag`、`dirty`、`deviceId`、`linkStatus`、`linkCheckedAt` |

`Bookmark.create()` 生成 UUID、设置 `urlKey=normalizeUrl()`、初始化时间戳与 `PENDING` 快照状态，并调用
`rebuildSearch()`。`searchText` 是标题、描述、站点、URL、备注、摘录、标签拼接后的小写串，搜索直接对它做
子串匹配，因此**凡是修改这些字段的 DAO 方法都必须重建 `search_text`**（现有 `setTitle/setNote/setExcerpt/
setTags/fillTags` 已处理；标签改名/合并/删除也在同一事务内按受影响书签重建）。

枚举在 [Constants.ets](../../entry/src/main/ets/common/Constants.ets)：`StreamFilter`、`ReadState`、
`SnapshotStatus`、`BookmarkSource`、`Pane`；`Limits` 定义抓取/快照/标题/描述上限。

### 文件夹模型

[Folder.ets](../../entry/src/main/ets/model/Folder.ets) 是 `@ObservedV2` 的 `Folder`（`id`、`parentId`、
`name`、`position`、`kind`、`createdAt/updatedAt`、`rev/dirty/remoteEtag/deleted`）与
`FolderNode`（`children`、`directCount/totalCount`、`path`、`subtreeIds()`）。
`kind` 是导入时捕获的浏览器语义标记（`''` / `'toolbar'` / `'unfiled'`），HTML 导出时回写为 Netscape
属性，避免浏览器把我们的根再包一层书签栏。`buildFolderTree()`（FolderDao.ets）由扁平行建树：过滤 `deleted`、悬空子树隐藏、
检测到环时丢弃环成员中 `updatedAt` 最新者的父边。

### 正文文档与阅读栈

[Article.ets](../../entry/src/main/ets/model/Article.ets) 定义 `ArticleDocument`、`ArticleBlock`、`ArticleLink`：

- `ArticleBlock.links: ArticleLink[]` 保存块内链接区间 `{start, end, url}`，偏移以 `block.text` 的字符下标计；
  `url` 是已解析的绝对 http(s) 地址。
- 快照 `FLOWPAGE-ARTICLE-2` 的第三字段保存 `start,end,encodeURIComponent(url)`，多条用 `;` 连接；
  解码校验区间与长度，非法条目丢弃。`FLOWPAGE-ARTICLE-1` 仍可读，链接为空。
- `ArticleDocument.truncate()` 截断块文本时同步裁剪链接，避免偏移越界。

### 抽取线程模型与上限

- `ArticleExtractor.extract()` 是纯函数（正则全部模块级复用），既可在 UI 线程同步调用，也可在 taskpool 里跑。
- 阅读页链路走 worker：[ArticleExtractTask.ets](../../entry/src/main/ets/core/parser/ArticleExtractTask.ets) 是
  `@Concurrent` 入口，只接收 `html / title / baseUrl` 三个 string，返回 `ArticleCodec.encode()` 的
  `FLOWPAGE-ARTICLE-2` 字符串；[ArticleExtractService.ets](../../entry/src/main/ets/core/service/ArticleExtractService.ets)
  在主线程 `ArticleCodec.decode()` 成 `ArticleDocument`。`ArticleDocument`/`ArticleBlock` 不是 Sendable，
  **不要**把模型对象传给 taskpool。
- 超时 4 s；taskpool 初始化失败、超时或返回异常时回退主线程同步抽取（保证功能不丢）。
- 使用方：`ReaderPageLoader.load()`（`MetadataService.fetch(url, true, true)`）、`ReadingShell.extractFromWeb()`、
  `FlowRepository.applyMetadata()`（第三轮起显式 `offThread=true`——同步抽取热点已全部迁移 worker）。
- 单次耗时（101,620 字符 / 648 块，2026-10-25 实测口径）：抽取 75–80 ms；含 taskpool 往返、`truncate`、
  `plainText`、codec 编解码约 150–210 ms。471,912 字符 / 1,150 块约 400–560 ms，仍应留在 worker。
  不要在 UI 线程循环调用抽取（例如逐块/逐页重抽）。
- **阅读页搜索同模式**：[ReaderSearchCore.ets](../../entry/src/main/ets/core/parser/ReaderSearchCore.ets) 纯函数
  （块内 containment、跨块/含分隔符不命中）+ [ReaderSearchTask.ets](../../entry/src/main/ets/core/parser/ReaderSearchTask.ets)
  （`@Concurrent`，只收 `string`/`number[]`，返回逗号分隔命中下标串）+
  [ReaderSearchService.ets](../../entry/src/main/ets/core/service/ReaderSearchService.ets)（`buildIndex` + taskpool +
  2 s 超时 + 同步回退）。索引构建 1,999 块约 6 ms，一次性留在 UI 线程；检索 1,999 块全量同步循环约 156 ms
  （均为 2026-10-25 实测口径），走 worker 后主线程零阻塞。纯函数等价性由 `ReaderSearch.test.ets`（11 例）覆盖。
- [ReadingEntry.ets](../../entry/src/main/ets/model/ReadingEntry.ets) 的 `ReadingEntry` / `ReadingSeed` 是
  `ReadingShell` 的运行时模型，**不落盘**：临时页的块位置只存内存，不写 `flowpage_reader`。
  `ReadingEntry.compact` 是非当前层的 `ArticleCodec.encode()` 串（阅读栈内存形态机的紧凑形态，见 wiki/02），
  同样不落盘、不同步。

## 2. 表结构

[Database.ets](../../entry/src/main/ets/core/db/Database.ets) 创建 `flowpage.db`（security level S1），七张表：

| 表 | 关键列 | 说明 |
|---|---|---|
| `bookmark` | `id` PK、`url_key` 唯一、`folder_id`、`deleted`、`archived`、`read_state`、`starred`、`rev`、`remote_etag`、`dirty` | 主表；`dirty` 默认 1 |
| `folder` | `id` PK、`parent_id`、`name`、`position`、`kind`、`rev`、`remote_etag`、`dirty`、`deleted` | 文件夹树；软删除，同级重名受限 |
| `tag` | `id` PK、`name`、`name_key` 唯一 | `name_key` 为小写名，保证大小写不重复 |
| `bookmark_tag` | `(bookmark_id, tag_id)` PK | 多对多关联 |
| `conflict` | `id` PK、`bookmark_id`、`local_json`、`remote_json`、`reason`、`created_at` | 下载覆盖本地 dirty 版本时留档（仅书签） |
| `sync_state` | `key` PK、`value` | 预留；当前同步游标用 preferences（`last_sync`），表未使用 |
| `tombstone` | `id` PK、`remote_id`、`deleted_at`、`attempts`、`last_error` | 彻底删除后待传播的墓碑；书签与文件夹共用（uuid 不冲突） |

九个常规索引：`idx_bookmark_url_key`（唯一）、按 `deleted/archived/created_at`、`deleted/starred/created_at`、
`deleted/read_state/created_at` 的三个列表索引、`idx_bookmark_domain`、`idx_bookmark_folder`、
`idx_tag_name_key`（唯一）、`idx_bookmark_tag_tag`、`idx_folder_parent`。另有部分唯一索引
`idx_folder_parent_name`（`folder(parent_id, name) WHERE deleted = 0`）：旧 SQLite 不支持部分索引时静默跳过，
FolderDao 每条写路径都有应用层同级重名兜底检查，两条防线不可只留其一。

## 3. DAO 行为

[BookmarkDao.ets](../../entry/src/main/ets/core/db/BookmarkDao.ets) 直接执行 SQL，负责：

- `insert/update`：写入 bookmark 全字段，并同步 `bookmark_tag`；`ensureTag()` 按小写名复用或新建标签。
- `listAll(includeDeleted)`：按 `created_at DESC`；默认过滤 `deleted=0`；一次性填充标签并重建搜索文本。
- `findById/findByUrlKey`：读取单条并加载标签。
- 状态更新：`setStarred/setArchived/setReadState/setNote/setExcerpt/setTitle/softDelete/restore` 都会
  `updated_at=now`、`rev=rev+1`、`dirty=1`；改文本的三者还会重建 `search_text`。
  批量版 `setStarredMany/setArchivedMany/setReadStateMany/softDeleteMany/restoreMany` 语义相同；
  `setFolder(id, folderId)` 只改归属，不动 `position`/`createdAt`。
- `setRemoteEtagIfUnchanged(id, etag, expectedRev, expectedUpdatedAt)`：条件更新（`rev` 和 `updated_at`
  都匹配）才写 `remote_etag` 并清 `dirty`，返回是否命中。这是上传竞态保护的关键。
- `clearRemoteEtags()`：切换 WebDAV 服务器时清空所有 ETag，**不清 dirty**。
- 标签：`listTags()` 只统计未删除书签（0 计数的标签不返回）；`renameTag()` 撞名时自动合并到目标；
  `deleteTag()` 只删关联与标签本身，不删书签；`mergeTags()` 把源标签关联复制到目标后删除源标签。
  三者都会在同一事务内只处理「确实带有源标签」的书签：重建 `search_text` 并批量
  `touch`（`updated_at=now`、`rev+1`、`dirty=1`），只含目标标签的书签不会被误标 dirty。
- 墓碑：`addTombstone()` 使用 `INSERT OR REPLACE`；`purge()` 先写墓碑再 `purgeLocal()`；
  `markTombstoneFailed()` 累加 `attempts` 并记录错误；`purgeExpired(days)` 找出软删除超期项逐个 `purge()`。

[FolderDao.ets](../../entry/src/main/ets/core/db/FolderDao.ets) 负责文件夹树的全部写路径：

- `create/findOrCreate(parentId, name, cache?)`：`position` 取父下最大值 +1；`findOrCreate` 供导入批量
  解析路径，共享缓存让一次导入只按「不同路径」发生 O(1) 次往返。
- `rename/move`：目标父下出现同名兄弟即拒绝；`move` 还拒绝移入自身或自己的后代
  （可选 `keepPosition` 让批量移动不改变 `position`）。
- `cascadeSoftDelete(id)`：连同子孙文件夹与其中书签一起软删除；`restoreChain(id)` 复活书签时顺带
  复活其文件夹祖先链，复活撞名时 `dedupedName/freeReviveName` 给占名者改名让位。
- `setFolderEtagIfUnchanged`：与 BookmarkDao 同名的上传竞态条件更新；`listExpiredFolderIds(days)`
  供过期清理；`clearRemoteEtags()` 与书签版一起在换服务器时调用。

**直接调 DAO 不会刷新 UI，也不会刷新服务卡片。** UI 侧只应通过 `FlowRepository`。

## 4. 初始化与迁移

`Database.init()` 是进程内单例：第一次调用 `getRdbStore`，依次 `CREATE TABLE IF NOT EXISTS` 七表，
再对五个后加列（bookmark 的 `dirty` / `link_status` / `link_checked_at` / `domain` / `folder_id`，
folder 的 `kind`）执行 `ALTER TABLE ... ADD COLUMN`，异常直接忽略（表示列已存在）；
随后尝试 `ALTER TABLE bookmark DROP COLUMN folder_path` 清掉被 `folder_id` 取代的旧开发库列
（新库/旧 SQLite 上抛错均无害），最后建索引。
因此新增列时必须同时：

1. 改 `Database.SQL_BOOKMARK`（或对应表，新库直接带上该列）；
2. 在 `applySchema()` 的 `addColumn()` / `addFolderColumn()` 列表补一条定义（旧库升级）。

没有 `DB_VERSION`、没有迁移事务、没有回滚。插入/更新、编辑正文、批量导入、清空本机、标签改名/合并/删除
等写操作已在显式事务内执行（`beginTransaction/commit/rollBack`）；单个状态字段的 `UPDATE` 仍是单条 SQL。

`FlowRepository.init()` 在建库后立即调用 `dao.purgeExpired(30)` 清理超过 30 天的软删除记录。

## 5. `FlowRepository` 门面

[FlowRepository.ets](../../entry/src/main/ets/repository/FlowRepository.ets) 是单例（`FlowRepository.get()`），
把 DAO、抓取、快照、同步、卡片串起来。UI 只依赖它。

| 方法组 | 行为 |
|---|---|
| `saveUrl(rawUrl, title, tags, note, source)` | URL 归一化、按 `url_key` 去重、恢复回收站同 URL、插入、`notify()` |
| `applyMetadata(id)` | 抓取元数据；标题只在为空或等于域名兜底时覆盖；写正文快照；更新 `snapshotStatus`；`notify()` |
| `setStarred/setArchived/setRead/setTitle/setNote/setExcerpt/setTags`（含 `*Many` 批量版） | 调 DAO 后 `notify()` |
| `delete/restore/purge/purgeExpired`（含 `*Many`） | 软删除、恢复（`restoreWithFolderChains` 顺带复活文件夹祖先链）、彻底删除（含快照文件清理） |
| 文件夹组 `folderTree/createFolder/renameFolder/moveFolder/deleteFolderCascade/setBookmarkFolder/countFolderBookmarks` | 树查询与单点写；`deleteFolderCascade` 走 `FolderDao.cascadeSoftDelete` |
| 批量组 `batchMove/batchMoveOut/batchDelete/batchDeleteImpact` | 批量面板与拖拽投放共用；DAO 循环后**单次** `notify()` |
| `importHtml/previewHtml/exportJson/exportHtml` | 导入预览、分批事务导入（可取消、失败清单）与两种导出 |
| `saveEdits` | 标题/备注/摘录/标签单事务写入，只 `notify()` 一次 |
| `queryPage` | SQL 过滤 + 排序 + 分页（搜索/标签/文件夹/回收站；`folderId` 为直属等值过滤） |
| `listConflicts/resolveConflict/countConflicts` | 冲突记录查询、恢复本地或采用远端 |
| `purgeExpired/purge/purgeFromRemote/clearAll` | 统一由仓库删除快照文件；`purgeExpired` 在书签之后处理过期文件夹（先墓碑后 `purgeLocal`） |
| `listAll/get/summary/listTags/listAllFolders/...` | 只读查询 |
| `upsertFromRemote(record, etag)` | 同步下载落库；见 [04](./04-sync-and-services.md#5-合并与冲突) |
| `upsertFolderFromRemote/setFolderEtagIfUnchanged` | 文件夹下载落库（同名兄弟去名合并）与上传竞态回填 |
| `setRemoteEtagIfUnchanged/clearRemoteEtags` | 供 `SyncEngine` 使用；ETag 清理同时覆盖书签与文件夹 |
| `afterSync()` | 同步结束后统一 `notify()` |

`notify()` 做两件事：递增 `AppState.refreshTick`；调度卡片快照刷新。卡片刷新用
`cardSnapshotRunning` / `cardSnapshotPending` 合并并发请求，避免每次写入都重入。

### 导入 / 导出

- [BookmarkHtmlParser.ets](../../entry/src/main/ets/core/parser/BookmarkHtmlParser.ets) 逐行解析 Netscape 书签：
  `<H3>` 记文件夹、`<DL>` 压栈、`</DL>` 出栈、`<A>` 取 `href` 与标题。**每个 `<A>` 必须与其内容在同一行**
  （浏览器导出的格式满足）；同一 HTML 内先按归一化 URL 去重；顶层 `<H3>` 的
  `PERSONAL_TOOLBAR_FOLDER` / `UNFILED_BOOKMARKS_FOLDER` 属性收进 `topMarks`。
- 导入按层级把路径解析成**真实文件夹链**：`resolveFolderChain()` 逐级 `findOrCreate`
  （共享缓存，一次导入按不同路径 O(1) 次往返），书签写直属 `folderId`；顶层标记每文件夹只写一次
  `kind`（幂等，重复导入保持同步静默）。已有 `url_key` 跳过；失败 URL 收集到 `ImportResult.failedUrls`；
  `ADD_DATE` 回填 `createdAt`。批量 250 条一档，整档失败降级为逐条插入。
- 导出 JSON：`{ schema: 2, exportedAt, items, folders }`，`items` 是完整 Bookmark 白名单，
  `folders` 携带 `id/parentId/name/position/kind/createdAt`。
- 导出 HTML：按文件夹树输出 Netscape 格式（悬空 `folderId` 的书签落根级，保证不丢），
  `kind` 标记回写为浏览器语义属性；书签按 `createdAt` 升序。

## 6. URL 归一化与去重

[UrlUtil.ets](../../entry/src/main/ets/common/UrlUtil.ets) 是唯一 URL 入口：

- 无 scheme 时补 `https://`；只接受 `http/https`，其他协议归一化为空串。
- host 小写；path 缺省为 `/`；丢弃 fragment。
- 删除跟踪参数：`utm_*` 以及 `spm/from/source/share_source/share_from/fbclid/gclid/yclid/mc_cid/mc_eid/ref/referrer/s_cid`；
  剩余 query 按 `key=value` 排序。
- `url_key` 唯一索引负责最终去重；`saveUrl`、导入、同步都以 `urlKey` 比较，不要直接比较原始 URL。
- `domainOf()` 返回去掉 `www.` 的 host；`extractFirstUrl()` 支持带 scheme 与裸域名，并裁掉尾部中英文标点。

## 7. 本地文件与偏好

| 位置 | 内容 |
|---|---|
| `filesDir/snapshots/<id>.txt` | 正文结构化快照（`FLOWPAGE-ARTICLE-2`，含块类型/文本/链接区间），上限 200 KiB（按字符截断）；不参与同步 |
| RDB `flowpage.db` | 书签、文件夹、标签、冲突、墓碑、同步状态表 |
| preferences `flowpage_settings` | `theme_mode`、`reading_size` |
| preferences `flowpage_sync` | `webdav_config`（含加密密码与服务器指纹）、`last_sync`、旧版兼容键 |
| preferences `flowpage_card` | 今日/最近卡片快照 |
| preferences `flowpage_card_forms` | 已发布卡片 ID 列表 |

`SnapshotStore` 只做 `save/read/remove`，路径不存在时返回空串，不抛异常。

### 生命周期约定

- `clearAll()` 定位为「只清本机」：清 bookmark/tag/folder/bookmark_tag/conflict，并删除 `snapshots/` 下全部
  `.txt`；云端数据保留，下一次同步会重新下载。tombstone 有意保留，避免清空前已排队的彻底删除
  失去云端传播。设置页文案已注明。
- `purge()`、`purgeExpired()`、`purgeFromRemote()`、`clearAll()` 都由 `FlowRepository` 删除快照，
  DAO 不承担文件副作用；`purgeFromRemote()` 即使数据库行已丢失，也会按 `<id>.txt` 清掉孤立文件。
- `FlowRepository.init()` 的过期清理改走仓库层 `purgeExpired()`，与手动清理共用同一套文件删除逻辑。
- `sync_state` 表已创建但当前没有读写方；不要把它当作同步游标。
