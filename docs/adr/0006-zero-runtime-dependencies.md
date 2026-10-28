# ADR-0006: 零第三方运行时依赖

- 状态：Accepted
- 日期：2026-10-26（补记：原决策于 2026-10-20 技术方案）

## Context（背景）

HTML 书签解析、WebDAV XML 解析、网页正文提取三处都有成熟第三方库可用，但引入它们意味着：
供应链风险（审计、漏洞、停维护）、包体膨胀、以及与 ArkTS 严格子集的兼容成本（多数 npm 生态库
不是为 ArkTS 写的）。自研工作量评估：三处均为有限域问题（Netscape 格式、固定 XML 子集、启发式
正文密度），可控。

## Decision（决策）

`oh-package.json5` 不引入任何第三方运行时依赖；解析器（`BookmarkHtmlParser`）、同步 XML
（`WebDavXml`）、正文提取（`ArticleExtractor`）、高亮等全部自研。开发工具链（hvigor、codelinter、
hypium 测试框架）不计入运行时依赖。

## Consequences（后果）

- 包体小（目标 ≤ 20 MB）、无供应链审计面、构建确定性强。
- 正文提取是启发式实现，不保证所有站点完美——宁可保留 teaser 也不丢正文，产品口径不承诺完美。
- 复杂网页场景（GBK 编码、压缩 HTML、跨行标签）的适配由自己承担，已知限制记录在 records。
- 若未来出现硬需求（如高质量 DOM 解析），需新开 ADR 推翻本决策。
