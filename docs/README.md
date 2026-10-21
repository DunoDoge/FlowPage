# 流笺 FlowPage · 软件开发文档

> 版本：v1.0 · 2026-10-21
> 状态：批次 A/B/C 主体已实现，走查问题 N1–N11 已修复并验证；当前实现状态以本文件「当前状态」为准，历史结论见 `records/`

## 文档时效约定

`product/`、`design/`、`engineering/` 记录产品基线、设计规范与技术方案，其中标注「规划 / V1.1」的能力尚未落地；
`quality/`、`records/` 是执行过程快照，文首有时效说明，不代表当前实现。判断代码现状时以源码、`wiki/` 和本文件为准。

## 文档结构

`docs/` 按用途分为五类，文件名统一为「两位序号 + 英文 kebab-case」；`wiki/` 是独立的 Code Wiki，不参与编号。

| 目录 | 用途 | 维护方式 |
|---|---|---|
| [product/](./product/) | 产品定位、用户、功能范围与业务规则 | 需求变化时更新 |
| [design/](./design/) | 设计 token、布局断点、组件与动效规范 | 视觉变化时更新 |
| [engineering/](./engineering/) | 技术方案、实施计划与验收标准 | 方案变化时更新 |
| [quality/](./quality/) | 走查清单与缺陷修复记录 | 每轮走查追加 |
| [records/](./records/) | 实现、复审与修复批次的历史记录 | 只追加；仅补时效标注与失效路径 |
| [wiki/](./wiki/) | 分层 Code Wiki：架构、UI、数据、同步与服务、构建运行 | 随代码同步更新 |

## 文档索引

| 文档 | 内容 | 适合谁读 |
|---|---|---|
| [product/01-prd.md](./product/01-prd.md) | 定位、竞品、用户、场景、差异化、功能范围、业务规则 | 产品 / 评审 |
| [design/01-ui-spec.md](./design/01-ui-spec.md) | 设计 token、三断点布局、组件与页面规格、动效与无障碍 | 设计 / 前端 |
| [engineering/01-tech-design.md](./engineering/01-tech-design.md) | 架构、数据模型、同步协议、鸿蒙能力接入、权限与测试 | 开发 / 架构 |
| [engineering/02-implementation-plan.md](./engineering/02-implementation-plan.md) | 批次、里程碑、验收标准、测试用例、演示脚本 | 项目管理 / 验收 |
| [quality/01-walkthrough-checklist.md](./quality/01-walkthrough-checklist.md) | 手机 / 2in1 / 同步走查步骤 | 测试 |
| [quality/02-walkthrough-issues.md](./quality/02-walkthrough-issues.md) | 真机走查问题、定位与修复验收 | 下一会话 |
| [records/01-implementation-log.md](./records/01-implementation-log.md) | 已实现功能、真机验证结果、偏差与待办 | 评审 / 验收 |
| [records/02-code-review.md](./records/02-code-review.md) | 功能完成度、代码质量、P0/P1 问题、两批工作清单与新会话提示词 | 开发 / 评审 |
| [records/03-review-follow-up.md](./records/03-review-follow-up.md) | 第二轮复审结论的三子代理复核、确认问题清单、测试/文档修正与第三批提示词 | 开发 / 评审 |
| [wiki/README.md](./wiki/README.md) | 分层 Code Wiki：架构、UI、数据、同步与服务、构建运行 | 开发 / 维护 |

## 方案速览

- **一句话**：把散落在浏览器、微信和各设备里的链接，三秒收进一册可离线、可搜索、可同步的「笺」。
- **核心闭环**：收 → 理 → 找 → 用。
- **差异化**：
  1. 一笺三态（链接 + 离线快照 + 摘录），对抗「收藏即吃灰」；
  2. 鸿蒙原生收笺（分享扩展 / 粘贴控件；碰一碰为 V1.1 规划）；
  3. 时光轴 + 每日笺，让旧收藏重新流动；
  4. 本地优先 + 自己的云（WebDAV 已实现；分布式数据为 V1.1 规划）。
- **视觉**：极简纸感黑白，米白纸面、墨色文字、发丝线，无彩色、无渐变、无投影。
- **同步**：本地 RDB 为唯一事实源；WebDAV 为主通道（已实现），分布式 KV 为同账号局域网增强通道（V1.1 规划）；LWW + 冲突记录。
- **收笺入口**：分享扩展、HTML 导入、粘贴控件（已实现）；碰一碰/隔空传送、内置浏览器（V1.1 规划）。

## 当前状态

- 批次 A（单机核心）、批次 B 的 WebDAV 与已落地系统能力（接续、卡片注册）、批次 C 的隐私/阅读增强已完成并通过真机验证；内置浏览器/阅读模式、分布式 KV、碰一碰仍未实现。
- 已验证：分享扩展、HTML 导入、粘贴控件、标签/搜索、深色、一多、WebDAV 双向同步（本地测试服务 + 真实坚果云）、跨设备下载、HUKS 凭据加密、失效链接检测、阅读字号、自动快照开关、阅读状态、冲突记录 UI、SQL 分页与搜索高亮。
- 待完成：分布式 KV、App Linking 域名、碰一碰实测、内置浏览器/阅读模式、WebDAV 端到端加密、冲突字段级合并、服务卡片人工添加验收、键盘完整路径验收、应用内隐私说明页；favicon 已明确不做。
- 2026-10-21 复审：P0 4 项一致性问题（标签变更不同步、清空语义、快照文件生命周期、同步状态误报）与 P1 验收缺口已在同日第一/第二批收口。详见 [records/02-code-review.md](./records/02-code-review.md) §10。
- 2026-10-21 第二轮复审 + 三子代理复核：第一/二批修复逐条核实有效；4 项 P1 与 5 项 P2 已于第三/第四批修复（T3.1–T3.8），详见 [records/03-review-follow-up.md](./records/03-review-follow-up.md)。
- 测试：10 个套件 / 81 个用例；模拟器 81/81 通过，手机主功能 77/77 通过（81 版因锁屏未复跑），见 [quality/01-walkthrough-checklist.md](./quality/01-walkthrough-checklist.md) §5。
- 走查问题：N1–N11 已全部修复并验证，其中 N4 完成连接 207、手机上传 6 条、2in1 下载 6 条；N10/N11 修复重复同步与首页即时刷新。见 [quality/02-walkthrough-issues.md](./quality/02-walkthrough-issues.md)。
- 背景与早期实现细节见 [records/01-implementation-log.md](./records/01-implementation-log.md)（历史快照）。

## 已锁定决策

| 决策 | 结论 |
|---|---|
| 同步底座 | 本地优先；WebDAV 已实现，分布式数据为 V1.1 规划 |
| 收笺入口 | 已实现分享面板、HTML 导入、剪贴板；碰一碰、内置浏览器为 V1.1 规划 |
| 设备形态 | phone / tablet / 2in1 一多并重 |
| 视觉方向 | 极简纸感黑白 |
| 交付节奏 | 先文档评审，确认后开发 |
| 包名 | `com.dunodoge.flowpage` |

## 明确边界

- 鸿蒙沙箱**无法读取其他浏览器书签库**；「浏览器书签同步」通过 HTML 导入 + 分享收笺 + 粘贴实现；内置浏览器为 V1.1 规划。
- V1.0 不包含账号体系、社交、云托管、浏览器扩展、Android/iOS。
- 碰一碰、App Linking、分布式同步需要第二台设备与真实域名；应用接续已完成双机验证（仅恢复当前书签，不恢复滚动位置）。

## 后续待决

1. 是否提供第二台鸿蒙设备，用于碰一碰、分布式与更多跨端验收。
2. 是否配置 App Linking 域名并完成 `/.well-known/applinking.json` 校验。
3. 是否在 V1.1 落地内置浏览器与正文阅读模式。
4. 服务卡片与键盘完整路径的人工验收由谁在何时完成。

## 技术基线

- HarmonyOS 6.0 / API 26，Stage 模型，ArkTS + ArkUI
- 状态管理 V2，`Navigation` + `NavPathStack`
- RDB `flowpage.db`（6 表 + 7 索引）+ preferences + 文件快照
- 零第三方运行时依赖
- 每个 `.ets` 文件优先跑快速 ArkTS 检查；阶段末用 `hvigorw clean assembleHap`（`devecocli` 内置 hvigor 不支持本工程 `modelVersion 26.0.0`）
