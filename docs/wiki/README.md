# FlowPage Code Wiki

流笺 FlowPage 是运行在 HarmonyOS 上的本地优先链接收笺应用。单模块 `entry`（HAP）承载全部代码：
ArkTS + ArkUI 声明式 UI，状态管理 V2；本地 RDB 是唯一事实源，WebDAV 只做设备之间的增量同步；
正文快照保存在应用沙箱的普通文本文件中，不参与同步。

本 Wiki 面向需要理解、维护或扩展仓库的开发者，按分层拆解职责、数据流与关键约束。
产品与设计背景见 [../README.md](../README.md) 与 `docs/01`–`docs/07`。

> 说明：本文以**当前仓库代码**为准。`docs/05-实现记录.md` 是历史批次记录，个别描述已过时
>（如 28 个用例、已不存在的 `BrowserPage`），以源码与 [AGENTS.md](../../AGENTS.md) 为准。

## 文档导航

| 文档 | 内容 |
|---|---|
| [01-architecture.md](./01-architecture.md) | 分层、Ability 入口、状态与刷新机制、关键数据流、设计约束 |
| [02-ui-layer.md](./02-ui-layer.md) | `Index` 三断点布局、首页/详情/收笺/标签/同步/设置、服务卡片与主题 |
| [03-data-layer.md](./03-data-layer.md) | 模型、RDB 六表、DAO、`FlowRepository`、URL 归一化、导入导出 |
| [04-sync-and-services.md](./04-sync-and-services.md) | WebDAV 协议、同步规划与合并、墓碑、凭据加密、元数据与卡片服务 |
| [05-build-and-run.md](./05-build-and-run.md) | 构建工具链、签名、安装运行、设备端测试、静态检查与排错 |

## 项目速览

| 项 | 值 |
|---|---|
| 包名 / 版本 | `com.dunodoge.flowpage` / 1.0.0（[app.json5](../../AppScope/app.json5)） |
| 形态 | Stage 模型，API 26，单 HAP `entry` |
| 设备 | phone、tablet、2in1 |
| UI | ArkTS + ArkUI，`@ComponentV2` / `@ObservedV2`；只有卡片用 V1 |
| 数据 | RDB `flowpage.db`：bookmark / tag / bookmark_tag / conflict / sync_state / tombstone |
| 同步 | WebDAV Basic Auth，`FlowPage/v1/` 布局，ETag + LWW + 墓碑 |
| 测试 | Hypium 设备端 4 套件 / 30 用例 |

## 功能与实现入口

| 能力 | 入口 / 实现 |
|---|---|
| 首页流、筛选、搜索 | [StreamHome.ets](../../entry/src/main/ets/components/StreamHome.ets) + [BookmarkRow.ets](../../entry/src/main/ets/components/BookmarkRow.ets) |
| 详情阅读 / 编辑 / 操作 | [DetailContent.ets](../../entry/src/main/ets/components/DetailContent.ets) |
| 手动收笺与粘贴 | [InboxSheet.ets](../../entry/src/main/ets/components/InboxSheet.ets) |
| 系统分享收笺 | [ShareAbility.ets](../../entry/src/main/ets/shareability/ShareAbility.ets) → [SharePage.ets](../../entry/src/main/ets/pages/SharePage.ets) |
| 标签管理 | [TagsPage.ets](../../entry/src/main/ets/pages/TagsPage.ets) |
| WebDAV 配置与同步 | [SyncPage.ets](../../entry/src/main/ets/pages/SyncPage.ets) + [SyncEngine.ets](../../entry/src/main/ets/core/sync/SyncEngine.ets) |
| 导入 / 导出 / 主题 | [SettingsPage.ets](../../entry/src/main/ets/pages/SettingsPage.ets) |
| 今日 / 最近服务卡片 | [TodayCard.ets](../../entry/src/main/ets/widget/pages/TodayCard.ets)、[RecentCard.ets](../../entry/src/main/ets/widget/pages/RecentCard.ets) |
| 深链与应用接续 | [EntryAbility.ets](../../entry/src/main/ets/entryability/EntryAbility.ets) |
| 统一数据入口 | [FlowRepository.ets](../../entry/src/main/ets/repository/FlowRepository.ets) |

## 源码目录

```
entry/src/main/ets/
├── entryability/     EntryAbility：want 解析、接续、初始化
├── shareability/     ShareExtensionAbility
├── formability/      FormExtensionAbility（服务卡片）
├── pages/            Index、SharePage（仅有的两个页面路由）；其余页面是组件
├── components/       StreamHome、DetailContent、InboxSheet、BookmarkRow、SideNav
├── common/           AppState、Constants、UrlUtil、DateUtil
├── model/            Bookmark、Tag、Tombstone、导入与元数据结果
├── repository/       FlowRepository（单例）
├── core/db/          Database、BookmarkDao
├── core/service/     MetadataService、SnapshotStore、CardSnapshot、CardPublisher
├── core/sync/        SyncEngine、SyncPlanner、SyncRecord、WebDavTransport、WebDavXml、SyncConfigStore
├── core/parser/      BookmarkHtmlParser
├── core/security/    CredentialCipher（HUKS）
└── widget/pages/     桌面卡片（V1 装饰器）
```

## 快速开始

```bash
cp build-profile.template.json5 build-profile.json5   # 首次克隆，配置签名后再构建
hvigorw assembleHap
```

详见 [05-build-and-run.md](./05-build-and-run.md)。
