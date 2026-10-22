# 流笺 FlowPage · 阅读模式实现记录

> **时效说明**：本文记录 2026-10-22 阅读模式批次；设备验证基于模拟器 127.0.0.1:37565（2in1 3120×2080）。
> 当前状态仍以 [docs/README](../README.md) 与源码为准。

- 日期：2026-10-22
- 范围：结构化正文快照 + 正文行内阅读器 + 全屏专注阅读
- 明确不做：内置浏览器、跨端阅读进度同步、图片/复杂排版落盘

## 1. 交付内容

| 能力 | 实现 |
|---|---|
| 正文提取 | 新增 `core/parser/ArticleExtractor.ets`，优先 `article`/`main`/正文容器，剔除导航、页脚、分享、评论、广告等噪声；输出 heading / paragraph / quote / listItem / code |
| 快照格式 | 新增 `core/service/ArticleCodec.ets`，`snapshots/<id>.txt` 内使用 `FLOWPAGE-ARTICLE-1` 版本头；旧纯文本读取时降级为段落；RDB 与同步协议不变 |
| 行内阅读器 | 新增 `components/ReaderView.ets`；正文页签按块渲染，提供字号和专注阅读入口 |
| 全屏专注阅读 | `DetailContent` 使用 `bindContentCover` 打开 `ReaderView(immersive=true)`；支持搜索/高亮、目录、字号/行距/段距、进度、位置恢复 |
| 选中摘录 | `SelectionContainer` + `bindSelectionMenu`，菜单为“复制 / 存为摘录”；已有摘录换行追加 |
| 阅读状态 | 进度 ≥90% 或停留 30 秒标记已读；手动标记未读保留 |
| 重新抓取 | 详情操作新增“重新抓取”，可覆盖旧快照 |

## 2. 数据与偏好

- `flowpage_settings`：`reading_size`（15–23）、`reading_line`（0–2）、`reading_para`（0–2）。
- `flowpage_reader`：`pos_<bookmarkId>` 保存正文块索引，仅本机；彻底删除/清空数据时清理。
- 正文快照仍为本地文件，不上传 WebDAV。读取只看 `snapshotPath` 是否可读，不再要求 `snapshotStatus === DONE`；
  抓取失败或正文为空时保留旧路径与状态，自动快照关闭但已有可读旧快照时状态写回 `DONE`；`snapshotAt` 同时作为详情页正文缓存版本。

## 3. 验证记录

- 构建：`DEVECO_SDK_HOME=... hvigorw assembleHap` → BUILD SUCCESSFUL。
- 自动化：设备端 11 个套件 / 106 个用例全部通过（`ReaderTest` 23 个，新增 card+comments、article.comments+main、
  navigation 容器、junk token 反例、CJK 站点后缀标题等回归）；codelinter 0 error / 1 条 startIcon 性能建议。
- 模拟器实测：
  - InfoQ、MDN 正文按块渲染；代码块保留换行；TOC 可跳转；搜索 `DeepSeek` 得到 2 处并可上一处/下一处。
  - 专注阅读滚动后进度增长（27%/66%；此数值来自旧进度算法，当前按可滚动高度计算，需在设备上重测），关闭重进恢复到上次块位置。
  - 字号/行距/段距设置即时生效并持久化。
  - 行内长按选中出现“复制 / 存为摘录”，保存后摘录页签显示所选文本。
- 已知限制：
  - 正文提取是启发式正则/栈扫描，不保证所有站点完美；空块 fallback 只对已清理 junk 的容器降级为整页段落，
    不会再把评论/导航当正文。无法区分真实短正文与 teaser 时优先保留唯一 `<article>`，宁可留下 teaser 也不丢正文。
  - 超长正文（接近 204800 字符）当前一次渲染全部块；若后续出现滚动卡顿，再引入分组虚拟化。
  - 全屏阅读使用 `bindContentCover`，不支持横竖屏切换（系统模态限制）。
  - 旧快照不会自动重写；用户可点“重新抓取”获得结构化正文。
  - 超长正文恢复位置最多重试 5 次（每次间隔 200ms）；块偏移尚未测量完成时不会写回位置。
  - 重新抓取且正文内容签名确实变化时才清除该笺本机阅读位置；内容相同的重复抓取保留位置。
  - 抓取失败或新正文为空时保留旧快照与状态，已有正文不会被标记为失败。

## 4. 相关文档

- [wiki/02-ui-layer.md](../wiki/02-ui-layer.md)
- [wiki/04-sync-and-services.md](../wiki/04-sync-and-services.md)
- [design/01-ui-spec.md](../design/01-ui-spec.md)
- [quality/01-walkthrough-checklist.md](../quality/01-walkthrough-checklist.md)
