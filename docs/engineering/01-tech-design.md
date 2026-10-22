# 流笺 FlowPage · 技术方案

> 时效说明：本文是实现后的技术基线，已按 2026-10-21 代码校准；标注「规划 / V1.1」的能力尚未实现。
> 当前功能状态与测试结果以 [docs/README](../README.md)、[wiki](../wiki/README.md) 和 `records/` 为准。

- 文档版本：v1.1（按实现校准）
- 对应 PRD：`docs/product/01-prd.md`
- 目标 SDK：HarmonyOS 6.0 / API 26（`targetSdkVersion: 26.0.0`）
- 语言与框架：ArkTS / ArkUI（Stage 模型）
- 设备：phone / tablet / 2in1

---

## 1. 技术选型

| 领域 | 选型 | 理由 |
|---|---|---|
| UI 框架 | ArkUI 声明式 | 原生性能、一多适配、系统组件一致 |
| 状态管理 | 状态管理 V2（`@ComponentV2` / `@Local` / `@Param` / `@ObservedV2` / `@Trace`） | 新工程无历史包袱，细粒度刷新更可控 |
| 路由 | `Navigation` + `NavPathStack` | 支持单栏/分栏/自适应，适合手机到 2in1 |
| 本地数据库 | `@ohos.data.relationalStore`（RDB） | 事务、索引、复杂查询、稳定 |
| 键值配置 | `@ohos.data.preferences` | 轻量设置、同步游标、卡片快照 |
| 网络 | `@ohos.net.http` | WebDAV、元数据抓取、失效检测 |
| 文件 | `@ohos.file.fs` + `DocumentViewPicker` | 导入 HTML、导出、快照文件 |
| 剪贴板 | `PasteButton` 安全控件 + `@ohos.pasteboard` | 点击即授权，避免权限弹窗骚扰 |
| 分享接收 | `ShareExtensionAbility` | 任意 App 分享链接直接收笺 |
| 服务卡片 | Form Kit（`FormExtensionAbility`） | 桌面「今日笺」与快捷收笺 |
| 跨设备 | WebDAV（主）+ `@ohos.data.distributedKVStore`（辅） | 跨网络 + 同账号局域网双通道 |
| 加密 | HUKS + `@ohos.security.cryptoFramework` | 加密 WebDAV 凭据，后续支持 E2EE |
| 测试 | Hypium（`@ohos/hypium`） | 工程自带，覆盖解析/合并/规范化 |

**原则：零第三方运行时依赖。** 解析器、同步引擎、正文提取全部自研，控制包体与供应链风险。

---

## 2. 总体架构

```
┌────────────────────────────────────────────────────────────┐
│                         UI 层                               │
│  pages/  components/  （手机单栏 / 平板双栏 / 2in1 三栏）    │
└───────────────▲──────────────────────────────┬─────────────┘
                │ @Local/@Param 状态            │ 事件
┌───────────────┴──────────────────────────────▼─────────────┐
│                      ViewModel 层                           │
│  StreamVM  DetailVM  InboxVM  ImportVM  SyncVM  SettingsVM  │
└───────────────▲──────────────────────────────┬─────────────┘
                │ 只读模型 / 命令               │
┌───────────────┴──────────────────────────────▼─────────────┐
│                     Repository 层                           │
│  BookmarkRepo  TagRepo  SyncRepo  SettingsRepo              │
└──────▲───────────────▲───────────────▲──────────────▲──────┘
       │               │               │              │
┌──────┴─────┐  ┌──────┴──────┐  ┌─────┴──────┐  ┌────┴─────┐
│ RDB / File │  │ WebDAV 同步  │  │ 分布式 KV  │  │ 系统服务  │
│ 本地事实源  │  │ 引擎         │  │ 通道       │  │ 分享/卡片 │
└────────────┘  └─────────────┘  └────────────┘  └──────────┘
```

**单一事实源**：所有数据先写本地 RDB，再由 `SyncEngine` 异步同步。任何同步失败都不影响本地使用。

---

## 3. 工程结构

```
entry/src/main/ets/
├── entryability/EntryAbility.ets      # 主入口、Want 分发、接续
├── shareability/ShareAbility.ets      # 分享扩展
├── formability/TodayCardAbility.ets   # 服务卡片
├── pages/
│   ├── Index.ets                      # Navigation 根容器 + 三断点布局
│   ├── SharePage.ets                  # 分享落地页
│   ├── TagsPage.ets                   # 标签管理
│   ├── SyncPage.ets                   # 同步中心 + 冲突列表
│   └── SettingsPage.ets               # 导入/导出/主题/清空
├── components/
│   ├── BookmarkRow.ets
│   ├── DetailContent.ets              # 详情 + 正文/摘录/备注 + 编辑
│   ├── InboxSheet.ets                 # 收笺半模态
│   ├── NavigationRail.ets             # 宽屏侧栏
│   └── StreamHome.ets                 # 首页流、搜索、筛选、分页
├── repository/
│   └── FlowRepository.ets             # UI 唯一数据入口
├── core/
│   ├── db/Database.ets                # 建表、增量加列、索引
│   ├── db/BookmarkDao.ets
│   ├── parser/BookmarkHtmlParser.ets
│   ├── security/CredentialCipher.ets  # HUKS AES-256-GCM
│   ├── service/
│   │   ├── CardPublisher.ets
│   │   ├── CardSnapshot.ets
│   │   ├── MetadataService.ets
│   │   └── SnapshotStore.ets
│   └── sync/
│       ├── SyncConfigStore.ets
│       ├── SyncEngine.ets
│       ├── SyncErrorText.ets
│       ├── SyncPlanner.ets
│       ├── SyncRecord.ets
│       ├── SyncTransport.ets
│       ├── WebDavTransport.ets
│       ├── WebDavTypes.ets
│       └── WebDavXml.ets
├── model/                             # Bookmark/Query/Conflict/Tag/Tombstone 等
├── common/                            # AppState/Constants/UrlUtil/Highlight 等
└── widget/pages/                      # RecentCard.ets、TodayCard.ets（V1 卡片）
```

> 原设计中的 `StreamPage` / `DetailPage` / `BrowserPage` / `DistributedTransport` / `MergePolicy` 等未落地：
> 首页与详情分别由 `StreamHome`、`DetailContent` 承担；分布式通道与内置浏览器仍为 V1.1 规划。

---

## 4. 数据模型

### 4.1 表结构

```sql
CREATE TABLE IF NOT EXISTS bookmark (
  id              TEXT PRIMARY KEY,
  url             TEXT NOT NULL,
  url_key         TEXT NOT NULL,
  domain          TEXT NOT NULL DEFAULT '',
  title           TEXT NOT NULL DEFAULT '',
  description     TEXT NOT NULL DEFAULT '',
  site_name       TEXT NOT NULL DEFAULT '',
  favicon_url     TEXT NOT NULL DEFAULT '',
  cover_url       TEXT NOT NULL DEFAULT '',
  note            TEXT NOT NULL DEFAULT '',
  excerpt         TEXT NOT NULL DEFAULT '',
  snapshot_path   TEXT NOT NULL DEFAULT '',
  snapshot_status INTEGER NOT NULL DEFAULT 0, -- 0 待补全 1 成功 2 失败 3 关闭
  snapshot_at     INTEGER NOT NULL DEFAULT 0,
  search_text     TEXT NOT NULL DEFAULT '',
  source          INTEGER NOT NULL DEFAULT 0, -- 0 手动 1 分享 2 粘贴 3 导入 4 碰一碰 5 内置浏览器
  folder_path     TEXT NOT NULL DEFAULT '',
  read_state      INTEGER NOT NULL DEFAULT 0, -- 0 未读 1 在读 2 已读
  starred         INTEGER NOT NULL DEFAULT 0,
  archived        INTEGER NOT NULL DEFAULT 0,
  deleted         INTEGER NOT NULL DEFAULT 0,
  created_at      INTEGER NOT NULL,
  updated_at      INTEGER NOT NULL,
  read_at         INTEGER NOT NULL DEFAULT 0,
  rev             INTEGER NOT NULL DEFAULT 1,
  remote_etag     TEXT NOT NULL DEFAULT '',
  dirty           INTEGER NOT NULL DEFAULT 1,
  link_status     INTEGER NOT NULL DEFAULT 0,
  link_checked_at INTEGER NOT NULL DEFAULT 0,
  device_id       TEXT NOT NULL DEFAULT ''
);

CREATE UNIQUE INDEX IF NOT EXISTS idx_bookmark_url_key
  ON bookmark(url_key);
CREATE INDEX IF NOT EXISTS idx_bookmark_stream
  ON bookmark(deleted, archived, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmark_starred
  ON bookmark(deleted, starred, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmark_read
  ON bookmark(deleted, read_state, created_at DESC);
CREATE INDEX IF NOT EXISTS idx_bookmark_domain
  ON bookmark(deleted, domain);

CREATE TABLE IF NOT EXISTS tag (
  id         TEXT PRIMARY KEY,
  name       TEXT NOT NULL,
  name_key   TEXT NOT NULL,
  created_at INTEGER NOT NULL
);
CREATE UNIQUE INDEX IF NOT EXISTS idx_tag_name_key ON tag(name_key);

CREATE TABLE IF NOT EXISTS bookmark_tag (
  bookmark_id TEXT NOT NULL,
  tag_id      TEXT NOT NULL,
  PRIMARY KEY (bookmark_id, tag_id)
);
CREATE INDEX IF NOT EXISTS idx_bookmark_tag_tag ON bookmark_tag(tag_id);

CREATE TABLE IF NOT EXISTS conflict (
  id          TEXT PRIMARY KEY,
  bookmark_id TEXT NOT NULL,
  local_json  TEXT NOT NULL,
  remote_json TEXT NOT NULL,
  reason      TEXT NOT NULL,
  created_at  INTEGER NOT NULL
);

CREATE TABLE IF NOT EXISTS sync_state (
  key   TEXT PRIMARY KEY,
  value TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS tombstone (
  id          TEXT PRIMARY KEY,
  remote_id   TEXT NOT NULL DEFAULT '',
  deleted_at  INTEGER NOT NULL,
  attempts    INTEGER NOT NULL DEFAULT 0,
  last_error  TEXT NOT NULL DEFAULT ''
);
```

### 4.2 模型约定

- `id`：UUID v4 字符串；导入时为每条生成，保证多端不撞。
- 时间：毫秒时间戳 `number`；同步比较使用服务端/本机时钟，允许 ±2 分钟漂移。
- `rev`：本地每次写 +1；用于同毫秒冲突的次级比较。
- `url_key`：`normalizeUrl()` 后的规范化 URL 字符串（补 `https://`、小写 host、去 fragment/跟踪参数、query 排序），唯一索引负责去重。
- `search_text`：小写拼接 `title + description + site_name + url + note + excerpt + tags`，写入时更新。
- `dirty`：本地有未上传修改时为 1；上传成功且 `rev + updated_at` 未变化时才清除。
- `link_status` / `link_checked_at`：失效链接检测结果与检查时间。
- 布尔值用 `0/1`，避免 RDB 布尔兼容问题。
- 删除为软删除：`deleted = 1`，30 天后物理清理并写入 `tombstone`（墓碑）。墓碑保存远端文件 ID，下一次同步补发 `DELETE`；`DELETE` 返回 404 视为成功，401/403/网络错误保留墓碑等待重试。

### 4.3 数据库迁移

- 没有 `DB_VERSION`，也没有版本化迁移脚本或迁移事务。
- `Database.applySchema()` 每次启动执行 `CREATE TABLE IF NOT EXISTS` 与 `CREATE INDEX IF NOT EXISTS`；
  后加列通过 `addColumn()` 执行 `ALTER TABLE ... ADD COLUMN`，异常直接忽略（列已存在）。
- 新增列时必须同时改 `Database.SQL_BOOKMARK` 并在 `addColumn()` 列表补一条；现有后加列为
  `dirty`、`link_status`、`link_checked_at`、`domain`。
- 批量写入使用显式事务；HTML 导入每 250 条提交一次。

---

## 5. 关键能力实现

### 5.1 分享收笺（ShareExtensionAbility）

**入口配置**：`module.json5` 注册 `ShareAbility`（`type: share`），`skills` 声明 `ohos.want.action.sendData`，`uris` 接收 `scheme: file` 的 `general.hyperlink` / `general.text`，`maxFileSupported: 1`。

**处理流程**：

1. `onSessionCreate` 通过 `systemShare.getSharedData(want)` 读取分享记录，优先取文本/URI 中的第一个 URL，并带出标题。
2. `session.loadContent('pages/SharePage')` 展示轻量收笺页：链接、标题、标签输入；标题为空时本地快速补全。
3. 用户点击「收下」→ 写入 RDB → `terminateSelf` 关闭分享页。
4. 写入后立即异步调用 `applyMetadata()` 补全元数据与正文快照（设置允许时）；详情页可手动「重试抓取」。没有启动时批量扫描待补全记录的逻辑。

**约束**：

- 分享面板内不发起长耗时网络请求，避免用户等待。
- 无网络时也能保存，仅保存 URL 与域名。
- 面板高度控制在半屏内，键盘弹出时布局自适应。

### 5.2 粘贴收笺（PasteButton）

- 首页搜索框右侧放一个 `PasteButton`，用户点击时系统临时授权读取剪贴板，**不弹权限框**。
- 读取后调用 `extractFirstUrl()`：支持纯 URL、带文案的分享文本、含多个 URL 时取第一个合法项。
- 命中后打开 `InboxSheet` 预填；未命中给出轻提示「剪贴板里没有链接」。
- 不申请 `READ_PASTEBOARD` 动态权限，避免每次启动弹窗；仅在安全控件不可用时降级申请。

### 5.3 HTML 书签导入

**格式**：Netscape Bookmark File（Chrome / Edge / Safari / Firefox / 华为浏览器导出）。

**解析器**：手写状态机，不引入 DOM 库。

```
扫描 token：
  <H3>folder</H3>   → pendingFolder = decode(text)
  <DL>              → stack.push(pendingFolder ?? '')
  </DL>             → stack.pop()
  <A HREF="url">t</A> → emit({ url, title: decode(t), folderPath: stack.join('/') })
```

要点：

- 属性支持单/双引号与大小写混合；解析按行扫描，跨行标签或压缩 HTML 可能漏解析。
- HTML 实体解码：`&amp; &lt; &gt; &quot; &#39; &#x...;`。
- 文件夹名去空、去重；路径映射为层级标签 `技术/前端`。
- 编码：当前固定按 UTF-8 读取，尚未实现 GBK/GB2312 自动检测；非 UTF-8 文件需用户自行转码。
- 去重：按 `url_key` 查询已有记录；重复项跳过并计数。
- 写入：每 250 条一个事务批量插入；导入过程显示 `已处理 / 总数`，支持取消与失败清单导出。
- 结果：成功、跳过、失败三组；失败 URL 可导出。
- 解析实现按行扫描 `<H3>` / `<DL>` / `<A>`，适配浏览器导出的标准 Netscape 格式；非换行的压缩 HTML 可能解析不全。

**性能目标**：5000 条导入 ≤ 8 秒（2in1）；设备实测约 4.5–7 秒，测试断言使用 12 秒保险阈值。

### 5.4 元数据抓取

`MetadataService.fetch(url)`：

1. 仅允许 `http` / `https`；拒绝 `file` / `data` / `javascript`。
2. `http.createHttp()`，`GET`，`Accept: text/html`，UA 使用应用标识，`connectTimeout: 8000`，`readTimeout: 8000`，最大读取 512 KB。
3. 编码：从响应头 `charset` 判定，缺省 UTF-8；尚未解析 HTML `<meta charset>`。
4. 解析优先级：
   - 标题：`og:title` → `<title>` → 域名
   - 描述：`og:description` → `meta[name=description]` → 正文首 160 字
   - 封面：`og:image`
   - 站点名：`og:site_name` → 域名
   - 图标：`link[rel~=icon]` → `/favicon.ico`
5. 失败降级：保留域名与 URL，`snapshot_status = 2`，详情页提供「重试」。
6. 当前未实现并发上限与同域名串行；抓取在 Repository 层逐条触发。

### 5.5 正文快照与阅读模式

**提取与落盘**

- 优先复用元数据请求返回的 HTML，避免二次请求。
- 去脚本/样式/导航/页脚 → 取 `<article>` 或文本密度最高的容器 → 输出结构化块（heading / paragraph / quote / listItem / code）。
- 上限 204800 字符（按字符计，不按 UTF-8 字节；常量名沿用 `Limits.snapshotBytes`），存 `files/snapshots/{id}.txt`；RDB 只存路径与 400 字内描述。
- 失败不影响收笺。

**当前实现（2026-10-22，结构化快照 + 原生阅读器）**

- `ArticleExtractor` 从同一份元数据 HTML 中提取正文块（heading / paragraph / quote / listItem / code），
  在 `<article>` / `<main>` / 正文 class/id 容器 / `<body>` 中选覆盖足够的候选：所有候选都需覆盖清理后的
  `<body>` 至少 50%。**先对 body 做 junk 清理再计分**，否则 `<article class="comments">`、`.post-navigation`、
  `.article-list` 等会劫持真实正文；junk 判定按 class/id 的 `[\s_-]+` token 匹配（`downloads` / `uploads` /
  `threads` / `unavailable` / `commentary` 等不误删），并覆盖 `<article>` 容器。`teaser` / `recommend` /
  `related` / `promo` 为强 teaser，`card` / `summary` 为弱 teaser；强弱 teaser 都只在存在另一个非 teaser 的
  `<article>` 竞争正文且剩余非 teaser 文本至少 200 字时才删除；`<main>` 与正文 class/id 包装可能只是把 teaser
  和未命名评论包在一起，不算竞争容器；未被命名的 `<div>`（如评论）同样不算，此时保守保留 teaser，优先不丢正文。`post-meta` / `entry-meta` / `post-header` 等命名同样按 token 作为噪声移除，候选过小时回退
  `<body>`；保留 `<article>` 与 `<main>` 内 `<header>` 的导语，同时剔除导航、页脚、评论、分享、广告等噪声。
  标题去重先剥离站点后缀并支持 CJK 短标题前缀比较。
- `ArticleCodec` 把块编码为带 `FLOWPAGE-ARTICLE-1` 版本头的文本，仍存
  `files/snapshots/<id>.txt`；旧纯文本快照读取时降级为段落。正文仍不上传同步。
- `ReaderView` 提供行内与全屏两种形态：全屏使用 `bindContentCover`；支持字号/行距/段距、TOC、
  正文搜索与高亮、选中存摘录、阅读进度和按书签恢复位置；进度 ≥90% 标记已读。
- 阅读偏好存 `flowpage_settings`，阅读位置存本机 `flowpage_reader`，不新增同步字段。
- 内置浏览器（`Web` 组件 + 在线注入提取）仍未实现，保留为后续增强。

### 5.6 服务卡片

- 两张卡片：`2x2 今日笺`、`2x4 最近三条`，分别由 `TodayCardAbility` 与 `form_config.json` 注册。
- `FormExtensionAbility` 与主应用不同进程：主应用在数据变更后把卡片所需的轻量 JSON 写入 `preferences`（`card_snapshot`），卡片读取该快照渲染，避免跨进程 RDB 竞争。
- 刷新：`updateDuration: 30` 分钟 + 主应用变更后 `formProvider.requestFormUpdate`。
- 交互：点击卡片 → `FormLink` 拉起应用并直达详情；今日笺提供「换一笺」，通过 `postCardAction` 触发 `message` 本地轮换。
- 空状态：无收藏时展示「去收第一笺」。
- 状态：桌面真实添加与刷新仍需人工验收，见 `quality/01-walkthrough-checklist.md` §5.4。

### 5.7 WebDAV 同步引擎

#### 5.7.1 远端布局

```
{baseUrl}/FlowPage/v1/
├── items/
│   ├── {bookmarkId}.json
│   └── ...
└── tombstones/          # 已彻底删除的书签 ID（仅 id + 时间，无正文）
    └── {bookmarkId}.json
```

单条一文件，避免整库文件冲突；便于增量与断点。`meta.json` 为早期设计，当前未使用。

#### 5.7.2 记录格式

```json
{
  "schema": 2,
  "id": "uuid",
  "url": "https://example.com/a",
  "title": "标题",
  "description": "摘要",
  "siteName": "站点",
  "faviconUrl": "…",
  "coverUrl": "…",
  "note": "备注",
  "excerpt": "摘录",
  "tags": ["技术/前端"],
  "folderPath": "技术/前端",
  "source": 3,
  "createdAt": 1730000000000,
  "updatedAt": 1730000000000,
  "readAt": 0,
  "readState": 0,
  "starred": false,
  "archived": false,
  "deleted": false,
  "rev": 3,
  "deviceId": "…",
  "linkStatus": 0,
  "linkCheckedAt": 0
}
```

> `schema: 2` 起同步 `folderPath` 与 `source`；旧记录缺少时按本地默认值处理。正文快照不上传。

#### 5.7.3 同步算法

```
sync():
  1. 连接测试：PROPFIND baseUrl，校验 207/200 与认证
  2. 确保目录：MKCOL FlowPage / v1 / items / tombstones（已存在则忽略 405）
  3. PROPFIND items/ Depth:1 → 得到 [{href, etag, lastModified}]
  4. 远端集合 R，本地映射 L（id → remote_etag）
  5. 待下载 D = { r ∈ R | L[r.id] 不存在 或 L[r.id].etag ≠ r.etag }
  6. 待上传 U = { l ∈ L | l.dirty } ∪ { l ∈ L | l.id ∉ R }
  7. for r in D: GET → 解析 → mergeRemote(local, remote)
  8. for l in U: PUT items/{id}.json
       header If-Match: 本地记录的 etag（新文件用 If-None-Match: *）
       412 → 重新 GET → merge → 重试（最多 3 次）
  9. 远端墓碑 R_t = PROPFIND tombstones/；命中 id：删除本地同 id 书签、清理残留 item，并阻止下载
  10. 本地墓碑 T：先 PUT tombstones/{id}.json（让其他设备感知删除），再 DELETE items/{id}.json；
      两步成功（DELETE 404 视为成功）后清除本地墓碑，失败保留重试
  11. 下载前检查墓碑：命中则跳过下载，绝不复活
  12. 上传成功后仅在 rev + updatedAt 未变化时回填 ETag 并清 dirty
  13. 最近同步时间写入 preferences（`last_sync`），不写 `sync_state` 表
```

#### 5.7.4 合并策略

- 主键 `id`；`url_key` 冲突（不同 id 同 URL）→ 保留较早创建者，另一条合并标签与备注后软删除。
- 双方都有修改：比较 `updatedAt`，较大者胜；相同则 `rev` 大者胜；再相同则本机胜。
- 败方完整 JSON 写入 `conflict` 表，同步中心可见，可「恢复此版本」。
- 删除优先：任一端 `deleted = true` 且 `updatedAt` 更新 → 删除；否则保留。
- 标签取并集（非冲突字段可自动合并），备注/标题/摘要走 LWW。

#### 5.7.5 触发与容错

- 当前仅支持同步页手动「连接并同步」/「立即同步」；应用回前台自动同步、写入后防抖、网络恢复触发均未实现。
- 并发保护：`SyncPage` 的 `syncing` 标志阻止重复点击，不是跨进程锁。
- 失败重试：单条失败记录原因后继续；切换服务器会清空 ETag 但保留 dirty。
- 超时与单文件大小由 `WebDavTransport` 控制；仅 HTTPS 为正式建议，HTTP 明确警告。

#### 5.7.6 凭据安全

- **当前实现**：HUKS AES-256-GCM 加密后写入 `preferences` 的单一 `webdav_config` JSON；密钥别名 `flowpage_sync_credential_key`，解密仅在同步时于内存进行。
- 支持应用密码（坚果云需使用应用密码）。
- 断开连接时清除凭据与 `last_sync`，不删除本地数据；仅当服务器 `url + user` 指纹变化时才清空 `remote_etag`（保留 dirty）。

### 5.8 分布式数据通道

- **当前状态**：V1.1 规划，尚未实现；Sync 页显示「下一阶段接入」。计划使用 `@ohos.data.distributedKVStore`，库名 `flowpage_sync`，键 `b:{id}`，值与 WebDAV 记录格式一致。
- 权限：`ohos.permission.DISTRIBUTED_DATASYNC`（用户授权）。
- 设备发现：`@ohos.distributedDeviceManager` 获取可信设备列表；仅在 `deviceManager` 可用且同账号组网时启用。
- 同步：`sync(deviceIds, PUSH_PULL)`，监听 `dataChange` 做增量合并，复用 WebDAV 的 LWW 合并规则。
- 限制：仅同应用、同账号、可信组网；不传快照正文（体积大），只同步元数据与标签。
- 冲突：与 WebDAV 相同的 LWW + 冲突表。

### 5.9 碰一碰 / 隔空传送 / App Linking

- **发送（V1.1 规划）**：通过 `systemShare` 分享 `https://{domain}/b/{id}` 链接，配合 Share Kit 的碰一碰/隔空传送能力。当前实现分享的是原文 URL。
- **接收（V1.1 规划）**：`module.json5` 声明 `ohos.want.action.viewData` + `https` 域名 + `domainVerify: true`；同时注册自定义 scheme `flowpage://bookmark/{id}` 作为无域名兜底。
- **当前实现**：仅注册自定义 scheme `flowpage://bookmark/{id}`，可显式拉起详情；分享面板已接入 Share Kit。HTTPS App Linking 仍需真实域名与 `/.well-known/applinking.json`，作为发布前配置项。
- 碰一碰需要两台真机；单设备环境仅验证分享面板与链接解析。

### 5.10 应用接续

- 已在 `module.json5` 设置 `continuable: true` 与 `launchType: singleton`，并实现 `onContinue`。
- `onContinue` 当前只传递 `bookmarkId`；滚动位置、阅读模式、字号尚未传递。
- 目标端 `onCreate` / `onNewWant` 读取 `want.parameters.bookmarkId` 恢复对应详情。
- 数据量 < 100 KB，直接走 `want.param`，不传文件。
- 应用接续已完成手机/2in1 双机验证；当前只恢复当前书签，滚动位置与阅读模式未传递。

### 5.11 搜索

- 查询：`WHERE deleted = 0 AND search_text LIKE ?`，参数 `%kw%`，转义 `%` `_` `\`。
- 排序：`created_at DESC` 或 `domain ASC, created_at DESC`；可按标签、关键词、已读/星标/归档/回收站叠加过滤。
- 结果高亮：在 UI 层对 `title` / `description` 做子串定位，使用 `Span` 分段着色。
- 目标 10,000 条 < 100 ms；当前测试保险阈值为 1000 条 < 100 ms、10,000 条 < 200 ms，设备实测 1–19 ms。

---

## 6. 权限与隐私

### 6.1 权限清单

| 权限 | 级别 | 用途 | 状态 |
|---|---|---|---|
| `ohos.permission.INTERNET` | system_grant | 元数据、WebDAV、失效链接检测 | 已申请 |
| `ohos.permission.GET_NETWORK_INFO` | system_grant | 网络状态与同步触发 | 规划，未申请 |
| `ohos.permission.DISTRIBUTED_DATASYNC` | user_grant | 分布式同步 | 规划，未申请 |
| `ohos.permission.READ_PASTEBOARD` | user_grant | 安全控件不可用时的降级 | 规划，未申请 |

当前 `module.json5` 只声明 `ohos.permission.INTERNET`；粘贴使用系统 `PasteButton` 安全控件，无需额外权限。

不申请：通讯录、位置、相机、麦克风、相册、后台持续运行。

### 6.2 隐私设计

- 默认纯本地；未开启同步时无任何数据出端。
- 不接入统计、广告、推送 SDK。
- 元数据抓取仅请求用户主动收藏的 URL；不携带设备标识。
- WebDAV 凭据加密存储；日志中脱敏 URL 查询参数与账号。
- 提供「导出全部数据」与「清空本机数据」，导出格式开放（JSON + Netscape HTML）；当前没有应用内独立隐私说明页，首次启动也不弹隐私弹窗。

---

## 7. 性能与质量预算

| 指标 | 目标 |
|---|---|
| 冷启动到首页可交互 | ≤ 800 ms（2in1） |
| 首页 1000 条滚动 | 稳定 60 fps；当前使用 `List` + `ForEach`，每页 50 条 |
| 单条收笺（本地写入） | ≤ 100 ms |
| 元数据抓取 | P90 ≤ 3 s，超时 8 s |
| 5000 条 HTML 导入 | 目标 ≤ 8 s；设备实测 4.5–7 s，测试保险阈值 12 s |
| 搜索 10,000 条 | 目标 ≤ 100 ms；测试保险阈值 200 ms |
| 同步 1000 条增量 | ≤ 30 s（良好网络） |
| 安装包 | ≤ 20 MB |
| 崩溃率 | < 0.1% |

> 性能阈值为目标与测试门禁，实际数字随设备负载浮动，以 `QueryTest` / `ImportTest` 断言和 quality 走查记录为准。

**降级策略**：

- 网络失败 → 本地可用，标记待补全。
- WebDAV 不可用 → 提示并保留本地变更，下次重试。
- 分布式不可用 → 自动隐藏入口，不阻塞主流程。
- 卡片刷新失败 → 展示上次快照。

---

## 8. 测试策略

### 8.1 单元测试（Hypium）

设备端在 `entry/src/ohosTest`，当前 11 个套件 / 106 个用例：

| 套件 | 覆盖 |
|---|---|
| `WebDavXmlTest` | ETag、目录过滤、URL 解码 |
| `SyncPlannerTest` | 上传/下载/跳过/采纳 ETag 的规划分支 |
| `SyncEngineTest` | 上传、下载、墓碑删除、重试、不复活、标签合并、schema 1/2 兼容 |
| `SyncStoreTest` | URL 归一化、去重、墓碑、dirty 竞态、冲突记录、旧库迁移 |
| `TagSyncTest` | 标签改名/合并/删除、`search_text` 重建、回收站计数 |
| `SnapshotTest` | clearAll/purgeExpired/purge/purgeFromRemote 快照清理 |
| `ReaderTest` | 正文容器与 teaser/junk 规则、标题去重、元数据写回分类、阅读进度 |
| `ConflictTest` | 冲突计数、列表、恢复本地/采用远端 |
| `RepositoryTest` | 编辑 rev、阅读状态、自动快照、摘要口径、卡片序列化 |
| `QueryTest` | SQL 分页、关键字/标签过滤、LIKE 转义、域名排序、冷/热基准 |
| `ImportTest` | 解析、预览、去重、取消、失败清单、5000 条导入 |

### 8.2 集成与手工验收

- 2in1 真机：全流程（收笺 → 搜索 → 详情 → 导出 → 同步）。
- 手机：分享、粘贴、导入、深色、回收站、阅读字号。
- 分享扩展：从浏览器、备忘录、文件管理器分享链接。
- 服务卡片：添加、刷新、点击直达、空状态（仍需人工验收）。
- 深色模式、字体放大、横竖屏切换。
- 异常：断网、错误密码、WebDAV 404、磁盘满。

### 8.3 构建与静态检查

- 每个 `.ets` 文件写入后运行 `check_ets_files`。
- 提交前 `hvigorw clean assembleHap` 必须成功；**不要使用 `devecocli build`**（内置 hvigor 不支持本工程 `modelVersion 26.0.0`）。
- 设备端测试通过后再进入 UI 走查；命令见 [wiki/05-build-and-run.md](../wiki/05-build-and-run.md)。

---

## 9. 技术风险与对策

| 风险 | 对策 |
|---|---|
| API 26 分享扩展/接续字段与文档示例有差异 | 先做最小可用 Demo 验证，再扩展；保留 `flowpage://` 兜底 |
| `TextDecoder` 对 GBK 支持不确定 | 实测；失败时降级 UTF-8 并提示用户转码 |
| WebDAV 服务商差异（坚果云/群晖/Alist） | 只用标准方法；连接测试分步提示；提供请求日志导出 |
| 2in1 上 Web 组件与窗口行为差异 | 单独适配窗口尺寸变化与键鼠事件 |
| 碰一碰/分布式缺少第二设备与组网条件 | 明确标注「未验证」，以 WebDAV 为主通道，提供自测脚本与模拟数据 |
| 同步文件数过多导致 PROPFIND 慢 | 5000 条后切换分片清单 |
| 网页正文提取质量 | 先纯文本 + 手动摘录；阅读模式作为增强，不承诺完美 |

---

## 10. 开发顺序（技术视角）

> 状态：1–6 与 8 的接续已落地；7（内置浏览器/阅读模式）与 8 的分布式、碰一碰未落地，按 V1.1 规划。

1. 工程骨架、主题 token、Navigation 三断点。
2. RDB、Repository、模型与迁移。
3. 首页、详情、手动收笺、搜索、标签。
4. 分享扩展、粘贴控件、HTML 导入。
5. 服务卡片、深色、2in1 交互。
6. WebDAV 同步引擎与冲突 UI。
7. 内置浏览器、阅读模式、快照增强（V1.1）。
8. 分布式通道、碰一碰、接续（仅接续已完成）。
9. 性能优化、异常兜底、验收。
