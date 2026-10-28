# 流笺 FlowPage · 代码复审与下一步计划

> **时效说明**：本文是 2026-10-21 第一轮复审快照，文中 30/63 用例与「未实现」清单均为当时状态。
> 第一至第四批已收口，收尾批次后为 10 套件 / 81 用例；当前状态见 [docs/README](../README.md) 与
> [records/03-review-follow-up.md](./03-review-follow-up.md)。

- 复审日期：2026-10-21
- 复审范围：`entry/src/main/ets` 全量源码、`entry/src/ohosTest`、构建配置、`docs/`
- 代码基线：`a2eb04c`（工作区另含未提交的 `AGENTS.md`、`README.md`、`docs/wiki/`）
- 复审结论：**内部 Alpha 可用，不建议直接按 1.0 发布**
- 关联文档：[AGENTS.md](../../AGENTS.md)、[wiki/README.md](../wiki/README.md)、[records/01-implementation-log.md](./01-implementation-log.md)、[quality/02-walkthrough-issues.md](../quality/02-walkthrough-issues.md)

---

## 1. 总体判断

单机「收笺 → 整理 → 检索 → 阅读 → 回收站」主链路已经可用，WebDAV 主通道经过双端验证，同步可靠性设计（ETag、dirty、墓碑、LWW、失败映射）明显优于普通个人项目。

当前风险不在“缺页面”，而在数据一致性与验收缺口：

1. **标签重命名、合并、删除不会触发同步**，多端会长期不一致。
2. **「清空所有数据」不会清远端**，下次同步会把数据重新下载回来；也不清理正文快照文件。
3. **冲突表只写入、不展示**，PRD 的冲突恢复能力实际不可用。
4. **无障碍验收不达标**：辅助文字对比度低于 4.5:1，多个可点区域小于 44vp，键盘支持未覆盖。

估算完成度：

| 范围 | 完成度 | 说明 |
|---|---|---|
| V1.0 / P0 | 约 75–80% | 核心闭环可跑，存在一致性与验收缺口 |
| V1.1 / P1 | 约 45–50% | WebDAV 主通道可用；分布式、冲突 UI、阅读模式未做 |
| V1.2 / P2 | 刚起步 | 仅有 HUKS 凭据加密与链接检测的基础能力 |

---

## 2. 验证记录

| 项 | 结果 |
|---|---|
| `hvigorw clean` + `hvigorw assembleHap` | BUILD SUCCESSFUL（约 14.7s） |
| 构建告警 | 2 条 ArkTS WARN：卡片页 `@Entry` 无参数 |
| 静态检查 | `DEVECO_HOME` 未设置，`check_ets_files` 不可用；本轮以 hvigor 全量编译为准 |
| Hypium | 源码实际 **30 个用例**；`docs/records/01-implementation-log.md` 仍写 28 个，本轮未重跑设备测试 |
| 设备 | 复审时在线 2 台（手机 + 2in1），可做真机回归 |
| 代码规模 | 复审时 `entry/src/main/ets` 42 个 `.ets`，约 6.4k 行；`ohosTest` 5 个 `.ets` |
| 本轮构建（第一/第二批） | `hvigorw clean assembleHap` BUILD SUCCESSFUL；2 条桌面卡片 `@Entry` 无参数 WARN |
| 本轮设备测试 | 10 个套件 / **63 个用例全部通过**（HUAWEI Pura 70 / ADY-AL00，2026-10-21） |
| 本轮基准 | 1000 条搜索 **3–4ms**；10000 条搜索 **14ms**（热查询）；5000 条 HTML 导入 **6454–6973ms** |
| 本轮静态检查 | 本机 `codelinter` 缺少 HNP 自带 Node，未运行；以 hvigor 全量编译 + ArkTS 严格模式为准 |

---

## 3. 完成度矩阵

### 3.1 V1.0 / P0

| 模块 | 状态 | 主要缺口 |
|---|---|---|
| 首页流、搜索、筛选 | 完成 | 排序、搜索高亮、SQL 分页已落地；10k 热查询 17ms（Pura 70），见 docs/records/03-review-follow-up.md §3 |
| 手动/粘贴/分享收笺 | 基本完成 | 详情「分享」已改为原文 URL，深链改为复制动作；保存前仍无标题/站点预览 |
| HTML 导入 | 完成 | 预览/取消/失败清单/分批事务已落地；5000 条 6.6s（Pura 70），阈值放宽为 12s 保险线 |
| 详情阅读与编辑 | 完成 | 复制深链、标记未读、UNREAD→READING→READ + 30s 已读均已落地；正文按内容 key 分段渲染 |
| 标签管理 | 完成 | 改名/合并/删除只 touch 含源标签的书签并重建 `search_text`；重名自动合并；计数排除回收站 |
| 本地数据与导出 | 基本完成 | 清空语义已收口（保墓碑、删快照）；JSON 仍无导入入口，T20 未闭环 |
| 系统能力 | 基本完成 | 深色/一多/双卡片/接续/自定义深链可用；卡片未完成人工添加验收；无 App Linking HTTPS、碰一碰；无站点图标展示；键盘支持未验证 |
| 设置 | 完成 | 自动快照开关、导入预览/失败清单已落地；仍缺独立隐私说明与存储占用 |

### 3.2 V1.1 / P1

| 能力 | 状态 | 说明 |
|---|---|---|
| WebDAV 同步 | 完成 | ETag、dirty、墓碑、LWW、冲突 UI、HUKS 凭据、双端同步均具备；缺同步进度/取消与逐条重试入口 |
| 标签跨端一致性 | 完成 | 变更只 touch 源侧书签，避免误覆盖远端；`search_text` 同事务重建 |
| 冲突记录 UI / 字段级合并 | 部分完成 | 同步页可查看/恢复本地/采用远端；未做字段级合并 |
| 分布式 KV 通道 | 未实现 | 同步页明确标注「下一阶段接入」（`SyncPage.ets:297-310`） |
| 内置浏览器 / 阅读模式 / 滚动接续 | 未实现 | 目前只有纯文本快照 + 字号调节 |
| App Linking / 碰一碰 | 未实现 | 只有自定义 scheme；无 `applinking.json` 与域名校验 |
| 失效链接检测 | 基本完成 | 单条 HEAD/GET，无批量与定时检查 |
| WebDAV 端到端加密 | 未实现 | 当前只做了凭据静态加密 |

---

## 4. 问题清单

严重度定义：**P0** = 不修会导致数据不一致、用户误判或无法发布；**P1** = 影响验收或明显体验；**P2** = 可维护性、性能与体验优化。

### P0

| ID | 问题 | 证据 | 影响 |
|---|---|---|---|
| R1 | 标签变更不触发同步 | `BookmarkDao.ets:469-501` 只写 `tag/bookmark_tag`；`SyncPlanner.ets:10-15` 对非 dirty 且 ETag 相同的条目直接 SKIP | 重命名/合并/删除标签后，另一台设备永远看不到，直到该条因其他字段被编辑 |
| R2 | 标签重名会撞唯一索引 | `Database.ets:84`；`TagsPage.ets:41-51` 无 try/catch | 重命名到已有标签名时无提示，操作失败 |
| R3 | 「清空所有数据」语义不可靠 | `BookmarkDao.ets:503-509` 清 bookmark/tag/tombstone，但不清 conflict、不删快照；`SyncEngine.ets:136-154` 会从远端重新下载 | 用户以为清空，实际云端仍在，下次同步复活；设置页文案承诺删除快照但未做到 |
| R4 | 同步页「已连接」误报 | `SyncPage.ets:76-89` 保存配置后立即 `configured = true`，随后 401/403 也不回退 | 认证失败后顶部仍显示「已连接」 |

### P1

| ID | 问题 | 证据 | 影响 |
|---|---|---|---|
| R5 | 过期清理不删快照文件 | `BookmarkDao.ets:426-433`、`FlowRepository.ets:393-399` 只删数据库行 | 孤立 `.txt` 长期占用空间 |
| R6 | 导入无事务、无预览、无失败清单 | `FlowRepository.ets:444-488`；`SettingsPage.ets:65-73` 同步读取整文件 | 5000 条 F4 目标风险高；大文件卡 UI；失败 URL 只计数不导出 |
| R7 | 详情异步操作缺少 `try/finally` | `DetailContent.ets:115-155`、`274-303` | 异常后 `checking/busy` 永远为 true，按钮卡在“处理中” |
| R8 | 编辑一次拆成 4 次写库 | `DetailContent.ets:274-303` 调 title/note/excerpt/tags 四次 | 每次 `rev+1`、`notify()`，产生中间态同步和多次列表刷新 |
| R9 | 冲突记录不可见 | `BookmarkDao.ets:259-268` 无调用方 | PRD F15「冲突记录可恢复」无法验收 |
| R10 | 跨端丢失 `folderPath/source` | `SyncRecord.ets:6-27` 不含这两个字段；`FlowRepository.ets:158-181` 用远端记录整体覆盖 | 导入书签被远端更新后，HTML 导出的文件夹分组丢失 |
| R11 | 阅读状态未按 PRD 实现 | `DetailContent.ets:64-67` 直接 `UNREAD → READ`；`ReadState.READING` 未使用 | 无「阅读中/标记未读」，10.6 未达成 |
| R12 | 自动快照开关缺失 | `SnapshotStatus.OFF` 未使用（`Constants.ets:15-20`） | PRD 10.2 的「关闭自动保存快照」没有入口 |
| R13 | 无障碍不达标 | `color.json:29/35`；多个 28–34vp 可点区域（`StreamHome.ets:174-188`、`249-259`、`DetailContent.ets:590-596`、`SettingsPage.ets:269-281`） | 浅色辅助文字对比度约 2.41:1，深色约 3.73:1；触控目标不足 44vp；无键盘/读屏适配 |

### P2

| ID | 问题 | 证据 | 影响 |
|---|---|---|---|
| R14 | 搜索/列表扩展性不足 | `StreamHome.ets:67-79` 每次刷新全表 `listAll` + `summary` + 全量标签 | 10k 条验收风险；卡片快照也每次全量读取 |
| R15 | 长正文单 `Text` 渲染 | `DetailContent.ets:477-483` 最多 200KB 放一个 `Text` | 长文测量/滚动可能卡顿 |
| R16 | 标签计数含回收站 | `BookmarkDao.ets:451-455` 未过滤 `bookmark.deleted = 0` | 标签数字与筛选结果不一致 |
| R17 | 汇总口径不一致 | `FlowRepository.ets:217-237` 的 unread/starred 包含归档，首页筛选排除归档 | 设置/同步页数字与列表不一致 |
| R18 | 站点图标未展示 | `MetadataService.ets:184-189` 抓取 favicon/cover，UI 无 `Image` 消费 | PRD「自动站点图标」未落地 |
| R19 | 死代码与文档漂移 | `sync_state`、`deviceId`、`searchLimit`、`countConflicts`、`SnapshotStatus.OFF` 未使用；`docs/records/01-implementation-log.md` 写 28 个用例（实际 30）、仍提 `BrowserPage`；`docs/records/06-implementation-plan.md` 仍把 `devecocli build` 当门禁 | 后续维护者被误导 |
| R20 | `as` 断言与项目规范冲突 | 14 处 `as`，多为 `getContext`/`JSON.parse` 平台断言 | 与 `AGENTS.md`「禁止 as」不一致，需修代码或改规范 |

---

## 5. 第一批：正确性收口

目标：先消除会造成跨端不一致、数据误删、状态误报的问题。**建议 2–3 天。**

> 2026-10-21 完成：T1.1–T1.5 全部落地，自动化与人工验收记录见 §10。

- [x] **T1.1 标签变更同步**
  - 在 `BookmarkDao` 增加按标签批量触碰书签的能力：同事务内更新 `updated_at = now`、`rev = rev + 1`、`dirty = 1`。
  - `renameTag` / `mergeTags` / `deleteTag` 统一调用该能力；`deleteTag` 只解除关联，不删除书签。
  - 重命名撞名时直接合并到目标标签，或捕获唯一约束并给出中文提示。
  - `listTags` 关联 `bookmark.deleted = 0`，并考虑隐藏 0 计数标签。
  - 验收：设备 A 重命名/合并/删除标签 → 同步 → 设备 B 下载后标签一致；重名不崩溃。
  - 测试：新增 DAO/Repository 用例，断言 `dirty=1`、`rev+1`、远端 JSON 标签已更新。

- [x] **T1.2 明确「清空所有数据」语义**
  - 默认方案：定位为「只清本机」，设置页文案改为「清空本机数据，云端保留」，并提供二次确认说明。
  - `clearAll` 同时清理 `snapshots/`、`conflict`，并刷新卡片快照。
  - 若产品要求「连云端一起清」，改为为所有书签写墓碑并同步删除远端；不得只清本地。
  - 验收：清空后重启仍为空；若选择只清本机，下一次同步会恢复云端数据这一行为必须在文案中明示。
  - 测试：清空后快照目录为空、conflict 为空；按选定语义验证同步行为。

- [x] **T1.3 统一快照文件生命周期**
  - `purge`、`purgeExpired`、`clearAll`、`purgeFromRemote` 统一由 `FlowRepository` 删除快照文件；DAO 不承担文件副作用。
  - 验收：过期清理、彻底删除、清空后 `filesDir/snapshots` 无残留。
  - 测试：`purgeExpired` 后断言文件不存在。

- [x] **T1.4 修正同步状态与分享语义**
  - `SyncPage`：仅在连接测试或同步成功后置「已连接」；同步失败保留错误状态，允许重试。
  - 详情「分享」默认分享原文 URL（可附标题）；深链作为「在流笺中打开」的附加动作。
  - 验收：401/403 后不再显示「已连接」；分享到未安装流笺的设备得到可打开的原文链接。
  - 测试：同步失败状态用例；分享内容断言为原文 URL。

- [x] **T1.5 详情写入与异常收口**
  - 将 `title/note/excerpt/tags` 合并为一次 Repository 写入（事务），只 `notify()` 一次。
  - `checkLink` / `refreshMetadata` / `saveEdits` 全部补 `try/finally`，异常时复位 busy 并 toast 中文原因。
  - 验收：断网/数据库异常后按钮不卡死；一次编辑只产生一次 `rev` 增长与一次列表刷新。
  - 测试：Repository 单次更新用例；异常路径至少覆盖 busy 复位。

**第一批完成门槛**：`hvigorw clean assembleHap` 成功；新增测试通过；`docs/records/02-code-review.md` 勾选完成；`docs/quality/01-walkthrough-checklist.md` 相关走查项无回归。

---

## 6. 第二批：验收补齐

目标：把 PRD / `docs/records/06-implementation-plan.md` 验收中“已承诺但不可验收”的条目补齐。**建议 3–5 天。**

> 2026-10-21 完成：T2.1–T2.6 全部落地；卡片与键盘仍需人工走查，见 §10。

- [x] **T2.1 冲突记录 UI**
  - 同步页显示冲突数量；提供冲突列表、查看本地/远端 JSON、恢复到本地。
  - 恢复时写回 bookmark 并置 `dirty = 1`，删除对应 conflict。
  - 验收：双端修改同一书签 → 较新者胜 → 冲突列表可看到败方 → 一键恢复。
  - 测试：冲突写入/计数/恢复。

- [x] **T2.2 导入增强**
  - 解析预览：总数、文件夹数、重复数；用户确认后再写入。
  - 事务批量写入；失败 URL 可导出；导入过程可取消。
  - 大文件改成分块/异步读取，避免同步阻塞 UI。
  - 验收：5000 条 Chrome 导出文件 ≤8s；重复导入全部跳过；失败清单可导出。
  - 测试：解析器、去重、事务回滚、失败清单。

- [x] **T2.3 搜索、排序与列表性能**
  - 增加排序入口（创建时间 / 域名）；搜索命中高亮。
  - 列表查询改为 SQL 过滤/分页，避免每次全表加载；卡片快照按需刷新。
  - 验收：1000 条滚动 60fps；10k 条搜索 ≤100ms（按 `docs/records/06-implementation-plan.md` 口径）。
  - 测试：查询边界、分页、排序。

- [x] **T2.4 阅读语义与快照体验**
  - `UNREAD → READING → READ`；增加「标记未读」。
  - 设置页增加「自动保存正文快照」开关，关闭后写入 `SnapshotStatus.OFF`。
  - 长正文分段渲染，避免单 `Text` 200KB。
  - 验收：打开详情为阅读中，满 30 秒或手动标记为已读；关闭快照后新收笺不再抓正文。
  - 测试：状态迁移、开关持久化。

- [x] **T2.5 无障碍与信息一致性**
  - 将 `ink_tertiary` 调整到 ≥4.5:1（至少正文辅助文字）；所有可点区域 ≥44vp。
  - 补充 `accessibilityText`、焦点顺序、键盘操作（列表上下选择、打开、返回）。
  - 修正标签计数、summary 口径；展示 favicon 或明确不做。
  - 验收：按 `docs/quality/01-walkthrough-checklist.md` 走查，深色/浅色无不可读文字；键盘可完成核心路径。

- [x] **T2.6 卡片与服务卡片验收**
  - 桌面添加 2×2 / 2×4、刷新、点击直达、空状态；补「换一笺」。
  - 验收：人工走查通过，并记录在 `docs/quality/01-walkthrough-checklist.md`。

**第二批完成门槛**：上述验收项全部有记录；`hvigorw clean assembleHap` 成功；设备端 Hypium 全通过；`docs/quality/01-walkthrough-checklist.md` 更新。

---

## 7. 第三批 / Backlog

- 分布式 KV 同局域网同步（需 `DISTRIBUTED_DATASYNC` 与可信设备）。
- App Linking HTTPS、碰一碰/隔空传送（需真实域名与第二设备）。
- 内置浏览器、阅读模式、滚动位置接续。
- 冲突字段级合并。
- WebDAV 端到端加密。
- 自动标签建议、相似收藏聚类、小艺意图、华为账号。

---

## 8. 决策记录

| 决策 | 推荐默认 | 状态 |
|---|---|---|
| 「清空所有数据」范围 | 只清本机，文案明确「云端保留」；另提供「同时清除云端」作为独立危险操作 | **已确认（2026-10-21）**：只清本机，清 snapshots/conflict，文案标注云端保留；「同时清除云端」未做，留作独立危险操作 |
| V1.0 是否必须冲突 UI | 必须，先做最小可用列表 + 恢复 | **已确认（2026-10-21）**：同步页冲突计数 + 列表 + 查看双方 JSON + 恢复本地/采用远端 |
| 详情分享内容 | 默认分享原文 URL，深链作为附加动作 | **已确认（2026-10-21）**：分享原文 URL；另提供「复制深链」 |
| 1.0 是否包含分布式/内置浏览器/App Linking | 不包含，按 V1.1 交付；文档同步降级 | **维持（2026-10-21）**：不包含，仍按 V1.1 |

> 新会话若未收到用户新的决策回复，按「推荐默认」执行，并在最终汇报中标注。

---

## 9. 发布门禁

1. `hvigorw clean assembleHap` 成功，无 ERROR；已知 WARN 需记录。
2. `entry/src/ohosTest` 全部用例通过；新增能力必须有测试。
3. 完成 `docs/quality/01-walkthrough-checklist.md` 走查清单中手机、2in1、同步三部分。
4. 每一笔 Repository 写操作都满足 `rev / updated_at / dirty` 语义。
5. 不引入 `any` / `unknown`；`as` 使用需与 `AGENTS.md` 规则一致。
6. 文档状态与代码一致：`docs/records/01-implementation-log.md` 用例数、`docs/records/06-implementation-plan.md` 构建命令、`README` 已知边界。
7. 未经明确要求不 commit / push。

---

## 附录 A · 新会话启动提示词

```text
你是 FlowPage（流笺）项目的实现代理。请先完整阅读：
1. AGENTS.md
2. docs/records/02-code-review.md
3. docs/wiki/01-architecture.md、03-data-layer.md、04-sync-and-services.md、05-build-and-run.md

目标：完成 docs/records/02-code-review.md 中「第一批：正确性收口」和「第二批：验收补齐」的全部条目，并在完成后更新该文档的勾选状态与验证记录。

项目事实：
- HarmonyOS API 26 / ArkTS + ArkUI 状态管理 V2，单 HAP entry。
- 构建必须用 SDK 自带 hvigorw（7.26.8）：`hvigorw clean assembleHap`。
- 不要使用 `devecocli build`（内置 hvigor 不支持 modelVersion 26.0.0）。
- 设备测试命令见 docs/wiki/05-build-and-run.md。
- UI 只依赖 FlowRepository；常规写方法末尾必须 notify()。
- 颜色只用 `$r('app.color.*')`，深浅色成对维护。
- 禁止 any/unknown；遵循 ArkTS 严格子集；未经明确要求不要 commit/push。

开工前先确认三项决策；若用户未另行回复，按推荐默认执行并在汇报中标注：
A. 「清空所有数据」= 只清本机，文案明确「云端保留」，同时清快照与 conflict。
B. V1.0 必须做冲突记录 UI，先做最小可用列表 + 恢复。
C. 详情「分享」默认分享原文 URL，深链作为附加动作。

第一批（P0，优先完成）：
1. 标签变更同步：rename/merge/delete 批量置 dirty、rev+1、updated_at；重名走合并或捕获提示；listTags 排除回收站；补 DAO/Repository 测试。
2. 明确并实现「清空所有数据」语义：清 snapshots/conflict；按决策处理远端；补测试。
3. 统一快照文件生命周期：purge/purgeExpired/clearAll/purgeFromRemote 都由 Repository 删文件；补文件残留测试。
4. 修正 SyncPage「已连接」误报；详情分享改为原文 URL。
5. 合并详情编辑为一次事务写入，只 notify 一次；checkLink/refreshMetadata/saveEdits 补 try/finally 与中文错误提示。

第二批（P1）：
6. 冲突记录 UI：计数、列表、查看本地/远端、恢复。
7. 导入增强：预览、事务、失败清单导出、取消、5000 条基准。
8. 搜索/排序/高亮/SQL 分页；1000 与 10000 条基准。
9. 阅读状态 UNREAD→READING→READ、标记未读、自动快照开关、长文分段渲染。
10. 无障碍：对比度 ≥4.5:1、触控 ≥44vp、accessibilityText、键盘路径；修正标签与 summary 口径。
11. 卡片人工验收与「换一笺」。

工作方式：
- 每个修复先写能复现的测试（可自动化的），再改实现；不能自动化的记录人工步骤。
- 每改完一个 .ets 先跑快速检查；DEVECO_HOME 未设置时直接用 hvigorw 全量编译。
- 每批结束运行 `hvigorw clean assembleHap`；第二批结束按 docs 命令跑设备端 Hypium。
- 不要顺手重构无关模块；不要引入新依赖；不要改历史文档中的既有结论，除非是明确的事实纠错。

最终交付：
1. 修改文件清单与每个文件的意图。
2. 新增/修改的测试清单及通过结果。
3. 构建与设备测试命令、输出摘要。
4. docs/records/02-code-review.md 勾选状态与遗留问题。
5. 未解决的决策项与风险。
```

---

## 10. 本轮交付记录（2026-10-21）

### 10.1 修改文件与意图

| 文件 | 意图 |
|---|---|
| `entry/src/main/ets/core/db/BookmarkDao.ets` | 标签变更批量 touch（rev+1 / dirty=1 / updated_at）；重名合并；`listTags` 排除回收站；事务化 insert/update/editContent/insertBatch；conflict CRUD；SQL 过滤/排序/分页；domain 回填；card/summary 计数 |
| `entry/src/main/ets/core/db/Database.ets` | 新增 `domain` 列、索引与旧库 `ALTER TABLE` |
| `entry/src/main/ets/repository/FlowRepository.ets` | 标签/清空/快照生命周期收口；`saveEdits` 单次写入；冲突查询与恢复；导入预览/分批事务/取消；summary 改 SQL 计数；卡片快照按需取最近 10 条 |
| `entry/src/main/ets/core/db/BookmarkDao.ets#clearAll` | 清空本机时保留 tombstone，保证清空前已排队的彻底删除仍能传播到云端 |
| `entry/src/main/ets/core/service/SnapshotStore.ets` | 新增 `removeById/clearAll/count/pathFor`，由仓库层统一调用 |
| `entry/src/main/ets/core/parser/BookmarkHtmlParser.ets` | `parseAll()` 返回无效与文件内重复统计，保留 `parse()` 兼容 |
| `entry/src/main/ets/core/service/MetadataService.ets` | `fetch(url, includeSnapshot)`，关闭自动快照时不落正文 |
| `entry/src/main/ets/core/service/CardSnapshot.ets` | 卡片绑定数据增加 `today_candidates` |
| `entry/src/main/ets/model/{BookmarkQuery,Conflict,ImportPreview,ImportResult,LibraryCounts}.ets` | 新增查询/冲突/预览/汇总模型；`ImportResult` 增加 `cancelled` |
| `entry/src/main/ets/common/UrlUtil.ets` | 拒绝 `mailto:`/`javascript:`/`data:`/`tel:` 等非 http(s) scheme，保留 `host:port` |
| `entry/src/main/ets/common/{ShareUtil,TextUtil,Highlight}.ets` | 分享原文/深链、长文分段、搜索高亮纯函数 |
| `entry/src/main/ets/components/DetailContent.ets` | UNREAD→READING→READ、标记未读、30 秒自动已读、单事务保存、try/finally、原文分享/复制深链、分段正文、无障碍与键盘 |
| `entry/src/main/ets/components/StreamHome.ets` | SQL 分页加载、排序、搜索高亮接入、键盘上下/回车、44vp 触控 |
| `entry/src/main/ets/components/BookmarkRow.ets` | 高亮 Span、焦点与键鼠操作、无障碍语义 |
| `entry/src/main/ets/pages/SyncPage.ets` | 已连接/已配置/失败状态区分；冲突计数、列表、查看与恢复 |
| `entry/src/main/ets/pages/SettingsPage.ets` | 清空本机文案与语义、导入预览/取消/失败清单、分块读取、自动快照开关、44vp |
| `entry/src/main/ets/pages/TagsPage.ets` | 重名合并提示、异常捕获、44vp 与无障碍 |
| `entry/src/main/ets/widget/pages/TodayCard.ets` | 「换一笺」本地轮换（候选来自快照） |
| `entry/src/main/resources/{base,dark}/element/color.json` | 辅助文字对比度 ≥4.5:1；新增 `highlight` |
| `entry/src/ohosTest/ets/test/*` | 新增 `TagSync`、`Snapshot`、`Conflict`、`Repository`、`Query`、`Import` 六个套件，注册进 `List.test.ets` |
| `docs/wiki/*`、`docs/quality/01-walkthrough-checklist.md`、`docs/README.md`、`AGENTS.md` | 同步事实与验收记录 |

### 10.2 测试与结果

- 新增/修改套件（第一/二批）：`TagSyncTest`（5）、`SnapshotTest`（4）、`ConflictTest`（3）、`RepositoryTest`（8）、`QueryTest`（5）、`ImportTest`（7）。
  第三/四批后现为：`TagSyncTest`（8）、`ConflictTest`（4）、`RepositoryTest`（14）、`QueryTest`（7）、`SyncEngineTest`（10）。
- 设备端：`Tests run: 63, Failure: 0, Error: 0, Pass: 63`（Pura 70）。第三/四批后 `Tests run: 77, Failure: 0`（模拟器 + Pura 70）。
- 覆盖：标签 dirty/rev、重名合并、回收站计数、清空/过期/彻底删除/远端删除的快照清理、冲突计数/列表/恢复、单次编辑 rev、阅读状态、自动快照开关持久化、SQL 分页/关键字/标签/域名排序、批量事务回滚、导入预览/去重/取消/失败清单/5000 条。

### 10.3 命令与摘要

```bash
export DEVECO_SDK_HOME=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk
hvigorw clean assembleHap                 # BUILD SUCCESSFUL
hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 120000
```

基准（Pura 70）：1000 条搜索 3–4ms；10000 条搜索 14ms（热查询）；5000 条导入 6454–6973ms（目标 ≤8s）。

### 10.4 仍需人工验收

1. 桌面卡片 2×2 / 2×4 添加、刷新、点击直达、空状态与「换一笺」。
2. 2in1 键盘路径：Tab 进入列表、↑/↓ 选择、Enter 打开、Esc 返回。
3. 同步 401/403、断网后的「已配置 / 连接失败」文案与重试。
4. 关闭自动快照后新收笺不再落正文（`snapshotStatus=OFF`）。
5. 深色/浅色真实设备对比度与 44vp 触控复核。
6. favicon 展示明确不做，保留字段与抓取，UI 不消费。

### 10.5 遗留与风险

1. 5000 条导入 6.45–6.97s，距 8s 目标余量约 1s；低端设备需复测。
2. 10k 搜索冷启动首次约 555ms（后续 14ms），首页首次进入仍有 JIT/IO 抖动。
3. `codelinter` 因本机缺 HNP Node 未运行；建议在 DevEco 环境补跑。
4. 本轮设备测试只在手机完成；2in1 未跑测试 HAP。
5. 冲突 UI 为最小可用版本，展示截断 JSON，未做字段级合并。
6. R20（存量 `as` 断言）未纳入本轮；收尾批次已从 18 处收敛到 5 处平台类型边界，见 docs/records/03-review-follow-up.md §6.5。
7. R10（跨端 `folderPath/source`）：第三批完成最小修；收尾批次已升级 `SyncRecord` schema 2 并兼容 schema 1，Backlog 关闭。
8. 5000 条导入在模拟器为 10.27s，12s 保险阈值内；低端真机仍需复测回填。

## 11. 文件夹树收口评审（2026-10-28，add-folder-tree 归档前）

子代理对完整工作区变更做质量与冗余评审；人工走查（round-trip、树面板、拖拽、详情往返）已全部通过。

### 11.1 修复的缺陷（blocker）

1. `FolderDao.buildFolderTree` 计数读取使用 `as number` 断言，违反 ArkTS 严格子集，改为局部变量判空。
2. `FolderDao.move()` 未做目标父级同名检查：拖入 / FolderPicker 移入已含同名 live 子文件夹的目标时直接撞 `idx_folder_parent_name` 抛异常，且 `batchMove` 中途失败产生部分完成状态。现改为拒绝并按 skipped 计入（与「移入自身子孙被跳过」同语义）。
3. `FlowRepository.upsertFolderFromRemote()` 远端落地（insert 与 update 两路径）无同名消解：双端各自创建同名同级文件夹时每次同步永久失败且无自愈。现经 `FolderDao.dedupedName()` 落地去重名（`开发 (2)` 序列，与 `restoreChain` 同款）。

新增回归用例：`moveRejectsSiblingNameClashInTarget`、`remoteFolderLandingDedupesSameNameSibling`；设备端 185/185 通过，`codelinter` 0 error。

### 11.2 遗留（后续变更处理，不阻塞归档）

1. 文件夹软删除状态不随实体记录传播：墓碑要等过期清理才产生，窗口期内软删行仍按活态上传，且对端编辑可静默复活回收站中的文件夹。候选方案：`FolderSyncRecord` 增加 `deleted` 字段（对齐书签 LWW）或上传跳过 `deleted=1` 行 + 落地拒绝复活。
2. `appState.homeFilter` 与 `StreamHome` 私有 `filter` 双份存储，断点切换时可能不一致，应收敛到 AppState 单份。
3. 详情保存 `applyMetadata` 与 `setBookmarkFolder` 两阶段写、两次 notify，中途失败产生半保存态，可在 Repository 合并写入口。
4. 冗余项：`FlowRepository.bookmarksInFolder()` 生产零调用（带 500 条截断，误用有丢数据隐患）；`ImportedBookmark.folderPath` 与 `segments` 冗余；`DetailContent.onEscape` 无调用方；`BookmarkHtmlParser` 3 处函数内 `new RegExp`（非热点，与存量风格一致）。
