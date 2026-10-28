# Proposal

## Why

现在时事实被复制到多处导致系统性漂移：同一「测试用例数」在 7 个位置出现 4 个数值（28 / 106 / 119 / 130），`docs/README.md` 的「当前状态」停留在 2026-10-21，而代码已前进 34 个提交；变更工作流半途而废（`openspec/` 空脚手架与 `spec/` 一次性 ad-hoc 双轨并存）；决策上下文散落（「已锁定决策」表是无编号 ADR，「双槽延迟销毁否决」等理由埋在 AGENTS.md 叙述里）；`engineering/` 与 `wiki/` 内容重叠且 02 已事实历史化。

## What Changes

- **时态分层 + 单一事实源**：`AGENTS.md` 成为唯一「现在时」速查（易变数字只活在这一处）；`docs/README.md` 删除「当前状态」「方案速览」「已锁定决策」「后续待决」等与 AGENTS.md 重复的段落，退化为纯索引；`wiki/` 速览表不再复制易变数字。
- **新增 `docs/adr/`**：轻量编号决策记录（Status/Context/Decision/Consequences），append-only；种子 8 条已锁定/埋没的方向性决策（同步底座、RDB SSOT、快照不同步、墓碑语义、状态管理 V2、零第三方依赖、单 HAP、视觉方向）。性能调优参数不 ADR 化，留在 AGENTS.md 约束段与 records。
- **统一变更工作流**：`spec/reader-perf-round3` 收编进 `openspec/changes/archive/`，删除 `spec/` 目录与 `spec/feature.json`；今后功能变更一律走 OpenSpec change 流程。
- **`openspec/config.yaml` 填充**：把 AGENTS.md 中的硬约束（hvigorw 而非 devecocli、ArkTS 严格子集、零依赖、不主动 commit 等）灌入 `context` 与 `rules`，使 spec/plan/tasks 生成自带项目约束。
- **`engineering/` 退役**：01-tech-design 的选型理由归入 ADR、架构描述已由 wiki 覆盖；02-implementation-plan 移入 `records/06-implementation-plan.md` 加时效头；目录整体移除，引用链接全量更新。
- **AGENTS.md 瘦身定界**：保持单文件入口（代理只读一个文件），职责收敛为「约束 + 速查 + 指针」；长文叙事与证据细节归 wiki/records，AGENTS.md 只留指针。

## Capabilities

### New Capabilities
- `docs-governance`: 文档体系治理规则——时态分层（现在时/过去时/将来时各有唯一归宿）、单一事实源（易变事实只在 AGENTS.md）、决策记录（编号 ADR、append-only）、变更工作流（功能变更走 OpenSpec change，落地归档）。

### Modified Capabilities

（无——`openspec/specs/` 目前为空，本能力是首个。）

## Impact

- **纯文档变更**：不触碰 `entry/` 源码、构建配置与运行时行为；`hvigorw assembleHap` 与 codelinter 结果不受影响。
- **文件移动/删除**：`engineering/` 两个文件（git mv 保留历史）、`spec/` 整目录、`docs/README.md` 大幅删段、`AGENTS.md` 局部重写；全仓库 markdown 内链需要一次全量校对。
- **工具链**：`openspec/config.yaml` 从模板变为生效配置；后续所有变更的规划产物会自动携带项目约束。
- **工作习惯**：此后每次代码冲刺需同步维护 AGENTS.md（唯一同步点，替代过去的三处）。
