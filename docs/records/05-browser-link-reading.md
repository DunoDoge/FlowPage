# 流笺 FlowPage · 内置浏览器与链接阅读实现记录

> **时效说明**：本文记录 2026-10-22 内置浏览器/链接阅读批次；设备验证基于模拟器 127.0.0.1:37565
> （2in1 3120×2080）。当前状态仍以 [docs/README](../README.md) 与源码为准。

- 日期：2026-10-22
- 范围：单标签 ArkWeb 内置浏览器 + 阅读模式链接抽取/阅读栈 + 快照 v2
- 明确不做：多标签、无痕、下载管理、网页 CSS 阅读模式、正文图片落盘、自动收笺链接页

## 1. 交付内容

| 能力 | 实现 |
|---|---|
| 快照携带链接 | `ArticleLink{start,end,url}`；`FLOWPAGE-ARTICLE-2` 每块第三字段编码链接区间；兼容读取 v1 |
| 链接抽取 | `ArticleExtractor.BlockScanner` 用私有标记记录 `<a>` 文本区间，清理后计算偏移；`resolveHttpUrl()` 解析绝对/相对链接，只保留 http(s) |
| 阅读模式链接 | `ReaderSegments` 合并链接与搜索命中；`ReaderView` 用 `Span.onClick` 打开链接，下划线 + 墨色样式；不新增彩色 token |
| 阅读栈 | 新增 `ReadingShell`（阅读/浏览统一外壳）+ `ReadingEntry`；链接页逐层 push，系统返回/ESC 逐层 pop |
| 临时阅读 | 链接页不写 RDB、不写 `flowpage_reader`、不自动收笺；底部与菜单提供「收藏这一页」 |
| 内置浏览器 | 单标签 `Web`：可编辑地址、前进/后退/刷新、加载进度、错误态、系统浏览器兜底 |
| 浏览 → 阅读 | 浏览器内用 `runJavaScriptExt` 取实时 `document.body.innerHTML`，复用 `ArticleExtractor` 生成临时阅读页 |
| 入口 | 详情「打开原文」改为应用内浏览；新增「系统浏览器」；正文链接 / 专注阅读 / 浏览器「阅读」均进入 `ReadingShell` |

## 2. 数据与格式

- `ArticleBlock.links` 仅存本机快照，不进入 RDB、WebDAV 或同步记录。
- 快照行格式：

```
FLOWPAGE-ARTICLE-2
p<TAB>看这里。<TAB>1,3,https%3A%2F%2Fexample.com%2Fa
h2<TAB>标题<TAB>
```

- 第三字段为 `start,end,encodeURIComponent(url)`，多条用 `;` 连接；解码时校验 `0 <= start < end <= text.length`。
- 旧 `FLOWPAGE-ARTICLE-1` 仍可读，链接为空；旧文章需「重新抓取」后才有可点链接。
- `ArticleDocument.truncate()` 同步裁剪链接，避免截断后偏移越界。
- 临时页的块位置只存在 `ReadingEntry.position` 内存字段；根书签仍写 `flowpage_reader`。

## 3. 交互与状态

- `Index` 根部 `bindContentCover` 承载 `ReadingShell`；`onWillDismiss(reason=PRESS_BACK)` 先请求阅读栈返回，根部才关闭覆盖层。
- `ReadingShell` 每个条目有 `mode`（READER/BROWSER）：
  - 阅读模式正文链接 → `pushReaderLink()`；http(s) 文档原生抓取，非文档直接进浏览器。
  - 浏览模式「阅读」→ 当前 URL 与已有正文一致时回到阅读，否则实时 DOM 提取并 push 临时阅读条目。
  - 浏览模式后退优先走 Web 历史；历史耗尽后回到已有正文或弹出条目。
- 临时页头部显示「临时阅读」，正文底部显示「收藏这一页」；收藏走 `FlowRepository.saveUrl(..., BookmarkSource.BROWSER)` + 后台 `applyMetadata()`。
- 根书签的已读/摘录仍由仓库 `notify()` 驱动详情与列表刷新。

## 4. 权限与安全

- 复用 `ohos.permission.INTERNET`；未新增权限、未改 `main_pages.json`、未改 RDB schema/同步协议。
- `Web` 仅允许 http(s)/about:blank 做主框架导航；其他 scheme toast 后拦截。
- `javaScriptOnDocumentStart` 覆盖 `window.open` 并移除 `target`，避免 `target=_blank` 新窗口阻塞渲染进程。
- 相机/麦克风/定位请求不授权；`fileAccess(false)`。

## 5. 验证记录

- 构建：`hvigorw assembleHap` → BUILD SUCCESSFUL（SDK hvigor 7.26.8）。
- 静态检查：`codelinter -c code-linter.json5` → 0 error / 0 warn / 1 条既有 startIcon 性能建议。
- 设备端：11 个套件 / **118** 个用例全部通过（新增 12 个链接抽取/编解码/截断/分段用例）；
  性能批次后为 **119** 个（新增转义 HTML 解码用例）。
- 模拟器实测：
  - 阅读模式正文链接点击后进入临时阅读页；标题/域名显示「临时阅读」，正文正常渲染。
  - 阅读模式「网页」→ 内置 Web 加载 `https://example.com`；再「阅读」回到已有正文。
  - 快照实测写入 `FLOWPAGE-ARTICLE-2`，标题/分类/「继续阅读全文」/文章列表均带正确链接区间。
  - 正文链接可见下划线；点击命中链接字形即可触发。
  - 浏览模式地址栏、前进/后退/刷新、错误态已接入标准 ArkWeb API；本轮仅验证 Web 加载与阅读/网页切换，
    其余按 [走查清单](../quality/01-walkthrough-checklist.md) §1.2 逐项验收。

## 6. 连续链接阅读性能（2026-10-22 第二批）

真机 HUAWEI Pura 70（ADY-AL00 / API 26），本地页面 `leaf100`（101,620 字符 / 648 块 / 1,139 链接），
链式点击「下一页链接」。栈每次只有一页在渲染，旧实现一次性挂载全部块。

### 6.1 主线程阻塞（心跳 20ms 采样，取每秒最大间隔）

| 场景 | 改动前 | 改动后 |
|---|---|---|
| 冷开专注阅读（根页，648 块） | 2,548 ms 连续阻塞 | 384–460 ms |
| 单次「下一页链接」点击 → 新页可读 | 5,715–7,180 ms 连续阻塞（5 次样本） | 1,000–1,623 ms，其中主线程最长间隔 356–525 ms |

### 6.2 阶段拆分（同一批样本的中位数）

| 阶段 | 改动前 | 改动后 |
|---|---|---|
| 抓取返回（`http.request` resolve） | 3,000–3,300 ms | 434–992 ms |
| 正文抽取（101,620 字符 / 648 块） | 164–213 ms，占用主线程 | 151–211 ms，taskpool worker，主线程不阻塞 |
| 新页布局（article 就绪 → 全部已挂载块 `onAreaChange` 完成） | 2,219–3,617 ms（648/648 块） | 356–515 ms（200/648 块） |
| 上一页拆解 / 首帧 | 与「抓取返回」重叠，无法用现有日志分离 | 265–277 ms（心跳单独观测到的一次间隔） |

改动前的整段 5.7–7.2 s 是一次连续阻塞：抓取 promise 直到主线程空闲才被处理，所以上表的「抓取返回」
包含上一页 648 块拆解与 GC 的等待，不能当作纯网络耗时。改动后主线程在抓取期间每 20 ms 正常唤醒，
网络耗时才是真实值；同一时段 `tiny.html`（96 字节）与 `leaf100/1.html`（170 KB）的直连探测分别为
418 / 509 ms，说明本地 HTTP 已不是瓶颈。

### 6.2.1 GC 占比

用 `@ohos.hidebug` 的 `getVMRuntimeStats()`（`ark.gc.gc-count` / `ark.gc.gc-time`，主线程累计）与
`getAppVMMemoryInfo().heapUsed` 采样，各 3 次点击（同一台真机，另一次会话）：

| 构建 | 点击→layoutDone | 主线程最长间隔 | 点击窗口内 GC | 主线程 GC 累计 | 点击后 VmRSS |
|---|---|---|---|---|---|
| 改动后（200 块窗口 + taskpool） | 835–887 ms | 361–374 ms | 0 次 | +11 / +21 / +24 ms | 326–349 MB |
| 改动前（648 块全量 + 同步抽取） | 6,732–6,795 ms | 6,711–6,779 ms | 6 次 | +79 / +38 / +42 ms | 554–573 MB |

- 改动前的主线程 GC 只占那次 6.7 s 阻塞的 **0.6%–1.2%**（单次 6–13 ms），**GC 不是主因**；
  主要耗时是同步抽取 + 一次挂载 648 块。
- 改动后点击窗口内没有主线程 GC，只有静置后的 2 次（heap 12→33 MB 后回落到 17 MB）。
- 限制：`hidebug` 的 gc-time 是当前线程累计值；worker 线程的 `IdleGCTrigger: trigger full gc`
  暂停时长平台未输出，日志里只有整体汇总（`GC statistic, count:5, maxPause:15.4, averagePause:5.4`），
  因此「worker GC 暂停」仍未单独计量。

### 6.3 内存与节点数（栈内 20 层）

| 指标 | 改动前 | 改动后 |
|---|---|---|
| VmRSS | 533 MB（VmHWM 626 MB） | 296 MB（VmHWM 425 MB） |
| `uitest dumpLayout` 节点数 | 4,124 | 1,440 |

### 6.4 改动

- `ReaderView` 首屏只挂载前 200 块，滚到已渲染内容底部或点「继续阅读 · n/total」每次追加 200 块；
  `SelectionContainer` 随之只覆盖已挂载块。目录/搜索跳转先 `ensureMounted(index)`，位置恢复到窗口外时
  按 `BLOCK_BATCH` 扩窗后重试（上限 10 次 ×200 ms）。进度在未全量挂载时按块下标估算。
- `ArticleExtractor` 移到 taskpool（`ArticleExtractTask` + `ArticleExtractService`），只传 HTML/title/baseUrl，
  用 `ArticleCodec` 的字符串格式跨线程传输；4 s 超时、初始化失败或结果异常时回退主线程同步抽取。
  `ReaderPageLoader.load()` 与 `ReadingShell.extractFromWeb()` 走 worker，元数据补全仍走同步路径。
- `MAX_STACK` 保持 20（根页 + 19 临时层）；第 20 次下钻 toast 改为
  「最多同时打开 20 层，先返回一层再继续」。
- 内置 Web 的 `runJavaScriptExt` 返回值先经 `decodeWebHtml()` 还原 `\uXXXX` / `\"` 等转义，再交给抽取器；
  该缺陷（正文显示 `\u003Cheader …`）已修复，`Reader.test` 覆盖转义输入 → 正常块文本。

### 6.5 本轮验证

- 构建 `hvigorw assembleHap` 成功；`codelinter` 0 error / 0 warn / 1 条既有 startIcon 建议。
- 设备端 11 套件 / **119** 用例通过（新增 `decodesEscapedHtmlFromWebView`）。
- 真机走查：链式 19 次下钻成功、第 20 次被拒并 toast；Web 内点站内链接 → 阅读显示正常正文与「临时阅读」；
  阅读/网页切换 5 轮正常；从 104 块与 287 块关闭再进入均恢复到原块；滚到底部自动扩到 648/648 且进度 100%。

### 6.6 第三轮优化（2026-10-25，模拟器口径）

**载体**：HUAWEI MateBook Pro 2in1 模拟器 `127.0.0.1:37565`（API 26；真机 Pura 70 自 T004 起被占用，全程未触碰）。
模拟器绝对耗时与真机不可直接比较，Before/After 均为模拟器同环境对照；真机复测待设备可用后补充。
完整数据与测量方法注记见 `/tmp` 草稿 `round3-us1-before.md`～`round3-us5.md`（本节为落档摘要）。

#### S1 · leaf500（312 KB / 1,999 块）基线（两轮各 10 钻，中位数）

| net | extract（taskpool） | fetch→rebind | layout（200 块首窗） | click→layoutDone | 下钻窗口 hbMax |
|---|---|---|---|---|---|
| 237–247 ms | 514 ms | 23–28 ms | 272–274 ms | 1,048–1,060 ms | 293–308 ms |

VmRSS：打开 363 MB → 10 钻 540 MB（HWM 571）；`dumpLayout` 节点恒 1,702（首窗恒 200 块）。
分窗行为核验：首屏仅挂 200 ✅；滚底自动扩窗 200→400→800 ✅；目录跳窗口外至全量 1,999（分批推进）✅；
搜索 1/1 命中跳转 ✅；位置恢复窗口外（~块 498）3/4 成功、尾部（~块 1,950）1/1 成功。
**发现（未修）**：恢复重试预算时序敏感——失败模式为停顶部 + visible 已扩满 + 进度条显示目标值（10×200ms
内块偏移测量未完成即耗尽）；候选修复是 `ensureMounted` 按目标距离步进或重试预算随目标自适应。
窗口参数决策：**INITIAL_BLOCKS/BLOCK_BATCH/恢复预算均不调**（layout 无窗口参数劣化；恢复失败与窗口无关）。

#### S2 · leaf100（648 块）布局（12 钻，Before）

layout 中位 **259 ms**（251–265）≤ 300 ms 目标（模拟器口径已达标，分帧挂载/骨架不触发）；
total 672 ms；hbMax ≤287 ms ≈ layout 段本身。六项行为走查（目录/进度/恢复/搜索/链接/收藏）通过；
遗留：多命中游标步进因模拟器 IME 注入不稳未驱动复演（设备用例已覆盖纯函数等价性）、
逐层 pop 内容因性能页同文不可文本断言。

#### S3 · 拆解归因修正（对照实验）

初次打开（纯新建 200 块，无旧页销毁）layout=262–275 ms ≈ 下钻（销毁+新建）251–282 ms
→ **上一轮真机口径的「265–277 ms 拆解」实为新页构建主导的整帧间隔，旧页销毁边际成本 ≈0–20 ms（≤150 ms）**。
双 ReaderView 槽位延迟销毁方案不做（预期收益 0–20 ms，内存/竞态风险倒挂）。

#### S4 · 搜索与元数据抽取移出 UI 线程

- 新增搜索三件套：`ReaderSearchCore`（纯函数，块内 containment、不跨块）+ `ReaderSearchTask`（@Concurrent）
  + `ReaderSearchService`（buildIndex + taskpool + 2 s 超时 + 同步回退）。`ReaderView.applySearch` 异步化
  （世代 token 防过期、索引按 articleSignature 缓存、120 ms 防抖保留、关闭/换文释放索引）。
- leaf500 全量 1,999 块：搜索主线程心跳 **156 ms → 21–25 ms**；索引构建 6 ms（UI 线程一次，无需下沉）。
- `FlowRepository.applyMetadata` 显式 `offThread=true`：新收藏触发 `extract-done`（taskpool 路径），无心跳尖峰。
- 设备端新增 `ReaderSearch.test.ets` 11 例；**119 → 130 用例全绿**。

#### S5 · 阅读栈内存裁剪（leaf100 20 层）

- 机制 A：`back()` 出栈即裁 `entries` 尾部（被弹层无前进路径）。
- 机制 B：push 后 600 ms 空闲把非当前层 article 压为 `ArticleCodec.encode()` 串，pop 回时 decode
  （encode 8–14 ms/层在空闲期；decode 12–15 ms/层（648 块）≪100 ms 门限，保留）。
- 20 层 pop 至根：**改动前 419.6 MB 恒定不降 → 改动后 380 MB**（pop 过程 490→407→380 递降）；峰值相当（530→555，GC 抖动内）。
- 测量方法注记：模拟器长会话后 `uitest keyEvent`（ESC）会被系统焦点吞掉，pop 驱动改用界面「返回」按钮。

#### 未测/未做（如实标注）

- 真机（Pura 70）全部指标复测：**待设备可用后补充**（模拟器与真机不可比）。
- S2 分帧挂载/骨架、S3 双槽延迟销毁：数据不触发，未实现。
- S1 恢复重试预算时序敏感问题：记录为发现，未在本轮修复。
- `dumpLayout` 节点数 Before/After 对照仅 leaf100（1,691）/leaf500（1,702）恒定值，无 After 变化（无渲染结构改动）。

## 7. 已知限制

- 链接页原生抓取不执行 JS、不带 Cookie；JS 渲染/登录墙/付费墙可能提取失败，此时可在浏览器查看。
- 浏览器模式切换会卸载 Web，Web 历史/滚动不保留（第一版行为）。
- 旧 v1 快照没有链接；需「重新抓取」。
- 阅读模式仍不保留图片/视频；超长页面按 200 块分批挂载，滚到底部继续加载。
- `Span` 不可键盘聚焦，2in1 键盘用户暂用顶部「输入网址」或鼠标点击。
- 系统返回依赖 ContentCover `onWillDismiss`；若特殊设备手势不走该回调，需将 `ReadingShell` 迁移为 `NavDestination`。

## 8. 相关文档

- [wiki/02-ui-layer.md](../wiki/02-ui-layer.md)
- [wiki/03-data-layer.md](../wiki/03-data-layer.md)
- [wiki/04-sync-and-services.md](../wiki/04-sync-and-services.md)
- [design/01-ui-spec.md](../design/01-ui-spec.md)
- [quality/01-walkthrough-checklist.md](../quality/01-walkthrough-checklist.md)
