# docs-governance Specification

## Purpose

规定 FlowPage 文档体系的治理规则：每类信息按时态有唯一归宿，易变的现在时事实只在 AGENTS.md 维护一处，方向性决策以编号 ADR 沉淀，功能变更统一走 OpenSpec change 流程。

## Requirements

### Requirement: 现在时事实单一事实源

易变现在时事实（测试套件/用例数、性能毫秒数、内存指标、门禁状态、功能完成度清单）SHALL 只在 `AGENTS.md` 维护数值；`docs/` 下的现行文档（README 索引、wiki）SHALL 以链接或文字指向代替复制数值；`records/`、`quality/` 中的历史快照不受此限，但 MUST 带时效说明。

#### Scenario: 检索无重复断言

- **WHEN** 在 `AGENTS.md` 之外的现行文档（docs/README.md、docs/wiki/）中检索测试用例数、性能耗时、VmRSS 等易变数字
- **THEN** 不出现无时效标注的数值断言；此类数字仅可在带时效头的历史快照（records/、quality/）中出现

#### Scenario: 代码冲刺后单点同步

- **WHEN** 一次代码冲刺改变了易变事实（如测试数从 130 增至 140）
- **THEN** 仅需更新 `AGENTS.md` 一处，`docs/README.md` 与 wiki 无需修改即保持正确

### Requirement: 文档按时态分层归宿

文档 SHALL 按时态各有唯一归宿：现在时速查 = `AGENTS.md`；现在时详解 = `docs/wiki/`；过去时执行日志 = `docs/records/` 与 `docs/quality/`（append-only）；过去时决策 = `docs/adr/`；将来时变更 = `openspec/changes/`。`docs/README.md` SHALL 为纯索引，不含当前状态断言。

#### Scenario: 索引纯化

- **WHEN** 阅读 `docs/README.md`
- **THEN** 只见目录结构与文档索引，「当前状态」「方案速览」「已锁定决策」「后续待决」等状态性段落已移除并指向 `AGENTS.md` 或 `docs/adr/`

#### Scenario: 历史快照不回改

- **WHEN** `records/`、`quality/` 中某文件已成历史
- **THEN** 后续修改仅限追加新批次、补时效标注或修正失效路径，不回改既有结论正文

#### Scenario: engineering 目录退役

- **WHEN** 本变更落地后检查 `docs/` 目录
- **THEN** `engineering/` 不存在：01-tech-design 的选型理由由 ADR 承接、架构描述由 wiki 承接，02-implementation-plan 以时效头快照形式移入 `records/`

### Requirement: 方向性决策以 ADR 记录

方向性技术与产品决策 SHALL 以编号 ADR（`docs/adr/NNNN-<slug>.md`，Status/Context/Decision/Consequences 四段）记录；ADR 目录 append-only：MUST NOT 删除或改写已发布的 ADR，推翻旧决策 MUST 用 `Superseded by ADR-NNNN` 标注。性能调优参数与实现细节不进 ADR。

#### Scenario: 新决策落档

- **WHEN** 做出新的方向性决策（如更换同步底座、引入第三方依赖）
- **THEN** `docs/adr/` 新增下一个连续编号的 ADR 文件，四段齐全

#### Scenario: 决策被推翻

- **WHEN** 后续决策替代某条旧决策
- **THEN** 旧 ADR 的 Status 改为 `Superseded by ADR-NNNN` 并保留原文，新 ADR 的 Context 引用旧编号

#### Scenario: 种子决策迁移完成

- **WHEN** 本变更落地后检查 `docs/adr/`
- **THEN** 存在不少于 8 条种子 ADR，覆盖：本地优先与 RDB 唯一事实源、WebDAV 同步底座（LWW+墓碑）、正文快照本地保留不参与同步、软删除 30 天与墓碑不复活语义、状态管理 V2（卡片例外 V1）、零第三方运行时依赖、单 HAP 无多模块、极简纸感黑白视觉方向

### Requirement: 功能变更走 OpenSpec 工作流

功能变更 SHALL 通过 OpenSpec change（proposal / specs / design / tasks）规划与实施，完成后归档至 `openspec/changes/archive/`，结论吸收进 `AGENTS.md` 与 wiki；仓库根的 `spec/` 目录 SHALL NOT 存在。

#### Scenario: 旧 spec 目录收编

- **WHEN** 本变更落地后检查仓库根
- **THEN** `spec/` 目录与 `spec/feature.json` 不存在，`openspec/changes/archive/reader-perf-round3/` 下可找到原三件套（spec/plan/tasks）

#### Scenario: 新变更自带项目约束

- **WHEN** 为新功能运行 `openspec instructions` 生成规划指引
- **THEN** 返回的 context/rules 携带项目硬约束（SDK 自带 hvigorw 而非 devecocli、ArkTS 严格子集、零第三方运行时依赖、不主动 commit/push）

### Requirement: AGENTS.md 职责收敛

`AGENTS.md` SHALL 限于「约束 + 速查 + 指针」三类内容，保持代理与开发者的单文件入口；超出资查颗粒度的长文叙事与证据细节 SHALL 位于 wiki 或 records，`AGENTS.md` 至多保留一行指针。

#### Scenario: 单文件满足速查

- **WHEN** 代理或开发者需要构建命令、验证门禁、架构速览、代码红线
- **THEN** `AGENTS.md` 单文件即可满足，关键操作无需跳转其他文档

#### Scenario: 细节外置

- **WHEN** `AGENTS.md` 中某段落属于长篇论证或历史证据（如多轮性能复测记录）
- **THEN** 该内容位于 wiki/records，`AGENTS.md` 只留结论性行与指向链接
