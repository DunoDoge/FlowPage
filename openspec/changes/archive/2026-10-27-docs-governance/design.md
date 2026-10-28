# Design

## Context

现状：`docs/` 五分类 + wiki 共 ~4,600 行；`AGENTS.md`（143 行）是事实上最新最准的现在时文件；`docs/README.md` 的状态性段落停在 2026-10-21；`openspec/` 脚手架空置，`spec/`（Kiro 风格 spec/plan/tasks）跑通过 reader-perf-round3 一轮；`engineering/` 与 wiki 重叠。动机见 proposal.md。

约束：纯文档变更，不触碰 `entry/` 与构建配置；git mv 保留历史；全程不 commit/push（AGENTS.md 约定）；文档以中文为主。

## Goals / Non-Goals

**Goals:**

- 每个易变事实只有一个维护点（AGENTS.md），消灭「测试数 7 处 4 值」式漂移。
- 决策（含理由）可追溯：编号 ADR，append-only，supersede 链完整。
- 变更工作流单一入口：OpenSpec；旧 `spec/` 冻结收编。
- `openspec/config.yaml` 从模板变为生效的项目约束注入。

**Non-Goals:**

- 不引入文档站点/静态生成器/SSG（Diátaxis 全量重组、Arc42、C4 均否决——单人 + AI 协作，重工具收益为负）。
- 不为存量 records/quality 补写 ADR 之外的追溯结构；历史快照保持冻结。
- 不改动 `entry/` 源码、测试与构建产物；`hvigorw assembleHap` 结果必须与变更前一致（不触发重建即无影响）。
- 不做多语言/i18n 文档层。

## Decisions

### D1 目录形态：按时态分层归宿

```
AGENTS.md              唯一「现在时」速查：约束 + 速查表 + 指针
docs/
 ├─ README.md          纯索引（目录表 + 阅读指引，无状态断言）
 ├─ product/           产品基线（不动）
 ├─ design/            设计基线（不动）
 ├─ adr/               新增：编号决策记录（append-only）
 ├─ wiki/              现在时详解（去易变数字）
 ├─ quality/           过去时·走查（append-only，不动）
 └─ records/           过去时·批次日志（append-only；吸收 engineering/02）
openspec/
 ├─ config.yaml        填充 context/rules
 ├─ changes/           将来时·进行中变更（本 change 即首个）
 │   └─ archive/       过去时·已完成变更（吸收 spec/reader-perf-round3）
 └─ specs/             能力规格持久层（本 change 归档后生成首个）
```

`engineering/` 整目录消失。

### D2 AGENTS.md：保持单文件入口，职责收敛为「约束 + 速查 + 指针」

- 保留全部约束行原文（构建命令、性能红线、代码红线、ArkTS 规则）——这些是代理操作手册的核心，一个字不删。
- 「项目快照」表保留并成为易变数字唯一载体（测试数等）。
- 「文档地图」段瘦身：指向 `docs/README.md` 索引与 `docs/adr/`，不再逐文件罗列。
- 新增紧凑「待决事项」小节（原 docs/README「后续待决」4 条迁入）。
- 性能约束段保留（那是约束不是叙事），但多轮复测的论证细节留 records/quality，只留结论行。

备选否决：拆成 `AGENTS.md`（操作）+ `ARCHITECTURE.md`（事实）两个文件——代理需要多读一个文件，且「事实」与「约束」边界模糊，必然互相渗透再次漂移。

### D3 ADR：轻量模板、连续编号、只收方向性决策

模板（中文，四段）：

```markdown
# ADR-NNNN: <标题>

- 状态：Accepted | Superseded by ADR-NNNN
- 日期：YYYY-MM-DD（补记须注明原决策时间）

## Context（背景）
## Decision（决策）
## Consequences（后果）
```

种子 8 条（编号即创建顺序）：`0001-local-first-rdb-source-of-truth`、`0002-webdav-sync-lww-tombstone`、`0003-snapshot-local-never-synced`、`0004-soft-delete-tombstone-no-resurrect`、`0005-state-management-v2`、`0006-zero-runtime-dependencies`、`0007-single-hap-module`、`0008-paper-minimal-visual`。内容取材：docs/README「已锁定决策」表 + engineering/01 选型理由 + AGENTS.md 散落的理由（如分布式 KV 降级 V1.1 的边界约束）。

粒度红线：性能调优参数（INITIAL_BLOCKS、心跳口径）、实现选型评估（LazyForEach 否决、双槽延迟销毁否决）**不进 ADR**——它们留在 AGENTS.md 约束段、wiki 与 change archive。备选否决：全量 ADR 化——粒度过细，写的人负担大，读者反而要在几十个 ADR 里找方向。

### D4 `spec/` 收编：冻结归档，不格式转换

`git mv spec/reader-perf-round3 openspec/changes/archive/reader-perf-round3`，保留 spec.md/plan.md/tasks.md 原文件名；在 archive 目录加一行 README 说明「Kiro 风格产物，2026-10-24–26，冻结不再维护」；删除 `spec/feature.json` 与空目录。

备选否决：转换成 OpenSpec 四件套格式——历史产物重写无收益，且 tasks.md 里的执行批注（环境变更记录等）是珍贵证据，原样冻结最诚实。

### D5 `engineering/` 退役，不留守指针页

- 01-tech-design（578 行）：§1 选型表理由 → 各 ADR 的 Context/Decision；架构/数据模型/同步协议描述 → wiki 01/03/04 已覆盖（10-25 校准），删除；权限/测试 → wiki 05 与 AGENTS.md 已覆盖。
- 02-implementation-plan（219 行）：`git mv` 至 `docs/records/06-implementation-plan.md`，文首加时效头（历史快照，结论已被 records/02–05 与 AGENTS.md 取代）。

备选否决：保留瘦身版 tech-design 与 wiki 并存——两份「现在时」架构描述必漂移，这正是本变更要消灭的形态。

### D6 `openspec/config.yaml` 填充

```yaml
schema: spec-driven

context: |
  HarmonyOS ArkTS 单 HAP（entry），API 26，状态管理 V2，phone/tablet/2in1。
  零第三方运行时依赖；RDB 为唯一事实源，WebDAV（LWW+墓碑）同步。
  构建门禁：SDK 自带 hvigorw（>=7.26.8）assembleHap + codelinter -c code-linter.json5；
  devecocli build 不支持本工程 modelVersion 26.0.0，禁止使用。
  ArkTS 严格子集：禁 any、as 断言、结构化类型、动态属性访问。
  文档中文为主；AGENTS.md 是唯一现在时事实源；未经明确要求不 commit/push。

rules:
  proposal:
    - 中文撰写；不复制 AGENTS.md 约束原文，只引用
  specs:
    - WHEN/THEN 标记保留英文，内容中文
  design:
    - 每个决策给出备选方案与否决理由
  tasks:
    - 任务路径写仓库根路径；涉代码任务必须以 check_ets_files + hvigorw assembleHap 收尾
    - 纯文档变更以全量内链 grep 校对收尾

operations:
  apply:
    guidance:
      - 完成后按 AGENTS.md 更新易变事实（若有）
  archive:
    guidance:
      - 归档后把影响速查事实的结论吸收进 AGENTS.md
```

context 控制在 ~10 行：只放代理无法从代码推断、且会改变规划/实施行为的约束。

### D7 `docs/README.md` 索引化

删除六个状态性段落：方案速览、当前状态、已锁定决策、明确边界、后续待决、技术基线。去向：方案速览/明确边界中 PRD 未覆盖的要点并入 `product/01-prd.md`；已锁定决策 → ADR；后续待决 → AGENTS.md 待决小节；当前状态/技术基线 → AGENTS.md 项目快照（已有）。保留：标题一句话、文档时效约定（改写为时态分层说明）、目录索引表（+ adr/、openspec/ 行，− engineering/ 行）。

## Risks / Trade-offs

- [AGENTS.md 重写丢失关键约束，代理行为退化] → 重写逐段 diff：约束行原文保留，只动指针与重复段；完成后人工通读一遍新文件。
- [wiki 去数字后单读性下降] → 只把「易变数值」改指针（测试数、耗时中位数、VmRSS），结构性事实（包名、六表、模块布局）保留；接受跳转 AGENTS.md 的轻成本。
- [archive 中 Kiro 格式与 OpenSpec 格式混淆] → archive/README 注明来源与冻结状态。
- [records/02、03 内部链接指向已删除的 engineering/ 路径] → 迁移后全量 `grep -rn "engineering/"` 并把死链改指 records 内部或 wiki；records 正文结论不回改，仅允许修链接路径（符合 append-only 例外：失效路径标注）。
- [config.yaml context 膨胀稀释注意力] → 硬上限 15 行，超出必须删减。
- [规则立了但无人执行，治理退回原状] → 把「AGENTS.md 单点同步」写进 D6 的 archive guidance；每次 change 归档时强制走一遍。

## Migration Plan

顺序执行（先建新、后拆旧、最后校验；任一步可 `git checkout` 回滚，纯文档无状态迁移）：

1. 建 `docs/adr/`（模板 + 8 种子）。
2. `git mv` 两次：engineering/02 → records/06；spec/reader-perf-round3 → openspec/changes/archive/。
3. 退役 engineering/01 与 `spec/` 残余。
4. 重写 AGENTS.md（定界）、索引化 docs/README.md、去重 wiki 速览、PRD 补要点。
5. 填充 openspec/config.yaml。
6. 全量校验：grep 死链（engineering/、spec/reader-perf）、易变数字残留（wiki 中无时效头的用例数/毫秒数）、`openspec validate docs-governance`；`git diff --stat` 确认只动 docs/、openspec/、AGENTS.md、spec/（删除）。
