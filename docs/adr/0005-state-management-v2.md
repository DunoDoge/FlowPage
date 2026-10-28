# ADR-0005: 状态管理 V2，桌面卡片例外 V1

- 状态：Accepted
- 日期：2026-10-26（补记：原决策于 2026-10-20 工程骨架期）

## Context（背景）

新工程无历史包袱，ArkUI 提供两代状态管理：V1（`@Component` + `@State`/`@Prop` 等，官方已停止演进）
与 V2（`@ComponentV2` + `@ObservedV2`/`@Trace`/`@Local`/`@Param`/`@Event`/`@Monitor`，细粒度依赖追踪）。
候选：全 V1（保守、资料多）、全 V2、混用。唯一的外部约束是 FormKit 桌面卡片对 V2 的支持不完整，
卡片只能用 V1 `@Component` + `@LocalStorageProp`。

## Decision（决策）

主 UI 全部使用状态管理 V2 装饰器；**仅** `entry/src/main/ets/widget/pages/` 的桌面卡片使用 V1
`@Component` + `@LocalStorageProp`（FormKit 约束，无法避免）。同一组件内不混用两代装饰器。

## Consequences（后果）

- 细粒度刷新，首页长列表与阅读页大文档的更新成本可控。
- V2 的 `@Local`/`@Param` 语义更严格（不可变参数等），写法约束由 AGENTS.md 代码约定承担。
- 卡片目录成为 V1 飞地，代理与新代码不得以卡片写法为参照反推主 UI 写法。
- 若 FormKit 未来补齐 V2 支持，可单点迁移卡片目录，不影响主 UI。
