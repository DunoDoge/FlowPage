# Feature Specification: 阅读页性能第三轮优化（reader-perf-round3）

**Created**: 2026-10-24  
**Status**: Draft  
**Input**: User description: "继续优化 FlowPage 阅读页性能：leaf500 基线、首屏 ≤300ms、切换拆解 ≤150ms、搜索/元数据抽取移出 UI 线程、（延伸）pop 裁剪非可见层 ArticleDocument。先测量再改，逐项验证。"

## Overview

在已完成的分窗挂载（INITIAL_BLOCKS=200 / BLOCK_BATCH=200）与 taskpool 抽取（上一轮）基础上，对阅读页做第三轮性能优化：先建立 leaf500（312 KB / 1,999 块）超大页基线，再逐项压低首屏布局耗时与页面切换拆解耗时，把搜索与元数据抽取移出 UI 线程，并作为延伸项降低 20 层阅读栈的内存占用。全程遵循"先测量、再修改、逐项验证"，每项改动给出同一复现步骤的 Before/After 数据，未测部分明确说明。

## User Scenarios & Testing *(mandatory)*

### User Story 1 - leaf500 超大页基线与分窗行为确认 (Priority: P1)

在真机（ADY-AL00 / API 26）上用本地性能页 leaf500（312 KB / 1,999 块）建立基线：1/5/10 次下钻的 click→layoutDone 总时长及其拆解（上一页拆解 / 网络 / 抽取 / 布局）、VmRSS、`uitest dumpLayout` 节点数；确认分窗挂载在超大页上的首屏与扩窗行为（首屏是否只挂 200 块、滚底扩窗、目录/搜索/位置恢复到窗口外是否仍工作），数据支持时调整 INITIAL_BLOCKS。

**Why this priority**: 用户要求"先测量，再改"；没有 leaf500 基线，后续每一项优化的 Before/After 都不成立，且 INITIAL_BLOCKS 是否需要调整由这份数据决定。

**Independent Test**: 在未做任何代码改动的前提下，用 leaf500/1.html 起始按固定手势下钻 1/5/10 次，用 20 ms 心跳记录最大间隔并拆分阶段耗时；可与既有 leaf100 数据（0.36–0.52 s 布局 / 265–277 ms 拆解 / 296 MB / 1,440 节点）对照成表。

**Acceptance Scenarios**:

1. **Given** 工作区 clean 于 6f460b0、perfweb serve4.js 已启动且端口转发生效，**When** 从书签「性能页 1」或深链进入 leaf500 并下钻 1/5/10 次，**Then** 产出每次的 click→layoutDone、拆解/网络/抽取/布局拆分、VmRSS、dumpLayout 节点数，写入 docs/records/05-browser-link-reading.md §6。
2. **Given** leaf500 首屏 1,999 块仅挂载 200 块，**When** 滚动到已渲染底部、点目录/搜索命中/恢复到窗口外位置，**Then** 扩窗、pendingJumpIndex 分批推进与 10×200 ms 重试均正常；若位置恢复重试上限不足（目标块接近 1,999），记录为数据并据此决定是否调整参数。
3. **Given** 基线数据采集完成，**When** 数据显示当前 INITIAL_BLOCKS 在超大页有明显劣化，**Then** 仅调整窗口参数并单独复测；否则保持不变并记录结论。

---

### User Story 2 - 首屏布局压至 ≤300 ms (Priority: P1)

在不破坏目录、进度、位置恢复（含窗口外块）、搜索命中、链接点击、临时页「收藏这一页」的前提下，把单次「点击链接→新页可读」中的布局阶段（article 就绪 → 已挂载块 onAreaChange 完成）从当前 356–515 ms 压到 ≤300 ms；评估 LazyForEach 或更小首屏窗口 + 骨架占位两条路线，按测量数据择优落地，并给出 Before/After。

**Why this priority**: 布局是当前 click→layoutDone 链路中占比最大的主线程阻塞段，直接影响连续阅读的跟手性；是本轮两个硬性耗时目标之一。

**Independent Test**: 用 leaf100（648 块）同一手势（第一条 → 专注阅读 → 下一页链接）连续下钻多次，比较布局阶段耗时、首屏内容可见时间（若引入骨架，含骨架出现/替换时机）与既有功能走查（目录/恢复/搜索/链接/收藏）是否全部保持。

**Acceptance Scenarios**:

1. **Given** leaf100 专注阅读页，**When** 点击「下一页链接」，**Then** 布局阶段中位数 ≤300 ms（目标；若未达标，如实给出 After 数据与未达标原因分析）。
2. **Given** 引入更小首窗或骨架，**When** 用户快速连续点击链接，**Then** 不出现目录跳转错误、进度估算错误、位置恢复失败、搜索命中丢失、链接 Span 不可点、「收藏这一页」丢失等回归。
3. **Given** leaf500（1,999 块），**When** 同步骤下钻，**Then** 同样测量并记录首屏布局 Before/After（超大页上的收益/劣化如实报告）。

---

### User Story 3 - 页面切换拆解降至 ≤150 ms (Priority: P2)

把下钻时上一页 ReaderView/Scroll 的拆解耗时从当前 265–277 ms 压到 ≤150 ms：评估 ReaderView/Scroll 复用或延迟销毁方案；落地后必须复测系统返回/ESC pop 行为与 20 层阅读栈 VmRSS，确认无内存回退。

**Why this priority**: 拆解与布局共同构成单次下钻的主线程阻塞；降低拆解可进一步逼近"点击即达"的连续阅读体验。

**Independent Test**: leaf100 链式下钻采样"上一页拆解/首帧"心跳间隔（当前 265–277 ms）对比 After；随后链式 19 次下钻 + 逐层 pop 返回，采样 VmRSS 与 dumpLayout 节点数，与 296 MB / 1,440 节点基线对照。

**Acceptance Scenarios**:

1. **Given** leaf100 下钻链路，**When** 点击「下一页链接」，**Then** 上一页拆解/首帧的心跳单独观测间隔 ≤150 ms（目标；未达标则如实报告）。
2. **Given** 20 层阅读栈（根页 + 19 层），**When** 逐层 pop 返回到根页，**Then** 每层内容/滚动位置正确恢复，无白屏、错层或残留；VmRSS 不高于改动前水平。
3. **Given** 延迟销毁/复用方案上线，**When** 快速 push/pop 交替操作，**Then** 无泄漏迹象（VmRSS 稳定、节点数不累积）。

---

### User Story 4 - 搜索与元数据抽取移出 UI 线程 (Priority: P2)

把阅读页搜索从 UI 线程同步全量循环（`ReaderView.applySearch` 现状）移到 taskpool（复用上一轮 ArticleExtractService 的模式：@Concurrent 任务 + 超时 + 同步回退），用 20 ms 心跳确认搜索期间主线程无长阻塞；随后把 `applyMetadata()` 的同步抽取同样移出 UI 线程。注意：工作区遗留的 3 个 ReaderSearch* 半成品文件已按用户决定删除，本轮全新实现。

**Why this priority**: 搜索在超大页（1,999 块）上是可感知的 UI 线程阻塞；applyMetadata 是当前仅剩的同步抽取热点，两者共用已验证的 taskpool 模式，风险低收益确定。

**Independent Test**: 在 leaf500 页打开搜索输入关键词，心跳记录主线程最大间隔（对照：改造前同操作）；断网/超时场景下搜索仍可用（回退路径）；保存新书签触发 applyMetadata 时 UI 无长阻塞；设备端原有 119 用例 + 新增用例全部通过。

**Acceptance Scenarios**:

1. **Given** leaf500 已全量挂载（或仅首窗挂载），**When** 输入搜索词，**Then** 心跳最大间隔显著小于同步循环基线（数据成表），命中列表与跳转行为不变。
2. **Given** taskpool 初始化失败/超时/返回异常，**When** 执行搜索，**Then** 回退主线程同步搜索，功能不丢，且回退有日志可查。
3. **Given** 收藏临时页/保存新书签触发 applyMetadata，**When** 抽取大页面，**Then** 主线程心跳无长阻塞，元数据与快照写入结果与改造前一致。
4. **Given** 新增搜索 taskpool 用例，**When** 设备端测试执行，**Then** 用例总数按新增数同步更新（119 → N）。

---

### User Story 5 - pop 时裁剪非可见层 ArticleDocument（延伸项） (Priority: P3)

时间允许时：pop 离开某层后，把该层 ArticleDocument 裁剪为只含块文本/链接的紧凑结构（或等价减内存手段），降低 20 层阅读栈 VmRSS；必须复测再次进入该层（若结构支持）与 20 层 VmRSS。

**Why this priority**: 每层保留完整 ArticleDocument 是已知内存大头之一；但属于延伸项，前四项完成且验证通过后剩余时间再做，否则明确记录未做。

**Independent Test**: 20 层下钻后采样 VmRSS（对照 296 MB）与 VmHWM；若裁剪影响"返回上一层"后的再渲染，需验证返回后内容完整。

**Acceptance Scenarios**:

1. **Given** 20 层阅读栈，**When** 执行裁剪策略，**Then** VmRSS 较基线下降且数值成表记录。
2. **Given** 裁剪仅作用于非可见层，**When** pop 回到已裁剪层（如方案允许），**Then** 内容完整可读；若方案选择直接丢弃，**Then** pop 行为须与现有一致（不出现错误渲染）。

---

### Edge Cases

- 位置恢复目标块接近 1,999（第 10 次 200ms 重试仍未扩到目标块）时，重试耗尽后的兜底行为必须明确（回到顶部/最接近位置），不得卡死或白屏。
- 搜索 taskpool 超时（超大页 + 短超时）时同步回退本身可能阻塞 UI 线程——回退触发条件与超时值需在测量中校准，避免"回退比原来更糟"。
- 快速连续 push/pop（复用/延迟销毁场景）下的组件生命周期竞态：不能出现旧页内容闪现在新页。
- 骨架屏/更小首窗下，目录跳到窗口外块、搜索命中在窗口外块的组合路径。
- leaf500 每层 312 KB × 20 层的内存叠加与 dumpLayout 节点数上限。
- 心跳探针自身开销不得污染测量（采样密度与探针代码量保持与上一轮一致以便对比）。

## Requirements *(mandatory)*

### Functional Requirements

- **FR-001**: 系统 MUST 在任何代码改动前完成 leaf500 基线测量：1/5/10 次下钻的 click→layoutDone、上一页拆解/网络/抽取/布局阶段拆分（20 ms 心跳法）、VmRSS、dumpLayout 节点数，并确认分窗首屏/扩窗/目录/搜索/位置恢复行为，数据写入 docs/records/05 §6。
- **FR-002**: 系统 MUST 仅在 FR-001 数据支持时调整 INITIAL_BLOCKS（或相关窗口参数），并单独复测；不支持则保持 200 并记录结论。
- **FR-003**: 系统 MUST 通过 LazyForEach 或更小首窗 + 骨架（按数据择优）把 leaf100 单次下钻的布局阶段中位数压向 ≤300 ms，且不破坏目录、进度、位置恢复、搜索命中、链接点击、「收藏这一页」任一既有行为；给出 Before/After。
- **FR-004**: 系统 MUST 通过 ReaderView/Scroll 复用或延迟销毁把上一页拆解耗时压向 ≤150 ms，并复测 pop/back 行为与 20 层 VmRSS 无回退；给出 Before/After。
- **FR-005**: 系统 MUST 将阅读页搜索迁移到 taskpool（@Concurrent + 超时 + 同步回退），搜索期间 20 ms 心跳最大间隔有测量数据；随后将 applyMetadata 的正文抽取迁移到 taskpool，主线程心跳有测量数据；原半成品 ReaderSearch* 文件已删除，不得复活旧实现。
- **FR-006**: （延伸，时间允许）系统 SHOULD 在 pop 后裁剪非可见层 ArticleDocument 为紧凑结构以降低 20 层 VmRSS，并给出 Before/After；未做则 MUST 在记录文档中明确标注未做。
- **FR-007**: 每一项改动 MUST 单独验证（一次只改一项），验收门禁为：`hvigorw assembleHap` 成功、`codelinter` 0 error / 0 warn（允许既有 startIcon 建议）、设备端测试全通过且新增用例计入总数。
- **FR-008**: 文档 MUST 同步更新：docs/records/05-browser-link-reading.md §6（本轮全部数据）、docs/wiki/02-ui-layer.md、docs/wiki/03-data-layer.md、AGENTS.md 性能约束段；新增走查项补 docs/quality/01-walkthrough-checklist.md。
- **FR-009**: 临时 hilog/探针/临时文件 MUST 在测完后删除；全程不 commit / 不 push；不新增第三方依赖，不改 RDB schema、权限、main_pages.json；遵守 ArkTS 严格子集（禁 any / as 断言 / 结构化类型 / 动态属性访问，@Concurrent 只传可序列化参数）。

### Key Entities

- **ArticleDocument / ArticleBlock / ArticleLink**: 现有正文模型；FR-006 的紧凑结构是其裁剪形态（仅块类型/文本/链接区间），不得影响快照编解码与已有消费方。
- **搜索索引（新）**: 供 taskpool 搜索使用的可序列化载荷（全文本 + 块起始偏移 + 关键词），跨线程只传可序列化参数。
- **性能样本（记录约定）**: 每条含场景、click→layoutDone、阶段拆分（拆解/网络/抽取/布局）、VmRSS/VmHWM、dumpLayout 节点数、采样方法（20 ms 心跳），Before/After 同格式成表。

## Success Criteria *(mandatory)*

### Measurable Outcomes

- **SC-001**: leaf500 的 1/5/10 次下钻基线数据表完整落档（每档含阶段拆分 / VmRSS / 节点数），此前"leaf500 修复后未复测"状态消除。
- **SC-002**: leaf100 单次下钻布局阶段中位数 ≤300 ms，或虽未达标但给出实测值与瓶颈分析（不许猜测）。
- **SC-003**: 上一页拆解 ≤150 ms 且 20 层 VmRSS 不高于基线 296 MB（或给出未达标实测值），pop/back 无回归。
- **SC-004**: leaf500 搜索期间主线程心跳最大间隔较同步基线显著下降（数据成表）；applyMetadata 抽取期间主线程无长阻塞（心跳数据）。
- **SC-005**: 设备端测试全通过，用例总数 = 119 + 新增数并同步到全部相关文档；codelinter 0 error / 0 warn（允许 1 条既有 startIcon 建议）。
- **SC-006**:（延伸）20 层 VmRSS 较 296 MB 基线下降并成表；未执行则文档明确标注。

## Assumptions

- **环境变更（2026-10-24，Phase 4 执行中）**：真机 ADY-AL00（2YB0224508009888）T001–T003 阶段完成后被占用；经用户指示，自 T004 起全部测量/调试改在电脑端模拟器 `127.0.0.1:37565`（HUAWEI MateBook Pro 2in1，API 26）上进行。影响与处理：① 模拟器为宽屏 2in1 形态，UI 驱动坐标需按 dumpLayout 重新探测（原手机坐标不适用）；② 模拟器绝对耗时与真机基线（Pura 70 数字）**不可直接比较**，Before 必须在模拟器上重新采集，Before/After 仅做同环境对照；③ 全部文档数据须标注测量载体，真机复测列为"待设备可用后补充"，不阻塞本轮交付；④ 所有 hdc 命令必须 `-t 127.0.0.1:37565`，不得触碰被占用的手机目标。
- perfweb 本地页（leaf100/leaf500 各 21 页）与 serve4.js（18084）+ `hdc -t 127.0.0.1:37565 rport tcp:18085 tcp:18084` 转发可用（rport 对模拟器同样有效）；书签「性能页 1」若丢失可用深链重建。
- ≤300 ms / ≤150 ms 为努力目标而非绝对门槛：未达标时以真实数据 + 原因分析交付，不得虚报（用户验收条款 3 已明确"明确说明仍未测的部分，不要猜"）。
- ≤300 ms 布局目标主要针对 leaf100（648 块）单次下钻场景（即既有 356–515 ms 基线的同口径场景）；leaf500 同步测量并如实报告，不设硬门槛。
- 上一轮已交付能力（分窗、taskpool 抽取、转义修复、MAX_STACK=20 等）为既成事实，不重复实现、不回退。
- 网络耗时受 hdc 端口转发抖动（0.4–3.3 s）影响，必须拆分阶段看数据，不把总时长当结论。
- 既有 119 用例与文档数字（docs/records 中的历史数字可能滞后）以源码与本轮实测为准。

## Open Questions

- （已解决）遗留 ReaderSearch* 半成品文件处置：用户已决定删除后重做，工作区已恢复 clean @ 6f460b0。
- （已解决）目标 5 是否纳入：用户已决定纳入为 P3 延伸项。
