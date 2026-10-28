# ADR-0007: 单 HAP 模块，不拆 HAR/HSP

- 状态：Accepted
- 日期：2026-10-26（补记：原决策于 2026-10-20 工程骨架期）

## Context（背景）

HarmonyOS 工程可拆分 HAP/HAR/HSP 多模块。候选：单 HAP；按层拆 HAR（如 core 单独成库）；多端形态
拆分模块。本项目单团队开发、单交付物、无跨应用复用诉求；分层已由目录结构（`core/`、`repository/`、
`components/`、`pages/`）表达，模块化收益只有构建隔离，代价是依赖配置与发布复杂度。

## Decision（决策）

仅保留 `entry` 一个 HAP 承载全部代码：无 HAR、无 HSP、无多端模块。架构分层用包内目录表达，
禁止跨层直连的约束由 AGENTS.md 与代码约定承担（UI 只依赖 `FlowRepository`）。

## Consequences（后果）

- 构建、签名、安装、测试包产物路径全部单一确定（`entry/build/default/outputs/...`）。
- 页面路由极简（`main_pages.json` 仅 2 个路由），标签/同步/设置等经组件切换。
- 若未来出现第二个交付物（如穿戴端、元服务），需新开 ADR 重新评估拆分。
