# 流笺 FlowPage · 软件开发文档

> 本目录是**纯索引**。当前状态、构建门禁、性能口径等易变事实唯一维护于 [AGENTS.md](../AGENTS.md)；
> 方向性决策（为什么这样做）见 [adr/](./adr/README.md)。

## 文档时态约定

文档按时态各有唯一归宿，跨时态复制事实是漂移的根源：

| 时态 | 归宿 | 维护方式 |
|---|---|---|
| 现在时 · 速查 | [AGENTS.md](../AGENTS.md) | 随代码同步更新；易变数字（用例数、耗时、内存）只在此处 |
| 现在时 · 详解 | [wiki/](./wiki/README.md) | 随代码同步更新；引用而非复制易变数字 |
| 现在时 · 契约 | `openspec/specs/` | 能力规格（系统持久行为契约），随变更归档同步 |
| 过去时 · 决策 | [adr/](./adr/README.md) | append-only；推翻用 Superseded 链，不改写 |
| 过去时 · 日志 | [quality/](./quality/)、[records/](./records/) | append-only；仅补时效标注与失效路径 |
| 将来时 · 变更 | `openspec/changes/` | proposal → 实施 → 归档至 `archive/` |

不随代码漂移的基线文档：[product/](./product/) 产品需求、[design/](./design/) 设计规范。

## 文档索引

| 文档 | 内容 | 适合谁读 |
|---|---|---|
| [AGENTS.md](../AGENTS.md) | 项目快照、构建与验证、架构与数据流、性能约束、代码红线 | 开发 / 代理 |
| [adr/README.md](./adr/README.md) | 方向性决策索引与 ADR 规则（ADR-0001 起） | 开发 / 评审 |
| [product/01-prd.md](./product/01-prd.md) | 定位、竞品、用户、场景、差异化、功能范围、业务规则 | 产品 / 评审 |
| [design/01-ui-spec.md](./design/01-ui-spec.md) | 设计 token、三断点布局、组件与页面规格、动效与无障碍 | 设计 / 前端 |
| [wiki/README.md](./wiki/README.md) | 分层 Code Wiki：架构、UI、数据、同步与服务、构建运行 | 开发 / 维护 |
| [quality/01-walkthrough-checklist.md](./quality/01-walkthrough-checklist.md) | 手机 / 2in1 / 同步走查步骤 | 测试 |
| [quality/02-walkthrough-issues.md](./quality/02-walkthrough-issues.md) | 真机走查问题、定位与修复验收 | 下一会话 |
| [records/01-implementation-log.md](./records/01-implementation-log.md) | 批次 A/B/C 实现记录与真机验证（历史快照） | 评审 / 验收 |
| [records/02-code-review.md](./records/02-code-review.md) | 功能完成度、代码质量、P0/P1 问题与修复批次（历史快照） | 开发 / 评审 |
| [records/03-review-follow-up.md](./records/03-review-follow-up.md) | 第二轮复审结论复核与第三批修复（历史快照） | 开发 / 评审 |
| [records/04-reading-mode.md](./records/04-reading-mode.md) | 2026-10-22 阅读模式批次（历史快照） | 开发 / 评审 |
| [records/05-browser-link-reading.md](./records/05-browser-link-reading.md) | 2026-10-22/23 内置浏览器、链接阅读与性能轮次（历史快照） | 开发 / 评审 |
| [records/06-implementation-plan.md](./records/06-implementation-plan.md) | 批次实施计划与验收标准（历史快照，2026-10-26 归档） | 项目管理 / 验收 |

## 文档文件命名

`docs/` 文件名统一为「两位序号 + 英文 kebab-case」；`wiki/` 是独立的 Code Wiki，不参与编号；
`adr/` 为 `NNNN-kebab-slug.md`。

## 变更管理

新功能与修改一律走 OpenSpec 变更流程（`openspec/changes/`，proposal / specs / design / tasks），
完成后归档并按需把结论吸收进 AGENTS.md 与 wiki；项目约束见 `openspec/config.yaml`。
