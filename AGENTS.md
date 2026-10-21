# AGENTS.md — FlowPage / 流笺

本地优先的 HarmonyOS 链接收笺应用：单 HAP（`entry`），ArkTS + ArkUI 状态管理 V2，RDB 为唯一事实源，WebDAV 增量同步。
完整分层说明见 [docs/wiki/](docs/wiki/README.md)；本文件只记录代理容易踩错的事实。

## 项目快照

| 项 | 值 |
|---|---|
| 包名 / 版本 | `com.dunodoge.flowpage` / 1.0.0（`AppScope/app.json5`） |
| 平台 | HarmonyOS Stage 模型，API 26，phone / tablet / 2in1 |
| 模块 | 仅 `entry`（HAP）；无 HAR、无多端模块、无第三方运行时依赖 |
| 状态 | `@ObservedV2` + `@Trace` + `@ComponentV2` + `@Local` / `@Param` / `@Event` / `@Monitor` |
| 数据 | RDB `flowpage.db`（6 表 + 7 索引）、preferences、`filesDir/snapshots/*.txt` |
| 同步 | WebDAV（Basic Auth），ETag 增量 + LWW；无分布式 KV、无账号体系 |
| 测试 | `@ohos/hypium`，`entry/src/ohosTest` 10 个套件 / 81 个用例，仅设备端 |

## 构建与验证（顺序有讲究）

- **`devecocli build` 对本仓库不可用**：其内置 hvigor 只支持 `modelVersion 6.1.0`，本工程是 `26.0.0`，会报
  `Unsupported modelVersion of Hvigor 26.0.0`（已实测）。改用 SDK 自带 hvigor 7.26.8：

```bash
hvigorw --version                 # 必须 >= 7.26.8
hvigorw assembleHap               # 产物 entry/build/default/outputs/default/entry-default-signed.hap
codelinter -c code-linter.json5   # 当前 0 error / 1 条 startIcon 性能建议
```

- 若 `hvigorw` 不在 PATH，本机位于
  `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/hvigor/bin/hvigorw`。
- 首次克隆或依赖变化后先 `ohpm install`；然后每次改完 `.ets` 先跑会话内的 `check_ets_files`
  （快速 ArkTS 严格模式检查），再跑 `hvigorw assembleHap`；不要用 `devecocli build` 作为验证门禁。
- 纯函数测试入口是 `entry/src/test`（`hvigorw test`），与设备端 `entry/src/ohosTest` 分开；本机 SDK
  未安装 previewer 包时 `hvigorw test` 会停在 `previewer/common/bin ENOENT`，此时只能跑设备端套件。
- 设备端测试（真机/模拟器）：

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000
```

- `build-profile.json5` 含本机签名材料且被 gitignore；新克隆先从 `build-profile.template.json5` 复制生成，
  不要提交。`.hvigor/`、`entry/build/`、`oh_modules/` 均为生成物。
- `main_pages.json` 只有 2 个页面路由：`pages/Index`、`pages/SharePage`。标签/同步/设置是组件，经
  `Index` 内的 `NavPathStack` 或宽屏 pane 切换，不要往 `main_pages.json` 里加路由。桌面卡片是独立的
  `@Entry` 表单页面（`widget/pages/`），不属于页面路由。

## 架构与数据流

```
EntryAbility ─┬─ flowpage://bookmark/{id} / want.bookmarkId ─▶ AppState.openBookmark
              ├─ http(s) URL ─▶ AppState.openInbox
              └─ ShareAbility ─▶ pages/SharePage
Index (breakpoint 700/1000vp) ─▶ StreamHome / DetailContent / TagsPage / SyncPage / SettingsPage
                                      │
                                      ▼
                          FlowRepository（单例，UI 只依赖它）
                           ├─ BookmarkDao + Database（RDB）
                           ├─ MetadataService / SnapshotStore
                           ├─ SyncEngine + WebDavTransport
                           └─ CardPublisher / CardSnapshot
```

- **刷新靠 tick**：`AppState.notifyChanged()` 递增 `refreshTick`；Repository 的常规 UI 写方法完成后会自动
  `notify()`（`setLinkStatus` 与同步内部方法除外）。直接调 `BookmarkDao` 不会刷新 UI，也不会推送卡片。
  新写入口必须走 Repository，或在末尾补 `notify()`。
- `AppState.openBookmark()` 写 `routeTick` 触发手机端 push `detail`；`onContinue` 只携带当前 `selectedId`。
- 宽屏三栏仅 `width>=1000vp` 显示 `SideNav`；`700–999vp` 为两栏；手机为 `Navigation` 栈。
- 卡片在独立进程读取 preferences，`CardSnapshot.open()` 必须先
  `removePreferencesFromCacheSync`，否则读到旧快照。`FlowRepository.notify()` 已做“写快照 + 推送”串行合并。
- 所有 URL 先经 `normalizeUrl()`：补 `https://`、小写 host、去 fragment、去跟踪参数、query 排序；`url_key`
  唯一索引负责去重。新增入口不要自己比较原始字符串。
- 正文快照是 `filesDir/snapshots/<id>.txt` 纯文本，**不上传同步**；同步只传链接、元数据、标签和状态。
- 删除语义：软删除 `deleted=1` 保留 30 天；彻底删除/过期清理会写 `tombstone`，同步先传墓碑再删远端文件。
  墓碑是“不复活”的唯一保障，任何清理路径都不能跳过 `addTombstone`。
- 上传竞态：PUT 前记录 `rev + updatedAt`，成功后仅当仍匹配才回填 ETag 并清 `dirty`；不匹配说明同步期间
  又被编辑，必须保持 dirty。
- 数据库没有版本号/事务迁移框架：建表用 `CREATE TABLE IF NOT EXISTS`，加列同时改 `Database.SQL_BOOKMARK`
  并在 `Database.applySchema()` 的 `addColumn()` 列表补一条吞异常的 `ALTER TABLE`（现有 `dirty` /
  `link_status` / `link_checked_at` / `domain` 即此模式）；`SyncStoreTest` 用旧表结构验证迁移幂等。

## 代码约定

- ArkTS 严格子集：禁止 `any`、`as` 断言、结构化类型、动态属性访问；对象字面量必须有显式类型上下文。
  存量 `as` 只剩 5 处平台类型边界（`JSON.parse` ×2、WebDAV 动词/响应头、`BusinessError` 统一收口在
  `common/PlatformError.ets`），新增业务代码不要再用 `as`。
- 主 UI 统一 V2 装饰器；**只有** `entry/src/main/ets/widget/pages/` 的桌面卡片使用 V1
  `@Component` + `@LocalStorageProp`（FormKit 约束），不要混用。
- 颜色一律 `$r('app.color.*')`（`resources/base|dark/element/color.json` 成对维护）。当前没有 i18n 层，
  页面文案是内联中文，只有应用名/Ability 标签在 `string.json`。
- 日志 `hilog`，domain `0x0000`，TAG `'flowpage'`。
- 注释只写代码表达不出的约束，英文，与该文件现有风格一致。
- 提交遵循现有 Conventional Commits（`fix(sync): ...`、`docs: ...`）；**未经明确要求不要 commit/push**。
- 现有文档 `docs/records/01-implementation-log.md` 含历史批次记录，可能落后于代码（例如“28 个用例”、已删除的
  `BrowserPage`/Permissions）。以源码和本文件为准。

## 文档地图

- `docs/wiki/`：分层 Code Wiki（架构 / UI / 数据 / 同步与服务 / 构建运行）。
- `docs/product/`、`docs/design/`、`docs/engineering/`：产品需求、UI 规范、技术方案与实施计划。
- `docs/quality/`：走查清单与走查问题修复记录。
- `docs/records/`：实现记录与两轮复审结论及修复批次；文档里的勾选只是声明，落地与否必须回代码与测试验证。
- `docs/README.md`：设计文档索引；根 `README.md` 面向使用者。
