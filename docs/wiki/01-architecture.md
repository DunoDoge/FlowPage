# 整体架构

本篇说明 FlowPage 的分层、Ability 入口、状态刷新机制与跨层数据流。

## 1. 分层模型

```
┌──────────────────────────────────────────────────────────────┐
│ 应用框架层（HarmonyOS）                                       │
│ UIAbility / ShareExtensionAbility / FormExtensionAbility /    │
│ ArkUI / RDB / Preferences / HTTP / HUKS / FormKit / ShareKit  │
└──────────────────────────────────────────────────────────────┘
        ▲                         ▲
        │ ArkTS API               │ Want / 深链
┌──────────────────────────────────────────────────────────────┐
│ ① 入口层  entryability / shareability / formability           │
│   EntryAbility · ShareAbility · TodayCardAbility             │
└──────────────────────────────────────────────────────────────┘
        ▲
┌──────────────────────────────────────────────────────────────┐
│ ② 表现层  pages + components + widget                         │
│   Index · SharePage · StreamHome · DetailContent · InboxSheet │
│   TagsPage · SyncPage · SettingsPage · TodayCard/RecentCard   │
└──────────────────────────────────────────────────────────────┘
        ▲ 只通过 FlowRepository
┌──────────────────────────────────────────────────────────────┐
│ ③ 仓库层  repository/FlowRepository（进程内单例）              │
│   统一读写入口、notify tick、元数据/快照编排、导入导出、卡片快照  │
└──────────────────────────────────────────────────────────────┘
        ▲
┌──────────────────────────────────────────────────────────────┐
│ ④ 核心层  core/                                               │
│   db（RDB/DAO）· sync（WebDAV/规划/合并/墓碑）· service        │
│   （元数据/快照/卡片）· parser · security（HUKS）              │
└──────────────────────────────────────────────────────────────┘
        ▲
┌──────────────────────────────────────────────────────────────┐
│ ⑤ 基础设施                                                   │
│   flowpage.db · preferences · filesDir/snapshots · 远端 WebDAV │
└──────────────────────────────────────────────────────────────┘

common/（AppState、URL/日期工具、枚举）与 model/（数据模型）
被 ②③④ 共同依赖，本身不反向依赖 UI。
```

| 层 | 目录 | 职责 |
|---|---|---|
| 入口层 | `entryability/`、`shareability/`、`formability/` | 解析 Want、接续、注册分享/卡片、初始化仓库 |
| 表现层 | `pages/`、`components/`、`widget/pages/` | 布局、交互、列表/详情渲染；不直接拼 SQL |
| 仓库层 | `repository/FlowRepository.ets` | UI 唯一写入口；写后统一 `notify()`，并串行刷新卡片 |
| 核心层 | `core/**` | RDB、WebDAV、同步算法、抓取、快照、加密、卡片数据 |
| 公共模型 | `common/`、`model/` | 全局状态、URL 归一化、枚举、带 `@Trace` 的数据对象 |

## 2. Ability 与页面入口

| Ability | 类型 | 入口行为 |
|---|---|---|
| `EntryAbility` | `UIAbility` | 主入口；处理 `bookmarkId`、`flowpage://bookmark/{id}`、`http(s)` URL，初始化 RDB |
| `ShareAbility` | `ShareExtensionAbility` | 接收系统分享，把 URL/标题放入 `AppStorage` 后加载 `pages/SharePage` |
| `TodayCardAbility` | `FormExtensionAbility` | 卡片添加/刷新/事件/移除，读取 preferences 快照 |

`EntryAbility.onCreate/onNewWant` 的路由分发见 [EntryAbility.ets](../../entry/src/main/ets/entryability/EntryAbility.ets)：

- `want.parameters.bookmarkId` 或 `flowpage://bookmark/{id}` → `AppState.openBookmark(id)`；手机端由
  `routeTick` 触发 `NavPathStack.pushPathByName('detail')`，宽屏直接更新 `selectedId`。
- `http://` / `https://` → `AppState.openInbox(url)`，首页弹出收笺面板。
- 接续启动时 `restoreWindowStage` 并在 `onContinue` 里只携带当前 `selectedId`；页面栈不自动恢复。

`main_pages.json` 只有 `pages/Index` 与 `pages/SharePage` 两个真实路由。标签、同步、设置是组件：
宽屏由 `AppState.pane` 切换，手机由 `NavPathStack` 以 `tags` / `sync` / `settings` 名称推入。

## 3. 状态与刷新（关键）

`AppState` 是 `@ObservedV2` 单例，充当轻量事件总线：

| 状态 | 用途 |
|---|---|
| `selectedId` / `pane` | 当前详情与宽屏面板 |
| `routeTick` / `routeId` | 请求手机端打开详情；`consumeRoute()` 保证只消费一次 |
| `refreshTick` | 数据版本号；`StreamHome`、`TagsPage`、`SyncPage`、`SettingsPage` 用 `@Monitor` 监听后重载 |
| `tagFilter` | 标签页到首页的筛选条件 |
| `inboxUrl` / `showInbox` | 收笺面板开关与预填 URL |
| `toastText` | 2.4 秒后自动清除的轻提示 |

**写路径必须单调**：UI → `FlowRepository` → DAO/服务 → `notify()`。
`notify()` 递增 `refreshTick` 并调用 `scheduleCardSnapshot()`。直接拿 `BookmarkDao` 写入会绕过 UI 刷新和
卡片推送，是新增功能时最常见的错误。

`Index` 的 `ready` 在 `FlowRepository.init()` 成功后置真；初始化失败只 toast，不阻塞页面框架。

## 4. 核心数据流

### 4.1 收笺

```
InboxSheet / SharePage
  → FlowRepository.saveUrl()
    → normalizeUrl() 归一化并查 url_key
    → 新建 Bookmark（UUID、url_key、search_text、PENDING）
    → BookmarkDao.insert()（同时写 bookmark_tag）
    → notify()
    → 异步 applyMetadata()：HTTP 抓取 → 标题/摘要/图标 → 快照文件 → update + notify
```

重复 URL 返回已有记录（`created=false`）；回收站中的同 URL 会被恢复并 `rev+1`。

### 4.2 详情与阅读

`DetailContent` 按 `bookmarkId` 从 Repository 读取；首次打开 `UNREAD → READING`，停留 30 秒或手动
「标记已读」后进入 `READ`，也可「标记未读」。正文快照按 `snapshotStatus` 懒加载并分段渲染。
编辑保存走 `FlowRepository.saveEdits()`：`title/note/excerpt/tags` 在同一个 DAO 事务内写入，只 `rev+1`、
只 `notify()` 一次。

### 4.3 同步

`SyncPage` 保存配置后调用 `SyncEngine.sync()`。引擎以本地 RDB 为事实源，与远端
`FlowPage/v1/items/*.json`、`FlowPage/v1/tombstones/*.json` 对账；详细算法见
[04-sync-and-services.md](./04-sync-and-services.md)。

### 4.4 服务卡片

`FlowRepository.notify()` → 串行写 `flowpage_card` preferences 快照 → `CardPublisher.publish()` 遍历
已发布卡片调 `formProvider.updateForm()`。卡片进程读 preferences 前必须清缓存，详见
[04-sync-and-services.md](./04-sync-and-services.md#6-服务卡片)。

## 5. 依赖关系

所有系统能力均来自 `@kit.*`，无第三方运行时依赖：

- `@kit.AbilityKit`、`@kit.ArkUI`、`@kit.ArkData`（RDB/preferences）、`@kit.NetworkKit`（HTTP）
- `@kit.CoreFileKit`（文件/选择器）、`@kit.ShareKit`、`@kit.FormKit`
- `@kit.UniversalKeystoreKit` + `@kit.CryptoArchitectureKit`（HUKS AES-256-GCM 与随机 nonce）
- `@kit.PerformanceAnalysisKit`（hilog）、`@kit.ArkTS`（URL、编解码、UUID）

## 6. 设计约束

- **本地优先**：网络失败不得影响本地读写；同步失败只报告，不回滚本地。
- **RDB 是唯一事实源**：preferences 只存配置、卡片快照和同步游标；远端不是运行时数据源。
- **正文快照不参与同步**：仅 `filesDir/snapshots/<id>.txt`，远端记录没有快照字段。
- **删除靠墓碑**：彻底删除、30 天过期清理都会先写 `tombstone`；否则对端会把旧记录重新上传回来。
- **LWW 但保留冲突**：远端更新覆盖本地 dirty 版本时，把双方 JSON 写入 `conflict` 表；同步页提供冲突
  计数、列表、查看双方 JSON 与「恢复本地 / 采用远端」。
- **无迁移框架**：没有 `DB_VERSION` 或事务迁移，新增列必须走 `ALTER TABLE` + `CREATE TABLE IF NOT EXISTS`
  双写模式，见 [03-data-layer.md](./03-data-layer.md#4-初始化与迁移)。
