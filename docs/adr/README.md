# ADR · 方向性决策记录

记录 FlowPage 的方向性技术与产品决策：每个决策一个文件、连续编号、append-only。
本目录回答「为什么这样做」；「现在是什么样」看 [AGENTS.md](../../AGENTS.md) 与 [wiki](../wiki/README.md)，
「当时做了什么」看 [records](../records/)。

## 规则

- **粒度红线**：只记方向性决策（数据归属、同步底座、框架选型、架构边界、视觉方向）。
  性能调优参数（窗口大小、耗时中位数）、实现级评估（某方案否决理由属于单次变更的）**不进 ADR**，
  它们留在 AGENTS.md 约束段、wiki 与 `openspec/changes/archive/`。
- **append-only**：不删除、不改写已发布的 ADR；推翻旧决策时把旧 ADR 的状态改为
  `Superseded by ADR-NNNN` 并保持原文，新 ADR 的 Context 引用旧编号。
- 文件名：`NNNN-kebab-slug.md`，NNNN 从 0001 连续递增。
- 内容中文，四段结构，补记需标注原决策时间。

## 模板

```markdown
# ADR-NNNN: <标题>

- 状态：Accepted
- 日期：YYYY-MM-DD（补记：原决策于 YYYY-MM-DD）

## Context（背景）

为什么需要做这个决策：面临的问题、候选方案、约束。

## Decision（决策）

选择了什么。一句话可执行结论，细节指向 wiki / records。

## Consequences（后果）

带来的好处、代价与后续约束；被放弃方案的残留风险。
```

## 索引

| ADR | 决策 | 状态 |
|---|---|---|
| [0001](./0001-local-first-rdb-source-of-truth.md) | 本地优先，RDB 为唯一事实源 | Accepted |
| [0002](./0002-webdav-sync-lww-tombstone.md) | WebDAV 为主同步通道，ETag 增量 + LWW | Accepted |
| [0003](./0003-snapshot-local-never-synced.md) | 正文快照仅存本机，不参与同步 | Accepted |
| [0004](./0004-soft-delete-tombstone-no-resurrect.md) | 软删除 30 天 + 墓碑防复活 | Accepted |
| [0005](./0005-state-management-v2.md) | 状态管理 V2，桌面卡片例外 V1 | Accepted |
| [0006](./0006-zero-runtime-dependencies.md) | 零第三方运行时依赖 | Accepted |
| [0007](./0007-single-hap-module.md) | 单 HAP 模块，不拆 HAR/HSP | Accepted |
| [0008](./0008-paper-minimal-visual.md) | 极简纸感黑白视觉方向 | Accepted |
