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
| 数据 | RDB `flowpage.db`（7 表 + 9 索引）、preferences、`filesDir/snapshots/*.txt` |
| 同步 | WebDAV（Basic Auth），ETag 增量 + LWW；书签/文件夹/墓碑三类实体；无分布式 KV、无账号体系 |
| 测试 | `@ohos/hypium`，`entry/src/ohosTest` 15 个套件 / 185 个用例，仅设备端 |

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
                           ├─ BookmarkDao + FolderDao + Database（RDB）
                           ├─ MetadataService / SnapshotStore / ReaderPageLoader
                           ├─ SyncEngine + WebDavTransport（书签 + 文件夹 + 墓碑）
                           └─ CardPublisher / CardSnapshot
```

- **刷新靠 tick**：`AppState.notifyChanged()` 递增 `refreshTick`；Repository 的常规 UI 写方法完成后会自动
  `notify()`（`setLinkStatus` 与同步内部方法除外）。直接调 `BookmarkDao` 不会刷新 UI，也不会推送卡片。
  新写入口必须走 Repository，或在末尾补 `notify()`。
- `AppState.openBookmark()` 写 `routeTick` 触发手机端 push `detail`；`onContinue` 只携带当前 `selectedId`。
- 宽屏三栏仅 `width>=1000vp` 显示 `SideNav`（文件为 `components/NavigationRail.ets`）；`700–999vp` 为两栏；手机为 `Navigation` 栈。
- 卡片在独立进程读取 preferences，`CardSnapshot.open()` 必须先
  `removePreferencesFromCacheSync`，否则读到旧快照。`FlowRepository.notify()` 已做“写快照 + 推送”串行合并。
- 所有 URL 先经 `normalizeUrl()`：补 `https://`、小写 host、去 fragment、去跟踪参数、query 排序；`url_key`
  唯一索引负责去重。新增入口不要自己比较原始字符串。
- 正文快照是 `filesDir/snapshots/<id>.txt` 的结构化文本（`FLOWPAGE-ARTICLE-2` 版本头，每块第三字段是
  `start,end,encodeURIComponent(url)` 链接区间），**不上传同步**；同步只传链接、元数据、标签和状态。
  `FLOWPAGE-ARTICLE-1` 仍可读但无链接；旧文章需“重新抓取”。根书签阅读位置存本机 `flowpage_reader`，不参与同步。
- 阅读/浏览器统一走 `Index` 根部的 `bindContentCover` + `ReadingShell`，不要往 `main_pages.json` 加路由；
  临时链接页不写 RDB/快照/`flowpage_reader`，只保留在 `ReadingEntry` 内存栈中。正文链接点击 → 原生抓取
  （`ReaderPageLoader`）→ 临时阅读页；非文档链接 → 内置 `Web`。浏览器「阅读」用
  `runJavaScriptExt('document.body.innerHTML')` 提取实时 DOM，同样复用 `ArticleExtractor`。
- 删除语义：软删除 `deleted=1` 保留 30 天；彻底删除/过期清理会写 `tombstone`，同步先传墓碑再删远端文件。
  墓碑是“不复活”的唯一保障，任何清理路径都不能跳过 `addTombstone`。
- 上传竞态：PUT 前记录 `rev + updatedAt`，成功后仅当仍匹配才回填 ETag 并清 `dirty`；不匹配说明同步期间
  又被编辑，必须保持 dirty。
- 数据库没有版本号/事务迁移框架：建表用 `CREATE TABLE IF NOT EXISTS`，加列同时改 `Database.SQL_BOOKMARK`
  并在 `Database.applySchema()` 的 `addColumn()` 列表补一条吞异常的 `ALTER TABLE`（现有 `dirty` /
  `link_status` / `link_checked_at` / `domain` 即此模式）；`SyncStoreTest` 用旧表结构验证迁移幂等。

## 性能约束（阅读页）

- **禁止在 UI 线程循环调用 `ArticleExtractor.extract()` 或 `ReaderSearchCore.searchBlocks()`**。阅读页链路
  （`ReaderPageLoader.load()`、`ReadingShell.extractFromWeb()`、`FlowRepository.applyMetadata()`）必须走
  `ArticleExtractService.extractAsync()`（taskpool，4 s 超时 + 同步回退）；阅读页搜索必须走
  `ReaderSearchService.search()`（taskpool，2 s 超时 + 同步回退，索引构建 ≤10 ms 留 UI 线程一次性）。
  `ArticleDocument` 不是 Sendable，跨线程只传 HTML 与 `ArticleCodec` 字符串/`number[]`。
- 热点正则必须模块级复用（`ArticleExtractor`、`MetadataService` 均如此），不要在函数内 `new RegExp`
  或堆重复 `replace` 链；改动抽取器后要复测耗时。
- transient 页性能预算（Pura 70 / 648 块 / 101,620 字符）：首屏布局 ≤ 600 ms，单次「点击链接→新页可读」
  ≤ 1.7 s。模拟器口径（2026-10-25 第三轮）：layout 中位 259 ms、click→layoutDone 672 ms、
  leaf500(1,999 块) layout 272 ms / 总 1,048 ms。`ReaderView` 首屏 `INITIAL_BLOCKS=200`、每次
  `BLOCK_BATCH=200`，**不要**一次挂载整篇（实测 648 块一次挂载约 3 s、VmRSS 553 MB）；改窗口/恢复/搜索
  逻辑后要复测 `uitest dumpLayout` 节点数、`VmRSS` 与 1/5/10/20 次下钻。
- **下钻整帧间隔由新页 200 块构建主导**（第三轮对照实验：初次打开 ≈ 下钻 layout），旧页销毁边际成本
  ≈0–20 ms——不要再把该帧归因给「拆解」，也不要为拆解引入双槽延迟销毁（收益/风险倒挂，已评估否决）。
- 改 `ReaderView` 必须保留：目录、进度、位置恢复（含窗口外块）、搜索命中、链接点击、临时页「收藏这一页」。
  **已知边角（未修）**：位置恢复到窗口外块在超大页上时序敏感（10×200 ms 重试内测量未完成即耗尽则回落顶部
  且进度条残留目标值，第三轮 4 试 1 失）；改恢复逻辑时优先验证 leaf500 尾部恢复。
- **阅读栈内存形态机**：`ReadingShell.back()` 出栈即裁 `entries` 尾部（被弹层无前进路径）；push 后 600 ms
  空闲把非当前层 article 压为 `ArticleCodec.encode()` 串（`entry.compact`），pop 回时 decode（12–15 ms/648 块，
  ≪100 ms 门限）。改栈逻辑必须保持这两条不变量，并复测 20 层 VmRSS。
- 判断主线程阻塞用 20 ms `setInterval` 心跳并记录最大间隔；只看 hilog 阶段时间戳会把「上一页拆解/GC」
  误判成网络耗时。模拟器测量注意：连续 `dumpLayout`+`hdc file recv` 会触发病毒扫描风暴污染心跳
  （出现过 6.7–8.1 s 假阻塞），心跳采样必须在无并发 hdc 操作的静默窗口；`uitest keyEvent`（ESC）在长会话
  后可能被系统焦点吞掉，UI 驱动 pop 用界面「返回」按钮。
- 本节性能数字是当前权威口径（易变数字唯一维护点）；复测方法与各轮原始数据见
  `docs/records/05-browser-link-reading.md` 与 `openspec/changes/archive/reader-perf-round3/`。

## 代码约定

- ArkTS 严格子集：禁止 `any`、`as` 断言、结构化类型、动态属性访问；对象字面量必须有显式类型上下文。
  存量 `as` 只剩 5 处平台类型边界（`JSON.parse` ×2、WebDAV 动词/响应头、`BusinessError` 统一收口在
  `common/PlatformError.ets`），新增业务代码不要再用 `as`。
- 主 UI 统一 V2 装饰器；**只有** `entry/src/main/ets/widget/pages/` 的桌面卡片使用 V1
  `@Component` + `@LocalStorageProp`（FormKit 约束），不要混用。
- 文件夹管理属主页：`FolderPanel` 挂在最左页面栏——≥1000vp 停靠在 `SideNav` 内（导航项下方，栏宽 280vp），
  <1000vp 由主页左上角按钮打开左侧抽屉（遮罩，点外部/返回关闭）。抽屉顶部复用 `NAV_ITEMS` 渲染主导航
  （含流笺），主页头部不放 标签/同步/设置，只剩 ☰（窄屏）与「批量」。树的展开集合、滚动位置与抽屉开合在
  `AppState`；跨列多选与拖拽会话也走 `AppState` / `FolderDragSession`，投放由侧栏直接提交。点树行把流过滤到
  该文件夹的**直属书签**（`BookmarkQuery.folderId` 等值，子文件夹内容经其行下钻；树行计数仍含全部子孙）。
  长按拖拽只改归属（`bookmark.folder_id` / `folder.parent_id`），**不写** `position` / `createdAt`；
  批量与拖拽共用 `FlowRepository.batchMove/batchMoveOut/batchDelete`，单次 `notify()`。行操作入口是行尾
  「…」锚定面板（桌面右键同入口），不要再加长按菜单或 context menu；无拖拽路径经 `FolderPicker`。
- 动态文案不要只放在带参 `@Builder` 里：实测 `ReadingShell` 的「网页/阅读」标签在模式切换后会残留旧值，
  改为直接内联 `Text` 或提升到 `@Local` 状态；其余带参 builder 的静态文案不受影响。
- 内置 Web 复用 `INTERNET` 权限，不要新增权限；`target=_blank`/`window.open` 用
  `javaScriptOnDocumentStart` 中和，ArkTS 不能给 `ControllerHandler.setWebController` 传 `null`。
  离开浏览模式后 Web 会卸载，调用 `WebviewController` 前必须检查 `webMounted`。
- 颜色一律 `$r('app.color.*')`（`resources/base|dark/element/color.json` 成对维护）。当前没有 i18n 层，
  页面文案是内联中文，只有应用名/Ability 标签在 `string.json`。
- 日志 `hilog`，domain `0x0000`，TAG `'flowpage'`。
- 注释只写代码表达不出的约束，英文，与该文件现有风格一致。
- 提交遵循现有 Conventional Commits（`fix(sync): ...`、`docs: ...`）；**未经明确要求不要 commit/push**。

## 待决事项

1. 是否提供第二台鸿蒙设备，用于碰一碰、分布式与更多跨端验收。
2. 是否配置 App Linking 域名并完成 `/.well-known/applinking.json` 校验。
3. 内置浏览器是否扩展为多标签/无痕（当前单标签、可编辑地址、阅读模式切换）。
4. 服务卡片与键盘完整路径的人工验收由谁在何时完成。

## 文档地图

- 文档索引：[docs/README.md](docs/README.md)；分层架构详解：[docs/wiki/](docs/wiki/README.md)。
- 方向性决策（为什么这样做）：[docs/adr/](docs/adr/README.md)，append-only，推翻走 Superseded 链。
- 进行中与已完成变更：`openspec/changes/`；能力规格（系统持久行为契约）见 `openspec/specs/`；规划新变更先看 `openspec/config.yaml` 内的项目约束。
- `docs/quality/`、`docs/records/` 是只追加的历史快照；文档里的勾选只是声明，落地与否必须回代码与测试
  验证。现有 `docs/records/01-implementation-log.md` 含历史批次记录，可能落后于代码（例如“28 个用例”、
  已删除的 `BrowserPage`/Permissions），以源码和本文件为准。
