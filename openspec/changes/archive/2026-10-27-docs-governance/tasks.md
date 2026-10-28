# Tasks

纯文档变更：全程不触碰 `entry/`、构建配置；工具链只需 git 与 grep；完成后以 Phase 6 全量校验收口。路径均为仓库根（/storage/Users/currentUser/Documents/Coding/FlowPage）相对路径。

## 1. ADR 体系建立

- [x] 1.1 创建 `docs/adr/README.md`：ADR 机制说明（编号规则、四段模板、supersede 流程、粒度红线——方向性决策才进 ADR，性能参数/实现评估不进）与种子决策索引表；验证：文件存在且含模板代码块
- [x] 1.2 按 design D3 清单创建 8 条种子 ADR（0001-local-first-rdb-source-of-truth 至 0008-paper-minimal-visual），内容取材 docs/README「已锁定决策」、engineering/01 选型表、AGENTS.md 散落理由，补记日期标注原决策时间；验证：`ls docs/adr/` 见 9 个文件（README + 8 ADR），每条四段齐全、状态 Accepted
- [x] 1.3 抽查 ADR-0002（WebDAV LWW+墓碑）：Context 含「分布式 KV 降级为 V1.1」的边界理由，Decision 与 AGENTS.md「项目快照」表述一致；验证：人工比对两处无矛盾

## 2. 目录迁移（先建后拆，git mv 保历史）

- [x] 2.1 `git mv docs/engineering/02-implementation-plan.md docs/records/06-implementation-plan.md`，文首加时效头（历史快照声明 + 指向 records/02–05 与 AGENTS.md）；验证：`git status` 显示 renamed，新文件头部含时效说明
- [x] 2.2 `git mv spec/reader-perf-round3 openspec/changes/archive/reader-perf-round3`，随后 `git rm spec/feature.json` 并删除空 `spec/` 目录；在 archive/ 下补 README 一行注明「Kiro 风格产物，2026-10-24–26，冻结不再维护」；验证：仓库根无 `spec/`，archive 下三件套 + README 齐全
- [x] 2.3 `git rm docs/engineering/01-tech-design.md` 并删除空 `engineering/` 目录（拆解去向已在 Phase 1 ADR 与既有 wiki 落实）；验证：`docs/` 下无 `engineering/`

## 3. 现在时文档定界重写

- [x] 3.1 重写 `docs/README.md` 为纯索引：删除方案速览/当前状态/已锁定决策/明确边界/后续待决/技术基线六段，索引表加 `adr/` 与 `openspec/` 行、删 `engineering/` 行，时效约定改写为时态分层说明；验证：全文 grep 无「当前状态」「已锁定」状态性小节，索引表每行的链接文件存在
- [x] 3.2 方案速览/明确边界中 PRD 未覆盖的要点并入 `docs/product/01-prd.md`（对照后仅补缺，不重写既有章节）；验证：PRD 覆盖原两段的全部信息点（逐条对照清单留档）
- [x] 3.3 重写 `AGENTS.md`：保留全部约束行原文与项目快照表，「文档地图」瘦身为指向 docs/README 与 docs/adr/ 的指针，新增「待决事项」小节（原后续待决 4 条），性能约束段只留结论行 + 指向 records 的复测记录指针；验证：新旧逐段 diff，确认无任何约束行丢失（diff 中删除行仅限指针化与重复段）
- [x] 3.4 `docs/wiki/` 去易变数字：wiki/README.md 项目速览表删「测试」行的数值（改指 AGENTS.md），grep 全部 wiki 文件中无时效头的用例数/耗时毫秒/VmRSS 数值断言并改为指针；验证：`grep -rn "130\|119\|用例" docs/wiki/` 仅剩指向 AGENTS.md 的引用或带时效标注的历史引述
- [x] 3.5 修复 records/ 与 quality/ 内指向 `engineering/`、`spec/reader-perf-round3` 的死链，改指 records 内部或 openspec/changes/archive/；验证：`grep -rn "engineering/" docs/ AGENTS.md README.md` 与 `grep -rn "spec/reader" docs/ AGENTS.md README.md` 均无命中

## 4. OpenSpec 配置生效

- [x] 4.1 按 design D6 填充 `openspec/config.yaml`（context ≤15 行 + 四类 artifact rules + operations guidance），删除模板注释；验证：`openspec context --json` 正常返回且内容携带新约束，YAML 可解析

## 5. 全量校验（integration）

- [x] 5.1 死链与残留终检：全仓 markdown 内链逐一存在（脚本化 grep 相对路径目标），无 `engineering/`、根 `spec/` 残留引用；验证：校验脚本 0 命中
- [x] 5.2 单一事实源终检：`docs/README.md`、`docs/wiki/`、`docs/product/`、`docs/design/` 中无无时效头的易变数值断言（用例数、性能中位数、VmRSS）；验证：grep 清单留档 0 命中
- [x] 5.3 变更面终检：`git diff --stat`（对 main）仅含 docs/、openspec/、AGENTS.md、spec/（删除）；`openspec status --change docs-governance` 与 `openspec validate docs-governance` 通过；验证：两者输出留档

## Workflow follow-up

- 人工通读新 AGENTS.md 一遍（Risk D2 缓解），确认代理可单文件完成构建/校验操作。
- 满足评审要求后归档：`openspec archive docs-governance` → specs/ 生成首个能力规格 `docs-governance`。
- 归档后按 config.yaml 的 archive guidance 检查 AGENTS.md 是否需要吸收本变更结论（预期：文档地图指针已覆盖，无额外更新）。
