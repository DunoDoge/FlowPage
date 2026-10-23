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
