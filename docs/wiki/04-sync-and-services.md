# 同步与服务

本篇说明 WebDAV 协议实现、同步算法、合并/墓碑语义、凭据加密，以及元数据抓取与服务卡片数据。

## 1. 远端布局

同步只使用标准 WebDAV 方法，远端根为用户配置的 URL，目录固定为：

```
<base>/
└── FlowPage/
    └── v1/
        ├── items/<bookmark-id>.json       # 一条书签一个文件
        └── tombstones/<bookmark-id>.json  # 彻底删除的墓碑
```

`ensureBase()` 依次 MKCOL 这四层目录；`405` 视为已存在。文件名使用 `encodeURIComponent(id)`。
正文快照、标签表结构、冲突记录都**不在远端**；远端只存 `SyncRecord` 的 JSON。

## 2. WebDavTransport

[WebDavTransport.ets](../../entry/src/main/ets/core/sync/WebDavTransport.ets) 实现
[SyncTransport](../../entry/src/main/ets/core/sync/SyncTransport.ets) 接口：

| 方法 | HTTP | 约定 |
|---|---|---|
| `test()` | `PROPFIND` Depth 0 | 接受 207/200；401/403/404 转成明确错误 |
| `ensureBase()` | `MKCOL` ×4 | 201/200/405 成功；409 → `PARENT_MISSING` |
| `listItems()` | `PROPFIND` Depth 1 | `WebDavXml.parseItems()`，只收 `.json` |
| `listTombstones()` | `PROPFIND` Depth 1 | 404 视为空列表 |
| `put(name, json, etag)` | `PUT` | 已知 ETag 时带 `If-Match`；新文件不带条件头 |
| `get(name)` | `GET` | 返回状态、正文、ETag |
| `remove(name)` | `DELETE` | 404 视为删除成功，便于重试 |
| `putTombstone(id)` | `PUT` | JSON `{schema,id,purgedAt}` |

- 认证是 `Authorization: Basic base64(user:password)`；日志用 `safeUrl()` 隐藏 URL 中内嵌的凭据。
- PUT 成功后优先读响应头 `ETag`（大小写不敏感）；缺失时补一次 `PROPFIND Depth: 0` 读取并写回。
- 上传使用本次目录列表返回的远端 ETag，而不是本地可能过期的 `remote_etag`；远端不存在时不带 `If-Match`，
  这是避免 409/412 的关键。
- [WebDavXml.ets](../../entry/src/main/ets/core/sync/WebDavXml.ets) 是正则解析：href 末尾 `/` 跳过，
  去 query、URL 解码、只保留 `.json`；ETag 支持弱 ETag 与实体转义。
- 所有请求超时：连接 10s / 读取 30s；网络异常统一抛 `NET_<code>`。

## 3. 配置与凭据

[SyncConfigStore.ets](../../entry/src/main/ets/core/sync/SyncConfigStore.ets) 把配置存在 preferences
`flowpage_sync` 的单个 `webdav_config` JSON 中（避免多键写入不一致）：

```json
{ "url": "...", "user": "...", "passwordEnc": "<nonce>:<cipher>", "fingerprint": "url|user" }
```

- `fingerprintOf(url, user)` 去掉 URL 尾部 `/`、user 去空格转小写；保存时返回“是否变化”。
  `SyncPage` 在变化时调用 `clearRemoteEtags()`，只清 ETag、不清 `dirty`。
- `CredentialCipher` 使用 HUKS 中别名 `flowpage_sync_credential_key` 的 AES-256 密钥，GCM 模式、
  12 字节随机 nonce、AAD `flowpage-sync-credential`；输出 `base64(nonce):base64(cipher+tag)`。
- 解密失败或缺少密文时 `credentialInvalid=true`、密码为空，同步页要求重新输入。磁盘上不落明文密码；
  明文只存在于内存和密码输入框。
- `last_sync` 记录上次成功同步时间；`SyncConfigStore.clear()` 同时清旧版兼容键。

## 4. 同步引擎

[SyncEngine.ets](../../entry/src/main/ets/core/sync/SyncEngine.ets) 的 `sync()` 负责读配置和并发保护
（静态 `running`，重复进入抛 `BUSY`）；`run(transport, context)` 接受任意 `SyncTransport`，测试用 FakeTransport
直接跑这一层。

### 4.1 执行阶段

```
test → ensureBase → listItems / listTombstones
  → 处理远端墓碑
  → 逐条处理远端 items（缺失则下载；存在则规划）
  → 上传仅本地存在的书签
  → 发布本地墓碑并删除远端对应文件
  → setLastSync + FlowRepository.afterSync() → 中文汇总
```

- **远端墓碑**：本地同 id 存在则 `purgeFromRemote()`（删本地、快照、本地墓碑）；本地有同 id 墓碑则移除；
  远端仍有条目文件则 DELETE。
- **远端条目**：两端任一有同 id 墓碑就直接跳过，防止复活。本地缺失则 GET + `upsertFromRemote()`。
  本地存在则按 §4.2 规划。
- **仅本地条目**：远端从未出现且本地不 dirty 时也上传（首次全量）；有远端记录且不 dirty 时跳过。
- **本地墓碑**：远端墓碑不存在时先 `putTombstone()`，再删远端条目文件，最后删本地墓碑。
  PUT 或 DELETE 失败会 `markTombstoneFailed()`，保留墓碑并计入失败，下一轮重试。
- 汇总 `SyncReport`：`uploaded / downloaded / skipped / deleted / failed / firstFailure`，最后生成
  `上传 x · 下载 y · 跳过 z[ · 删除 n][ · 失败 m（首个原因）]`。

### 4.2 规划规则

[SyncPlanner.ets](../../entry/src/main/ets/core/sync/SyncPlanner.ets) 是纯函数：

| 函数 | 条件 | 动作 |
|---|---|---|
| `planForExisting` | 远端无 ETag 或 ETag 相同 | dirty ? UPLOAD : SKIP |
| | ETag 不同 | FETCH |
| `planAfterFetch` | `remoteUpdatedAt > localUpdatedAt` | DOWNLOAD |
| | 否则本地 dirty | UPLOAD |
| | 否则本地 ETag 为空 | ADOPT_ETAG |
| | 其余 | UPLOAD |
| `planForLocalOnly` | 不 dirty 且远端已知 | SKIP |
| | 其余 | UPLOAD |

`ADOPT_ETAG` 用条件更新写入远端 ETag；若期间本地被修改导致条件不匹配，则改为上传。

LWW 比较的是 `updatedAt`，`rev` 只用于并发写入检测与记录版本，**不参与新旧判断**。

### 4.3 上传竞态

上传前记录 `expectedRev = rev` 与 `expectedUpdatedAt = updatedAt`；PUT 成功后调用
`setRemoteEtagIfUnchanged()`。仅当两列仍匹配才写 `remote_etag`、清 `dirty`。同步期间用户又编辑时条件失败，
记录保持 dirty，下一轮继续上传新版本。这一情形不计入 `uploaded`，而计入 `skipped`，因为本轮上传的内容
没有成为最新版本；`uploaded` 只统计 ETag 已回填、`dirty` 已清除的条目。

### 4.4 失败语义

单条 PUT/GET/DELETE 失败只累加 `failed` 并记录首个错误，不中断整轮；整轮仍会写 `last_sync`，
但 `SyncPage` 会在 `failed > 0` 时提示“同步完成，但有 N 条失败”，不会误报完全成功。

## 5. 合并与冲突

[SyncRecord.ets](../../entry/src/main/ets/core/sync/SyncRecord.ets) 是远端 JSON 的字段白名单（schema 1）：
id、url、标题/摘要/站点/图标/封面、备注/摘录、标签、时间戳、阅读状态、星标/归档/删除、rev、deviceId、
链接状态。不含 `snapshotPath`、`searchText`、`remoteEtag`、`dirty`。

`FlowRepository.upsertFromRemote(record, etag)`：

1. 本地存在同 id 墓碑 → 拒绝，避免已彻底删除的条目复活。
2. `normalizeUrl(record.url)` 为空 → 拒绝。
3. 本地已有记录且 `dirty=true` → 把本地与远端 JSON 写入 `conflict`（`reason='lww-remote-wins'`），
   然后仍以远端版本覆盖（LWW 远端优先）。
4. 保留本地正文快照字段（`snapshotPath/snapshotStatus/snapshotAt`）与 `folderPath/source`（协议不传这两项，
   不能让下载把它们覆盖成空/0）；若远端 `linkStatus=0` 而本地已有检查结果，则保留本地链接状态。
5. 已有记录 `rev = 本地 rev + 1`，写入 `remoteEtag`，`dirty=false`；新记录直接插入。

冲突表在同步页可见：显示数量与列表，可展开查看本地/远端 JSON，并选择「恢复本地」或「采用远端」。
恢复会写回 bookmark、`rev+1`、`dirty=1`，并删除对应 conflict 记录；采用远端时同样保留本地 `folderPath/source`
与快照三字段。未做字段级合并，极端同时修改
仍可能丢失败方字段。

## 6. 服务卡片

卡片数据由 [CardSnapshot.ets](../../entry/src/main/ets/core/service/CardSnapshot.ets) 和
[CardPublisher.ets](../../entry/src/main/ets/core/service/CardPublisher.ets) 维护：

- `FlowRepository.writeCardSnapshot()` 取所有未删除且未归档的书签（按 `createdAt DESC`）：
  - 今日笺：`new Date().getDate() % active.length` 选一条（同一天稳定，不是随机）；
  - 最近：前 3 条，序列化为「标题 \u0001 域名 \u0001 id」换行串（标题压单行）；
  - 统计：未归档总数。
- 写入 preferences `flowpage_card` 的 `today_title/today_domain/today_id/recent_lines/total_count/today_candidates`。
- `CardPublisher.publish()` 先用 `formProvider.getPublishedRunningFormInfos()` 获取运行中的卡片并刷新
  持久化 ID 列表；失败时回退到 `flowpage_card_forms.form_ids`，逐个 `updateForm()`。
- **跨进程陷阱**：卡片 Ability 与应用不在同一进程。`CardSnapshot.open()` 在读取前必须调用
  `preferences.removePreferencesFromCacheSync()`，否则会读到旧快照。
- [TodayCardAbility.ets](../../entry/src/main/ets/formability/TodayCardAbility.ets) 处理 `onAddForm`（登记 ID）、
  `onUpdateForm` / `onFormEvent`（刷新）、`onRemoveForm`（移除 ID）。
- 卡片 UI 使用 V1 `@Component` + `@LocalStorageProp`，点击 `postCardAction` 以 `router` 拉起 `EntryAbility`。
- `FlowRepository.notify()` 已把“写快照 + 推送”串行合并，多个连续写入不会并发打架。

## 7. 元数据与正文快照

[MetadataService.ets](../../entry/src/main/ets/core/service/MetadataService.ets)：

- `fetch(url)`：GET，8s 连接/读取超时，限制 512 KiB；按响应头 `charset` 或 `<meta charset>` 解码，
  失败回退 UTF-8。抓取 `og:title`（回退 `<title>`）、`og:description`（回退 `description`，再回退正文前 160 字）、
  `og:site_name`、`og:image`、`rel=icon`（回退 `/favicon.ico`），相对地址用 `URL` 解析。
- 正文用正则去 script/style/注释/标签后折叠空白，截断到 204800 字符（常量名 `snapshotBytes`，实际按字符切）；
  标题截 200 字符、描述截 400 字符。
- `checkLink(url)`：HEAD，405/403 时 GET 兜底；2xx/3xx 可用（1），404/410/5xx 可能失效（2），其余未知（0）。
- `FlowRepository.applyMetadata()` 只在标题为空或等于域名兜底时用抓取标题覆盖，避免覆盖用户手改标题；
  快照文本落盘后 `snapshotStatus=DONE`，抓取失败置 `FAILED`。
- 设置页「自动保存正文快照」关闭后（preferences `flowpage_settings.auto_snapshot=false`），
  `MetadataService.fetch(url, false)` 仍抓取标题/摘要，但不返回正文，`snapshotStatus` 写 `OFF`。
- [SnapshotStore.ets](../../entry/src/main/ets/core/service/SnapshotStore.ets)：`filesDir/snapshots/<id>.txt`，
  纯文本、同步不包含。

## 8. 错误文案

[SyncErrorText.ets](../../entry/src/main/ets/core/sync/SyncErrorText.ets) 把内部错误串映射为中文：
`AUTH_401`（坚果云需应用密码）、`AUTH_403`、`NOT_FOUND`、`NO_CONFIG`、`NO_CREDENTIAL`、`BUSY`、
`PARENT_MISSING`、`NET_*`（2300006/2300007 不可达、2300028 超时）、`PUT_*`（401/403/409/412）、
`DELETE_*`、`GET_*`、`MKCOL_*`、`PROPFIND_*`、`STATUS_*`。新增错误码应同时补这里，避免 UI 直接显示内部串。
