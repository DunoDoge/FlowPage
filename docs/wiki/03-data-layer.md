# 数据层

本篇说明数据模型、RDB 结构、DAO、`FlowRepository` 门面，以及 URL 归一化、导入导出与本地文件。

## 1. 数据模型

[Bookmark.ets](../../entry/src/main/ets/model/Bookmark.ets) 是 `@ObservedV2` 类，全部字段带 `@Trace`，
是 UI 直接观察的数据对象。主要字段分四组：

| 组 | 字段 |
|---|---|
| 标识与内容 | `id`、`url`、`urlKey`、`title`、`description`、`siteName`、`faviconUrl`、`coverUrl` |
| 正文与摘录 | `note`、`excerpt`、`snapshotPath`、`snapshotStatus`、`snapshotAt`、`searchText` |
| 组织与状态 | `tags`、`folderPath`、`source`、`readState`、`starred`、`archived`、`deleted`、`createdAt`、`updatedAt`、`readAt` |
| 同步与链接 | `rev`、`remoteEtag`、`dirty`、`deviceId`、`linkStatus`、`linkCheckedAt` |

`Bookmark.create()` 生成 UUID、设置 `urlKey=normalizeUrl()`、初始化时间戳与 `PENDING` 快照状态，并调用
`rebuildSearch()`。`searchText` 是标题、描述、站点、URL、备注、摘录、标签拼接后的小写串，搜索直接对它做
子串匹配，因此**凡是修改这些字段的 DAO 方法都必须重建 `search_text`**（现有 `setTitle/setNote/setExcerpt/
setTags/fillTags` 已处理；标签改名/合并/删除也在同一事务内按受影响书签重建）。

枚举在 [Constants.ets](../../entry/src/main/ets/common/Constants.ets)：`StreamFilter`、`ReadState`、
`SnapshotStatus`、`BookmarkSource`、`Pane`；`Limits` 定义抓取/快照/标题/描述上限。

## 2. 表结构

[Database.ets](../../entry/src/main/ets/core/db/Database.ets) 创建 `flowpage.db`（security level S1），六张表：

| 表 | 关键列 | 说明 |
|---|---|---|
| `bookmark` | `id` PK、`url_key` 唯一、`deleted`、`archived`、`read_state`、`starred`、`rev`、`remote_etag`、`dirty` | 主表；`dirty` 默认 1 |
| `tag` | `id` PK、`name`、`name_key` 唯一 | `name_key` 为小写名，保证大小写不重复 |
| `bookmark_tag` | `(bookmark_id, tag_id)` PK | 多对多关联 |
| `conflict` | `id` PK、`bookmark_id`、`local_json`、`remote_json`、`reason`、`created_at` | 下载覆盖本地 dirty 版本时留档 |
| `sync_state` | `key` PK、`value` | 预留；当前同步游标用 preferences（`last_sync`），表未使用 |
| `tombstone` | `id` PK、`remote_id`、`deleted_at`、`attempts`、`last_error` | 彻底删除后待传播的墓碑 |

六个索引：`idx_bookmark_url_key`（唯一）、按 `deleted/archived/created_at`、`deleted/starred/created_at`、
`deleted/read_state/created_at` 的三个列表索引、`idx_tag_name_key`（唯一）、`idx_bookmark_tag_tag`。

## 3. DAO 行为

[BookmarkDao.ets](../../entry/src/main/ets/core/db/BookmarkDao.ets) 直接执行 SQL，负责：

- `insert/update`：写入 bookmark 全字段，并同步 `bookmark_tag`；`ensureTag()` 按小写名复用或新建标签。
- `listAll(includeDeleted)`：按 `created_at DESC`；默认过滤 `deleted=0`；一次性填充标签并重建搜索文本。
- `findById/findByUrlKey`：读取单条并加载标签。
- 状态更新：`setStarred/setArchived/setReadState/setNote/setExcerpt/setTitle/softDelete/restore` 都会
  `updated_at=now`、`rev=rev+1`、`dirty=1`；改文本的三者还会重建 `search_text`。
- `setRemoteEtagIfUnchanged(id, etag, expectedRev, expectedUpdatedAt)`：条件更新（`rev` 和 `updated_at`
  都匹配）才写 `remote_etag` 并清 `dirty`，返回是否命中。这是上传竞态保护的关键。
- `clearRemoteEtags()`：切换 WebDAV 服务器时清空所有 ETag，**不清 dirty**。
- 标签：`listTags()` 只统计未删除书签（0 计数的标签不返回）；`renameTag()` 撞名时自动合并到目标；
  `deleteTag()` 只删关联与标签本身，不删书签；`mergeTags()` 把源标签关联复制到目标后删除源标签。
  三者都会在同一事务内只处理「确实带有源标签」的书签：重建 `search_text` 并批量
  `touch`（`updated_at=now`、`rev+1`、`dirty=1`），只含目标标签的书签不会被误标 dirty。
- 墓碑：`addTombstone()` 使用 `INSERT OR REPLACE`；`purge()` 先写墓碑再 `purgeLocal()`；
  `markTombstoneFailed()` 累加 `attempts` 并记录错误；`purgeExpired(days)` 找出软删除超期项逐个 `purge()`。

**直接调 DAO 不会刷新 UI，也不会刷新服务卡片。** UI 侧只应通过 `FlowRepository`。

## 4. 初始化与迁移

`Database.init()` 是进程内单例：第一次调用 `getRdbStore`，依次 `CREATE TABLE IF NOT EXISTS` 六表，
再对三个后加列执行 `ALTER TABLE ... ADD COLUMN`，异常直接忽略（表示列已存在），最后建索引。
因此新增列时必须同时：

1. 改 `Database.SQL_BOOKMARK`（新库直接带上该列）；
2. 在 `init()` 末尾补一条 `try { ALTER TABLE bookmark ADD COLUMN ... } catch {}`（旧库升级）。

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
| `setStarred/setArchived/setRead/setTitle/setNote/setExcerpt/setTags` | 调 DAO 后 `notify()` |
| `delete/restore/purge/purgeExpired` | 软删除、恢复、彻底删除（含快照文件清理） |
| `importHtml/previewHtml/exportJson/exportHtml` | 导入预览、分批事务导入（可取消、失败清单）与两种导出 |
| `saveEdits` | 标题/备注/摘录/标签单事务写入，只 `notify()` 一次 |
| `queryPage` | SQL 过滤 + 排序 + 分页（搜索/标签/回收站） |
| `listConflicts/resolveConflict/countConflicts` | 冲突记录查询、恢复本地或采用远端 |
| `purgeExpired/purge/purgeFromRemote/clearAll` | 统一由仓库删除快照文件 |
| `listAll/get/summary/listTags/...` | 只读查询 |
| `upsertFromRemote(record, etag)` | 同步下载落库；见 [04](./04-sync-and-services.md#5-合并与冲突) |
| `setRemoteEtagIfUnchanged/clearRemoteEtags` | 供 `SyncEngine` 使用 |
| `afterSync()` | 同步结束后统一 `notify()` |

`notify()` 做两件事：递增 `AppState.refreshTick`；调度卡片快照刷新。卡片刷新用
`cardSnapshotRunning` / `cardSnapshotPending` 合并并发请求，避免每次写入都重入。

### 导入 / 导出

- [BookmarkHtmlParser.ets](../../entry/src/main/ets/core/parser/BookmarkHtmlParser.ets) 逐行解析 Netscape 书签：
  `<H3>` 记文件夹、`<DL>` 压栈、`</DL>` 出栈、`<A>` 取 `href` 与标题。**每个 `<A>` 必须与其内容在同一行**
  （浏览器导出的格式满足）；同一 HTML 内先按归一化 URL 去重。
- 导入时已有 `url_key` 跳过；`keepFolders=true`（设置页固定传 true）时把 `folderPath` 写入标签；
  同时保留 `folderPath` 字段。失败 URL 收集到 `ImportResult.failedUrls`。
- 导出 JSON：`{ schema: 1, exportedAt, items }`，`items` 是完整 Bookmark 对象。
- 导出 HTML：Netscape 格式，按 `folderPath` 分组，只导出 URL、标题、`ADD_DATE`。

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
| `filesDir/snapshots/<id>.txt` | 正文纯文本快照，上限 200 KiB（按字符截断）；不参与同步 |
| RDB `flowpage.db` | 书签、标签、冲突、墓碑、同步状态表 |
| preferences `flowpage_settings` | `theme_mode`、`reading_size` |
| preferences `flowpage_sync` | `webdav_config`（含加密密码与服务器指纹）、`last_sync`、旧版兼容键 |
| preferences `flowpage_card` | 今日/最近卡片快照 |
| preferences `flowpage_card_forms` | 已发布卡片 ID 列表 |

`SnapshotStore` 只做 `save/read/remove`，路径不存在时返回空串，不抛异常。

### 生命周期约定

- `clearAll()` 定位为「只清本机」：清 bookmark/tag/bookmark_tag/conflict，并删除 `snapshots/` 下全部
  `.txt`；云端数据保留，下一次同步会重新下载。tombstone 有意保留，避免清空前已排队的彻底删除
  失去云端传播。设置页文案已注明。
- `purge()`、`purgeExpired()`、`purgeFromRemote()`、`clearAll()` 都由 `FlowRepository` 删除快照，
  DAO 不承担文件副作用；`purgeFromRemote()` 即使数据库行已丢失，也会按 `<id>.txt` 清掉孤立文件。
- `FlowRepository.init()` 的过期清理改走仓库层 `purgeExpired()`，与手动清理共用同一套文件删除逻辑。
- `sync_state` 表已创建但当前没有读写方；不要把它当作同步游标。
