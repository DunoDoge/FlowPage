# Implementation Plan: 阅读页性能第三轮优化（reader-perf-round3）

**Input**: Feature specification from `spec/reader-perf-round3/spec.md`

## Summary

在 6f460b0 基线上对阅读页做第三轮性能优化：先用临时探针建立 leaf500（1,999 块）基线，再依数据逐项落地——首屏布局（更小首窗为主、骨架为辅）、切换拆解（先吃窗口缩小红利，不足再上双槽延迟销毁）、搜索/applyMetadata 迁移 taskpool、（延伸）阅读栈内存裁剪。核心技术判断已验证：LazyForEach 在 Scroll+Column 中不生效（官方文档明确仅 List/ListItemGroup/Grid/Swiper/WaterFlow 懒加载），故首屏路线以调窗为主而非渲染框架迁移。

## Technical Context

**Language/Version**: ArkTS 严格子集（禁 any / as 断言 / 结构化类型 / 动态属性访问），API 26，Stage 模型  
**Primary Dependencies**: 无第三方运行时依赖；`@kit.ArkTS`(taskpool)、`@kit.ArkUI`、`@kit.ArkWeb`、`@kit.PerformanceAnalysisKit`(hilog, 临时探针)  
**State Management**: 沿用现状 State Management V2（`@ComponentV2` + `@Local`/`@Param`/`@Event`/`@Monitor`），不引入 V1，不迁移  
**Storage**: 不改 RDB schema、不改 preferences 键、不改快照格式（`FLOWPAGE-ARTICLE-2` 复用为内存紧凑形态）  
**Testing**: `@ohos/hypium` 设备端（entry/src/ohosTest，11 套件 / 119 用例起点）；构建门禁 `hvigorw assembleHap` + `codelinter -c code-linter.json5`  
**Target Platform**: HarmonyOS phone，真机 HUAWEI Pura 70（ADY-AL00，序列号 2YB0224508009888）  
**Project Type**: 既有单 HAP（entry）增量优化，不新建模块  
**Performance Goals**: leaf100 单次下钻布局中位数 ≤300 ms（基线 356–515 ms）；上一页拆解 ≤150 ms（基线 265–277 ms）；搜索/applyMetadata 期间主线程心跳无长阻塞；20 层 VmRSS 不高于 296 MB 基线（延伸项目标为下降）  
**Constraints**: 不 commit/push；不新增权限；不改 main_pages.json；临时探针测完删净；`devecocli build` 不可用（modelVersion 26.0.0），用 SDK 自带 hvigor：`/storage/Users/currentUser/command-line-tools/hvigor/bin/hvigorw --no-daemon assembleHap`  
**Scale/Scope**: 改动面集中在 ReaderView.ets(1,384 行)、ReadingShell.ets(958 行)、3 个新搜索文件、FlowRepository.ets 一处调用、测试与文档

## Project Structure

### Documentation (this feature)

```text
/storage/Users/currentUser/Documents/Coding/FlowPage/spec/reader-perf-round3/
├── spec.md              # Phase 1 产出
├── plan.md              # 本文件
└── tasks.md             # Phase 3 产出
```

### Source Code (repository root)

```text
/storage/Users/currentUser/Documents/Coding/FlowPage/
├── entry/src/main/ets/
│   ├── components/
│   │   ├── ReaderView.ets            # S2: 首窗参数/骨架; S4: 搜索异步化接线; S1: 探针挂点
│   │   └── ReadingShell.ets          # S3: 双槽延迟销毁(条件触发); S5: 栈裁剪; S1: 探针挂点
│   ├── core/parser/
│   │   ├── ReaderSearchCore.ets      # 新增(S4): 纯函数搜索核心(同步回退与 worker 共用)
│   │   └── ReaderSearchTask.ets      # 新增(S4): @Concurrent 任务入口
│   ├── core/service/
│   │   └── ReaderSearchService.ets   # 新增(S4): 索引构建 + taskpool 调度 + 超时回退
│   ├── repository/
│   │   └── FlowRepository.ets        # S4b: applyMetadata 抽取切 off-thread(L329 附近)
│   └── (其余不动: model/, core/db/, core/service/Article*.ets 等)
├── entry/src/ohosTest/ets/test/
│   └── ReaderSearch.test.ets         # 新增(S4): 搜索核心/索引/回退用例(或并入 Reader.test.ets，实现时定)
├── docs/records/05-browser-link-reading.md   # §6 追加本轮全部 Before/After
├── docs/wiki/02-ui-layer.md, docs/wiki/03-data-layer.md, AGENTS.md
└── docs/quality/01-walkthrough-checklist.md  # 新增走查项
```

**Structure Decision**: 遵循既有项目架构（UI 组件在 components/、纯函数与并发入口在 core/parser/、调度服务在 core/service/、仓库门面在 repository/），不引入 MVVM 目录、不新建模块/分层。新增 3 个搜索文件与既有 `ArticleExtract{Task,Service}` 三件套结构完全对称（Core 纯函数 / Task @Concurrent / Service 超时调度），文件数已是该模式的最小集。

## Complexity Tracking

无 Constitution Check 违规需要辩护；不填。

## Research & Decisions

### D1 · S2 首屏路线：调窗为主，放弃 LazyForEach 迁移（本轮）

- **Decision**: 首屏布局优化采用「数据驱动的更小 INITIAL_BLOCKS（+必要时首批分帧挂载）+ 可选骨架占位」；不迁移 LazyForEach/Repeat/List。
- **Rationale**: 官方文档（ArkUI 开发指南《LazyForEach：数据懒加载》使用限制节）明确：**仅 List、ListItemGroup、Grid、Swiper、WaterFlow 支持数据懒加载，其他组件一次性加载全部数据**。当前 ReaderView 为 `Scroll → SelectionContainer → Column → ForEach(shownBlocks())`，在其中换 LazyForEach 无收益；要生效必须迁移为 List，而 List 迁移会破坏：① SelectionContainer 跨块整栏选择；② blockOffsets/blockHeights 像素测量模型（目录/搜索/位置恢复/进度估算全部依赖）；③ ArticleHeaderItem/LoadMoreItem/ArticleFooterItem 同轴混排；④ LazyForEach 会销毁滑出可视区的节点，与现有"窗口内全保留"的测量/恢复模型冲突。与 spec FR-003"不破坏既有六项行为"的硬约束直接冲突，风险收益不成比例。
- **Alternatives considered**: ① List+LazyForEach/Repeat 迁移（如上否决，记录为长期选项）；② 仅加骨架不改窗口（骨架改善感知但不改变 layoutDone 口径，不达目标）；③ 首批分帧挂载（首屏先挂小子集、后续帧补齐窗口——作为调窗后仍不达标时的叠加手段）。
- **关键联动（必须处理）**: 位置恢复依赖「扩窗 + 10×200ms 重试」，每次扩窗 +BLOCK_BATCH。INITIAL_BLOCKS 下调会压缩重试预算（例：INITIAL=100 时 100+9×200=1900 < 1,999，恢复到第 1900+ 块会耗尽重试）。调窗任务必须同步校准（加大重试上限 / 扩窗步进随目标距离增长），并用「恢复到 leaf500 尾部块」用例验证。

### D2 · S3 拆解路线：先吃窗口红利，不足再上双槽延迟销毁

- **Decision**: 分两步。第一步：S2 落地更小首窗后直接复测拆解（拆解成本 ∝ 旧页已挂载块数，当前心跳观测的 265–277 ms 对应 200 块销毁）。第二步（仅当仍 >150 ms）：ReadingShell.ReaderPane 改为**双 ReaderView 交替槽位**——push 时新条目绑到空闲槽，旧槽 `visibility(None)` 保留，空闲期（如 setTimeout ≥500 ms 且无新 push）再销毁；pop 时反向复用。落地后必须复测 pop/back 行为与 20 层 VmRSS（瞬时双页挂载的内存代价）。
- **Rationale**: 拆解是旧子树同步销毁，发生在同一次 diff 中；把销毁挪出关键帧是唯一直接手段。双槽方案不触碰 ReaderView 内部逻辑，行为面最小。
- **Alternatives considered**: ① push 前先把旧页 visibleCount 缩回 INITIAL 再换绑（两次 diff 总销毁量不变，仅分帧，收益边际且复杂）；② 永久保留已访问层组件（内存爆炸，与 S5 目标相反）。

### D3 · S4 搜索异步化：复刻 ArticleExtract 三件套模式

- **Decision**: 新增 `ReaderSearchCore.ets`（纯函数，worker 与同步回退共用）、`ReaderSearchTask.ets`（@Concurrent，只收 `haystack: string, starts: number[], needle: string`，返回逗号分隔的命中块下标串）、`ReaderSearchService.ets`（buildIndex + taskpool 调度 + 2 s 超时 + 同步回退）。ReaderView 接线：首次搜索时惰性构建索引并按 `ArticleSignature` 缓存；120 ms 防抖保留；加世代 token 丢弃过期结果；closeSearch/换文时释放索引（小写全文副本约为正文 2× 字符内存）。
- **Rationale**: 与已验证的 ArticleExtractService 模式完全对称（@Concurrent + 超时 cancel + 同步回退保证功能不丢）；字符串/number[] 均可序列化跨线程，ArticleBlock 不是 Sendable、不得传入 taskpool。
- **契约细节（实现必须遵守）**: 命中集合与现状同步循环**完全一致**——大小写不敏感、按块 containment（`block.text.toLowerCase().indexOf(needle) >= 0`）；拼接 haystack 时的分隔符不得让跨块匹配命中（needle 含分隔符或匹配区间跨块边界一律不算命中）。
- **Alternatives considered**: ① 索引构建也放 worker（传 codec 串、worker 拆行建索引）——仅当实测 UI 线程构建索引心跳 >50 ms（leaf500 312 KB）才升级，先按 UI 线程一次性构建（每会话一次，~10–40 ms 量级）设计并在任务中测量；② 全文正则/后缀数组等复杂索引（过度设计）。
- **注意**: 工作区遗留同名三件套半成品已按用户决定删除；本轮全新实现，不得从 git 历史复活旧文件。

### D4 · S4b applyMetadata 抽取 off-thread

- **Decision**: `FlowRepository.applyMetadata()` 内 `MetadataService.fetch(bookmark.url, autoSnapshot)` 改为显式传 `offThread=true`（fetch 已具备该参数与 ArticleExtractService 分支，ReaderPageLoader 已在用）；`retryCurrent()`/`saveCurrent()` 等调用方行为不变。用 leaf500 量级书签触发「重新抓取」，心跳验证主线程无长阻塞。
- **Rationale**: 一行改动即把最后一个同步抽取热点切到既有 worker 链路；超时/失败回退语义已内建。
- **Alternatives considered**: 无（既有能力补接线）。

### D5 · S5 栈内存裁剪（延伸，双机制）

- **Decision**: 机制 A（必做，低风险）：`ReadingShell.back()` 出栈后把 `entries` 尾部裁掉（`slice(0, index+1)`）——被弹出的层不存在"前进"再入路径，对象图立即可回收。机制 B（测量门控）：push 使某层变为非当前层后，把其 `article` 对象图替换为 `ArticleCodec.encode()` 字符串（紧凑形态），pop 回该层时 `decode` 重建；encode 延迟到空闲（push 完成 + idle 定时）执行，避免给 push 关键路径加耗时；decode 在 UI 线程同步执行并计入心跳（若 decode 心跳 >100 ms 则机制 B 降级为仅保留 A 并如实记录）。
- **Rationale**: 20 层全活栈的 296 MB 中每层 ArticleDocument 对象图（块对象 + 链接对象 + 字符串）是可释放大头；codec 字符串是现成的紧凑表示，无需新格式。
- **Alternatives considered**: ① 自定义"只留文本/链接"新紧凑类（新增格式与编解码，收益不明前不值得）；② 直接丢弃非当前层、pop 回时重抓（网络代价与不可离线，否决）。
- **验收口径**: 20 层下钻 VmRSS/VmHWM Before/After；pop 逐层返回内容完整性走查。

### D6 · 测量协议（所有 Before/After 统一口径）

- **Decision**: 临时探针（hilog，domain 0x0000，TAG 'flowpage'，消息加 `PERF:` 前缀）：点击时刻（pushReaderLink 入口）、抓取返回（ReaderPageLoader fetch resolve）、抽取完成（ArticleExtractService 回到主线程）、换绑时刻（ReaderView onArticleChanged）、layoutDone（measuredBlocks===visibleCount 首次达成）、拆解段（20 ms `setInterval` 心跳记录最大间隔，上一轮口径）。VmRSS 用 `/proc/<pid>/status`；节点数用 `uitest dumpLayout`。网络受 hdc rport 抖动（0.4–3.3 s），**必须**拆分网络/抽取/布局分列报告，不得只报总时长。每次改动单独构建→安装→测量；探针在最终验收门禁前全部删除（git status 仅剩正式改动）。
- **Rationale**: 与 docs/records/05 §6 既有数据同口径，Before/After 才可比。
- **环境**: perfweb 目录 `/storage/Users/currentUser/.tmp/deveco/perfweb`（leaf100/1..21、leaf500/1..21），host 起 `node serve4.js`(18084)，`hdc -t 2YB0224508009888 rport tcp:18085 tcp:18084`；书签「性能页 1」= `http://127.0.0.1:18085/leaf100/1.html`，丢失时 `aa start -U` 深链重建；UI 驱动 `click 400 1150 → click 1000 975 → click 300 890`（CJK 链接点字形左侧）；测完收走转发（不 hdc kill）。

## Data Model

### ReaderSearchIndex（新，S4）

- `haystack: string` — 全部块文本小写后按块拼接、块间以不出现在正文的分隔符（换行）相连；跨分隔符命中不算。
- `starts: number[]` — 每块在 haystack 中的起始下标（含分隔符占位规则，实现与纯函数约定一致）。
- 生命周期：首次搜索惰性构建 → 按 `ArticleSignature` 缓存于 ReaderView → article/bookmarkId 变化或 closeSearch 时丢弃。

### ReadingEntry 形态机（S5，既有类的用法扩展，不加字段也可用编码串字段替换实现）

- `LIVE`：持有 `ArticleDocument` 对象图（当前层或未裁剪层）。
- `COMPACT`：仅持有 `ArticleCodec.encode()` 字符串（FLOWPAGE-ARTICLE-2，内存紧凑形态；不入库、不同步）。
- `DROPPED`：出栈时从 `entries` 尾部移除，等待 GC。
- 转移：push 使 LIVE→COMPACT（idle 后）；pop 回使 COMPACT→LIVE（decode）；pop 离开使尾部→DROPPED。

### 性能样本（记录约定，文档层实体）

每条样本：场景（leaf100/leaf500 × 下钻次数）、click→layoutDone、分列（拆解/网络/抽取/布局）、VmRSS/VmHWM、dumpLayout 节点数、心跳最大间隔、采样说明。Before/After 同格式。

## Contracts & Interfaces

### 新增（S4）

```text
ReaderSearchCore.searchBlocks(haystack: string, starts: number[], needle: string): string
  —— 纯函数；空输入返回 ''；返回逗号分隔命中块下标；命中集合与现状同步循环等价（大小写不敏感、块内 containment、不跨块）
ReaderSearchTask.searchReaderTask(haystack: string, starts: number[], needle: string): string
  —— @Concurrent；参数全部可序列化；不得引用 ArticleDocument/ArticleBlock
ReaderSearchService.buildIndex(article: ArticleDocument): ReaderSearchIndex
ReaderSearchService.search(index: ReaderSearchIndex, needle: string): Promise<number[]>
  —— taskpool 2 s 超时 → 取消并同步回退 searchBlocks；主线程解码下标串；异常不抛出、返回结果或空集
```

### 修改（S4b / S5）

```text
FlowRepository.applyMetadata(id) 内部：MetadataService.fetch(url, includeSnapshot, offThread=true)
ReadingShell.back()：出栈后裁掉 entries 尾部（无前进路径）
ReadingShell（S5-B 门控启用时）：compactBelow/expand 与 idle encode 的内部方法，不对外暴露
```

### 保留不变的行为契约（回归基线）

目录跳转（含窗口外分批推进）、进度（未全量按块估算/全量按像素）、位置恢复（10×200 ms 重试 + 校准后的预算）、搜索命中高亮与上下处导航、正文链接 Span 点击、临时页「收藏这一页」、阅读/网页模式切换、MAX_STACK=20 与第 20 次 toast、系统返回/ESC 逐层回退。

## Changelog

- 2026-10-24 初版：依据 spec/reader-perf-round3/spec.md 与源码/官方文档调研生成。
