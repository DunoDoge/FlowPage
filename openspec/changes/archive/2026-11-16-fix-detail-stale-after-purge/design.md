# Design

## Context

见 proposal.md 的 Why。现状事实（探索期已核实）：

- `DetailContent` 有两条取数路径：`load()`（`@Monitor('bookmarkId')` / 挂载时）对「查无此笺」正确置 `hasBookmark = false`；`syncSnapshot()`（`@Monitor('appState.refreshTick')`）在 `repo.get()` 返回 `undefined` 时**直接返回**，`@Local bookmark` 内存对象继续渲染——僵尸详情的唯一来源。
- 宿主接线已存在：宽断点 `onRemoved → appState.clearSelection()`；手机端 NavDestination `onRemoved → closeDetail()`（仅弹栈，不清 `selectedId`）。
- 书签可经四条路径从事实源消失：列表行菜单 / 批量「彻底删除」（`purgeMany` → `notify()`）、详情面板自身「彻底删除」（`purge` → `notify()` + `onRemoved`，已正确）、同步远端墓碑（`purgeFromRemote` 不 notify，轮末 `afterSync()` 统一 bump）、启动期 `purgeExpired()`（UI 未起，无影响）。
- `DetailContent` 仅在 `ready=true` 后挂载（Index 根据仓库 init 门控），`repo.get()` 返回 `undefined` 可严格判定「行已不在 RDB」，无初始化期误判窗口。

## Goals / Non-Goals

**Goals:**

- 任何消失路径下，详情面板在下次库刷新后不再展示已消失书签，回到空态（宽断点）/ 收起详情页（手机端）。
- 选中态随腾空同步清空：`selectedId` 不残留死指针（行高亮、跨端接续）。
- 刷新结果只作用于发起时的目标书签，不误伤快速切换后的新选中。

**Non-Goals:**

- 邮件式「删后自动跳下一条」的选中策略（见 D5，可作未来独立变更）。
- `load()` 路径的「死 id 进参」处理（如携带已消失书签 id 的跨端接续打开空详情）：`load()` 本身不追加清空逻辑；死 id 空页的后续收口见 Risks。
- 编辑态（`editing`/`busy`）期间被同步删除的即时腾空：接受延迟自愈（见 Risks）。
- `purgeFromRemote` 补 `notify()` 或任何同步层改动。

## Decisions

### D1: 修复收口在展示方（`syncSnapshot`），不在删除源头

`syncSnapshot()` 的 `found === undefined` 分支对齐 `load()` 语义（置 `hasBookmark = false`），并触发既有 `onRemoved` 事件交宿主收口。原则：**能变僵尸的消费者自己免疫**，不依赖删除入口自觉。

- 备选 A：`StreamHome.purgeItems` 里检查 `selectedId ∈ ids` 后 `clearSelection()`。否决：只覆盖列表两条路径，同步墓碑与未来任何清理路径仍僵尸；且每个新删除入口都要记得补检查，逻辑分散易漏。
- 备选 B：`FlowRepository.purgeOne` 内清选中。否决：仓库层耦合 UI 选中语义；`purgeFromRemote` 等同步内部方法刻意不 notify（轮末统一刷），还需另加一套；详情面板自身删除已走 `onRemoved`，仓库再清属双写。

### D2: 用既有 `onRemoved` 事件腾空，而非仅置 `hasBookmark = false`

`syncSnapshot` 查无此笺时置空展示**并**触发 `onRemoved`：宽断点 `clearSelection()`（`selectedId` → `''`，`@Monitor('bookmarkId')` 联动 `load()` 复位），手机端 `closeDetail()` 弹栈。

- 备选：仅置 `hasBookmark = false`、不动选中。否决：`selectedId` 残留死指针——宽屏行高亮失配、`onContinue` 跨端携带死 id；且与详情内删除 / 恢复 / 归档全走 `onRemoved` 的既有词汇割裂，同因不同果。

### D3: 手机端 `PageMap` 的 `onRemoved` 补一行 `clearSelection()`

手机端详情页收起时同步清空 `selectedId`（`clearSelection()` + `closeDetail()`），与宽断点接线口径对齐，兑现 spec「跨端接续不携带已消失书签标识」。

- 备选：维持仅弹栈。否决：`selectedId` 死指针经 `onContinue` 外泄到对端设备（对端打开空详情）；宽 / 手机两断点同因不同果。改动成本一行，收益是选中语义全断点一致。

### D4: 竞态守卫用 `bookmarkId` 快照比对

`syncSnapshot` 进入时快照 `const id = this.bookmarkId`；`await repo.get(id)` 返回后若 `this.bookmarkId !== id` 直接返回——旧响应既不覆盖新选中展示，也不因其 `undefined` 误腾空新选中。与 `loadArticle` 的 `articleKey` 守卫同款。

- 备选 A：`loadGeneration` 式计数器（`StreamHome.load` 模式）。否决：为多次 await 的负载路径设计，`syncSnapshot` 仅一次 await，快照比对已封闭窗口，计数器过度。
- 备选 B：不加守卫。否决：既有竞态窗口恰会制造本变更要防的误伤——连点两行 + 旧行恰被删除时，旧响应的 `undefined` 分支会腾空新选中行展示。

### D5: 腾空后去向为「选一笺」空态，不自动跳下一条

- 备选：Outlook / Gmail 式删后自动选中列表下一条。否决：需定义「下一条」的筛选上下文、空列表回退、与 `clearSelection` 既有语义的关系；行为变更远大于缺陷修复，且与详情面板内删除 / 恢复 / 归档后的既有表现（空态）不一致。批量清理场景已有批量栏承担，单条清理后点一行成本可接受。如真机反馈需要，另立变更。

### D6: 腾空分支同时清阅读计时器

`syncSnapshot` 的腾空分支置 `hasBookmark = false` 时同步 `clearReadingTimer()`。否则「非删除态书签 + 同步墓碑删除 + 阅读计时器挂起」组合下，30 秒后计时器对已消失书签触发 `markRead`，UPDATE 空行不抛错而 `this.bookmark.id === id` 仍成立，弹「已标记为已读」幽灵 toast。`load()` 入口本就清计时器，腾空分支对齐即可。

- 备选：在 `markRead` 里加 `hasBookmark` 守卫。否决：治标——计时器本不该在书签消失后继续存活；腾空点收口一次即可，不给每个下游消费者各自设防。

## Risks / Trade-offs

- [误腾空：删除"别的"书签也清空详情] → 守卫缺失或写错所致。缓解：D4 快照比对 + spec 负向场景「删除其他书签不影响当前展示」纳入验证。
- [手机端阅读中被同步墓碑收起详情页，略显突兀] → 替代方案（僵尸页可交互：恢复报错、彻底删除对空行谎报成功）更差；收起与详情内删除同款词汇，用户已建立心智。
- [编辑态被同步删除的延迟自愈] → `editing`/`busy` 守卫使 `syncSnapshot` 跳过；保存时 `saveEdits` 对空行无写不抛错（`editContent` 返回 `undefined` 不 notify），随后 `load()` 兜底腾空。窗口极小且自愈路径闭环，接受；强制即时腾空会丢用户正在输入的草稿，伤害大于收益。
- [死 id 空详情页被腾空分支顺带收口] → 死 id 深链 / 跨端接续打开的空详情，首个 refreshTick 即被 `syncSnapshot` 判「查无此笺」腾空（手机端弹栈 + 清选中）。略越 Non-Goal 的「维持现状空态展示」，但彼页本就空白无操作，与 spec R1「不区分触发路径」一致，且死 id 不再经 `onContinue` 外泄，行为良性。
- [验证盲区：`uitest dumpLayout` 看不见部分渲染态] → 本变更无动画、无 translate，空态文案「选一笺」可直接断言，不依赖渲染探针；2in1 真机注意免键盘路径（AGENTS.md 既有教训），本流程全程点击无文本输入。
