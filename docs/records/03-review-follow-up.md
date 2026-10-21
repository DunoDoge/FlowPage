# 流笺 FlowPage · 第二轮复审复核与第三批修复计划

> **时效说明**：本文是 2026-10-21 第二轮复审与第三/四批修复的历史记录；收尾批次后为 10 套件 / 81 用例。
> 当前状态见 [docs/README](../README.md) 与 [quality/01-walkthrough-checklist.md](../quality/01-walkthrough-checklist.md) §5。

- 复核日期：2026-10-21
- 复核方法：主审（第二轮复审）出结论后，派 3 个只读子代理分别独立验证「数据/同步一致性」「UI/ArkUI 行为」「测试与文档」，优先尝试推翻
- 代码基线：HEAD `21d7bfb` + 工作区未提交改动（含 docs/records/02-code-review.md 第一/二批修复）
- 复核结果：**全部结论无一被推翻**；2 处表述修正、3 处加重因素、1 处补充发现
- 构建与设备证据：`hvigorw clean assembleHap` BUILD SUCCESSFUL（12.7s，2 条已知卡片 `@Entry` WARN）；
  设备 127.0.0.1:37565 实测 `Tests run: 67`（首跑 1 fail——5000 条导入 8s 预算临界，复跑 67/67 pass）；
  手机 10.201.65.94:36793 锁屏（开发者模式禁自动解锁）未能复跑

---

## 1. 复核结论总览

| 项 | 子代理裁决 | 修正/补充 |
|---|---|---|
| N1 标签合并误伤（P1） | CONFIRMED | **路径勘误**：远端 ETag 已变时走 `planForExisting→FETCH→GET→planAfterFetch→UPLOAD`（非直接 UPLOAD）；ETag 相同时才是 `planForExisting→UPLOAD` 直传。两种情形结论不变：旧内容覆盖远端新修改，且不写 conflict（conflict 仅在 DOWNLOAD 路径产生） |
| N2 标签变更不重建 search_text（P1） | CONFIRMED | 违反 wiki/03:19 明文不变量；子代理建议可议降 P2（无数据丢失），主审按「功能错误」定义维持 P1 |
| N3 正文分段 index-only key（P1） | CONFIRMED | **加重**：确定性缺陷而非概率性。`SnapshotStore.read` 是同步 readTextSync，`:112-114` 清空中间态与 `:118` 赋新值在同一渲染帧内合并，ForEach 直接 diff 复用——两侧各 ≥1 段即可复现（原声明"≥2 段"过严）。影响面：≥700vp 宽屏（手机端每次 push 新建 DetailContent 实例，不受影响）。官方文档已证实"键值未变则数据变化不渲染" |
| R10 folderPath/source 跨端丢失（P1，未修复） | CONFIRMED | 根因在协议层：字段从未进入 SyncRecord，跨端必丢；本地侧任何远端胜出的下载都会整行覆盖为 `''`/`0` |
| N4 StreamHome 加载竞态（P2） | CONFIRMED | **加重**：`loading` 只在 finally 置 false、从不置 true，`loadMore` 入口的 loading 检查是死代码——现有守卫全部无效 |
| N5 LIKE 未转义（P2） | CONFIRMED | `_`/`%` 当通配符，"a_b" 命中 "axb" |
| N6 导入基准临界（P2） | CONFIRMED | 实测 6454–6973ms 为预算 81%–87%，首跑偶发失败已被本轮设备运行复现 |
| N7 卡片 '\|' 分隔符冲突（P2） | CONFIRMED | **补充**：标题含换行是另一种失败模式——行被 split('\n') 切开后 id 仍正确、仅标题错；含 '\|' 才是错 id → 卡片跳转空白页。'\' 入口齐全（og:title、手动编辑、导入 cleanText 均不去 '\|'） |
| N8 fillTags 全表 join + 每刷新 7 查询（P2） | CONFIRMED | Query 基准断言 1000<300ms / 10k<800ms，是 docs/engineering/02-implementation-plan.md:121 验收口径（10k ≤100ms）的 3–8 倍宽松 |
| 高亮修复 7 项子断言 | 全部 CONFIRMED | key 因含 index 必唯一；全库 13 处 ForEach 扫描，仅 DetailContent.ets:623 一处 index-only key |
| 修复声明抽查（clearAll 保墓碑 / 上传竞态条件化 / editContent 单事务） | 全部 CONFIRMED | 上轮"已修复"判定非误判 |
| 测试审查（67 例、旧套件未改、断言未削弱） | CONFIRMED | rg 实数 67；旧 4 套件不在 git diff 中 |
| 文档漂移 | CONFIRMED | **补充发现**：docs/README.md:38 也写"63 个设备端用例" |

---

## 2. 确认问题清单（第三批输入）

严重度沿用 docs/records/02-code-review.md §4 定义：P0 数据丢失/崩溃/错误写入，P1 功能错误/状态不一致，P2 性能/可维护性，P3 文档/风格。

### P1

#### T3.1｜N1 标签合并误伤无关书签 → LWW 静默覆盖远端新修改　`[x] 已修复`

- 证据：`BookmarkDao.ets:759-776`（mergeTags 末尾 `touchByTag(targetId)`）；`:714-721`（touch SQL 的子查询在 `INSERT OR IGNORE ... SELECT` 之后求值，无法区分新旧关联）；`:723-728`（renameTag 撞名走 merge）。
- 触发（已验证路径）：书签 M 只带标签 Y；设备 B 改 M 标题并已上传；设备 A 把 X 合并/重命名进 Y → M 被置 `dirty=1`、`updated_at=now`。A 同步时 `planAfterFetch`（SyncPlanner.ets:17-33）见 `remoteUpdatedAt < localUpdatedAt` 且 dirty → UPLOAD 本地旧标题覆盖 B 的修改；全程不经 `upsertFromRemote`，**无 conflict 留痕、不可追溯**。
- 修法：merge 前先圈定受影响书签（只含源标签关联的 id），仅 touch 这些 id。SQL 上可在搬移关联**之前**执行
  `UPDATE bookmark SET ... WHERE id IN (SELECT bookmark_id FROM bookmark_tag WHERE tag_id = :source AND bookmark_id NOT IN (SELECT bookmark_id FROM bookmark_tag WHERE tag_id = :target))`，
  或在事务内先查出 id 列表再按 id touch；`renameTag` 撞名路径共用。
- 验收：新增用例——只带目标标签的"无关书签"在 merge 后 `dirty=0`、rev 不变；带源标签的书签 dirty/rev+1。

#### T3.2｜N2 标签 rename/merge/delete 不重建 search_text　`[x] 已修复`

- 证据：`BookmarkDao.ets:714-721`（touch 只改 updated_at/rev/dirty）；`Bookmark.ets:54-57`（tags 拼入 searchText）；`BookmarkDao.ets:266-270`（搜索走 `search_text LIKE`）；违反 `docs/wiki/03-data-layer.md:19` 明文不变量。
- 后果：标签「旧」→「新」后本地搜「新」不命中、搜「旧」误命中，直到该书签下次全量写；远端设备反而因 `upsertFromRemote→rebuildSearch` 正确。
- 修法：touch 的同时重算受影响书签的 `search_text`（可在同一事务内 `UPDATE bookmark SET search_text = ... WHERE id IN (...)`，或逐条 findById+rebuildSearch 后回写——注意与 T3.1 共用"受影响 id 集合"）。
- 验收：改名后 `search_text` 含新标签名、不含旧名；补 `TagSync.test` 断言。

#### T3.3｜N3 正文分段 ForEach index-only key（宽屏确定性残留）　`[x] 已修复`

- 证据：`DetailContent.ets:623-631`（key `${index}`）；`loadSnapshot()` 同步读文件 + `@Local snapshotChunks` 整体替换；宽屏 `Index.ets:203-207` 单实例切换 `bookmarkId`。官方 ForEach 语义：键值未变则数据变化不渲染。
- 复现（≥700vp）：两笺 A/B 快照 DONE、正文各 <4000 字；选 A 再点 B → 正文仍显示 A 的文字（页脚"已存下正文"已随 B 变化）；切"摘录"再切回可恢复。
- 修法：key 掺入内容，如 `${index}:${chunk.length}:${chunk.slice(0, 32)}`；或切换书签时强制销毁重建正文分支。**不要**回退到整段单 Text（R15）。
- 验收：宽屏真机/模拟器走查一次并记录到 docs/quality/01-walkthrough-checklist.md。

#### T3.4｜R10 folderPath/source 跨端丢失（协议层）　`[x] 最小修已落地`

- 证据：`SyncRecord.ets:5-27` 无这两字段；`toBookmark()`（:83-110）默认 `folderPath=''`、`source=MANUAL(0)`；`FlowRepository.ets:196-213`（upsertFromRemote）与 `:521-561`（resolveConflict）`dao.update` 整行覆盖。
- 最小修（不升 schema）：下载覆盖前保留本地字段——`bookmark.folderPath = existing.folderPath; bookmark.source = existing.source;`（与现有 snapshot 三字段保留模式一致，`FlowRepository.ets:209-211`）；resolveConflict 同理。
- 完整修（可选，升 SyncRecord schema 2，向后兼容 parse）：把两字段加入上传/解析，端到端同步。默认做最小修，完整修留 Backlog。
- 验收：本地导入书签经历一次远端胜出下载后 folderPath/source 不丢；补 Repository/SyncEngine 用例。

### P2

#### T3.5｜N4 StreamHome 加载竞态　`[x] 已修复`

- 证据：`StreamHome.ets:81-95`（load 无世代 token，`loading` 恒 false 不构成守卫）；`:97-115`（loadMore 的 offset 在 await 前求值、append 用 await 后的 filtered，与并发 load 交叠跳行/重复；重复行还会撞 `${id}:${rev}:${updatedAt}` 唯一 key）。
- 修法：引入自增 requestId，load 完成时校验仍是最新一次才赋值；loadMore 记录发起时的 filtered 引用，完成后若 `this.filtered` 已被替换则丢弃本次结果。

#### T3.6｜N5 搜索 LIKE 未转义　`[x] 已修复`

- 证据：`BookmarkDao.ets:266-270`。修法：转义 `%`、`_`（及转义符本身）并加 `ESCAPE '\'`；测试覆盖 "a_b"、"100%" 关键词。

#### T3.7｜N7 卡片序列化分隔符冲突　`[x] 已修复`

- 证据：`FlowRepository.ets:163-180` 写 `标题|域名|id`；`TodayCard.ets:21-40`、`RecentCard.ets:17-33` 按 `split('|')` 解析。标题含 `|` → 错 id → 卡片跳转空白页（EntryAbility 仅校验非空）；含换行 → 标题错但 id 对。
- 修法：分隔符换成标题/域名中不可能出现的控制字符（如 `\u0001`），写入与两处解析同步改；或改 JSON 序列化。写入侧同时把标题压成单行（去 `\n`）。

#### T3.8｜N8 列表刷新查询成本　`[x] 已修复`

- 证据：`BookmarkDao.ets:198-223`（fillTags 每次全表 join、无 id 过滤）；`StreamHome.ets:84-89`（每次刷新 queryPage + summary 5 个 COUNT + countToday）。
- 修法：fillTags 按 page id 集合过滤（`WHERE bt.bookmark_id IN (...)`）；summaryCounts 合并为单 SQL（SUM/CASE）。基准断言口径见 T3.9。

### P3（顺手修，不单开批次）

1. `[x]` `SyncEngine.ets:44-46`：`upload()` 应根据 `setRemoteEtagIfUnchanged` 返回值决定计入 uploaded 还是保持"待重传"计数。
2. `[x]` `BookmarkDao.ets:813-819`：clearAll 四条 DELETE 包进单事务。
3. `[x]` `BookmarkDao.ets:497-546`：setTitle/setNote/setExcerpt 改为事务内两段写（或复用 editContent 模式），避免中途失败留旧 search_text。
4. `[x]` 异步无 catch：`DetailContent.ets:371`（confirmDelete 的 delete 未 await/catch）、`TagsPage.ets:26-29`、`SyncPage.ets:43-62`、`SettingsPage.ets:40-42`。
5. `[ ]` `renameTag` 改成仅大小写不同的同名时不 touch（no-op 写放大）。
6. `[ ]` `SettingsPage.ets:93`：`readFileChunked` 的 `new Uint8Array(total)` 整文件驻留内存，可流式解码或分块解析。
7. `[ ]` `TextUtil.ets:9-11`：splitIntoChunks 丢弃空行，正文段落间距丢失。
8. `[x]` 触控残留：`SyncPage.ets:292/305/318`、`TagsPage.ets:222` 输入框 42vp → 44vp。
9. `[ ]`（观察，未做）`FlowRepository.ets:548-556`：resolveConflict 采用远端时可不清 dirty（内容与远端一致，省一次重传）——需与 setRemoteEtagIfUnchanged 语义对齐后再做，可留观察。
10. `[x]` `BookmarkDao.ets:344`：`countCreatedSince` 首行格式。

---

## 3. 测试补强清单

1. `[x]` **T3.1 回归用例**：merge/rename 撞名时"只带目标标签的无关书签"不被 touch（dirty/rev 不变）——本轮 `mergeTagsTouchesBothSides` 缺此对照断言，是 N1 漏网原因。
2. `[x]` **T3.2 用例**：rename/merge/delete 后 `search_text` 含新名不含旧名。
3. `[x]` **T3.4 用例**：upsertFromRemote 覆盖后 folderPath/source 保留本地值。
4. `[x]` **基准口径**：`Query.test.ets:137/150` 现为 1000<300ms、10k<800ms，与 `docs/engineering/02-implementation-plan.md:121`（10k ≤100ms）差 3–8 倍。处理：热查询断言收紧到验收口径（或 200ms 内），另设独立的冷启动"记录不判费"用例；`Import.test.ets:139` 的 `elapsed<8000` 在部分设备临界（本轮首跑失败复跑通过），建议改为记录 + 更宽保险阈值（如 12s）并在低端设备复测。
5. `[x]` 冲突链路用例（FakeTransport 可测）："恢复本地 → 下一轮同步上传本地版本"由 `SyncEngineTest.restoredLocalConflictUploadsOnNextSync` 覆盖；另补 `tagMergeDoesNotOverwriteRemoteEditOfTargetOnlyBookmark` 覆盖 N1 的 FETCH→UPLOAD 路径。

## 4. 文档修正清单

| 位置 | 现状 | 应改为 |
|---|---|---|
| `AGENTS.md:16` | "10 个套件 / 63 个用例" | 77（实际落地数） |
| `docs/wiki/05-build-and-run.md:77` | "63 个" | 77（实际落地数） |
| `docs/quality/01-walkthrough-checklist.md:69、104` | "63" | 77（并注明 127.0.0.1:37565 实测） |
| `docs/records/02-code-review.md` §10.2（:329-330） | "RepositoryTest（8）"、"Tests run: 63" | RepositoryTest（14）、Tests run: 77（并保留第一/二批历史数字） |
| `README.md:78` | "4 个套件 / 30 个用例" | 10 套件 / 77 用例 |
| `docs/README.md:38` | "63 个设备端用例通过" | 77（补充发现） |
| `docs/records/01-implementation-log.md:114` | "28 个"（历史文档） | 加"已过期，见 records/03-review-follow-up.md"注记即可，不改写历史记录 |
| `docs/wiki/02-ui-layer.md:29` | "数据源 listAll(true)" | queryPage SQL 分页 |
| `docs/wiki/02-ui-layer.md:45` | "自动 setRead(READ)" | UNREAD→READING→READ + 30s |
| `docs/wiki/02-ui-layer.md:49` | "分享 flowpage:// 深链" | 分享原文 URL，深链为复制动作 |
| `docs/wiki/02-ui-layer.md:92-93` | 卡片字段列表 | 补 `today_candidates` |
| `docs/wiki/02-ui-layer.md:77-78` | 色板列表 | 补 `highlight` |
| `docs/wiki/03-data-layer.md:70` | "所有写操作逐条 SQL、无事务" | 更新为事务现状（与 :55 自身矛盾） |
| `docs/records/02-code-review.md` §10.5 | 遗留清单 | 补列 R10（本轮确认未修复） |
| `docs/records/02-code-review.md` §3.1 完成度矩阵 | "无搜索高亮"等 | 随本批修复更新 |
| 本文档 §2 各条 | — | 修复后逐条勾选并记录验证 |

## 5. 修复批次建议

- **第三批（P1，建议 1–2 天）**：T3.1 → T3.2（同一事务区域，一起改一起测）→ T3.3 → T3.4；每项先写复现用例再改实现。
- **第四批（P2 + 测试口径 + 文档，建议 1–2 天）**：T3.5–T3.8、§3 基准口径、§4 文档同步。
- P3 清单作为两批内的顺手修，不设独立门槛。
- 完成门槛：`hvigorw clean assembleHap` 成功；设备端全通过（记录实际套件/用例数）；docs/records/03-review-follow-up.md 勾选并回填验证记录；未经明确要求不 commit/push。

---

## 6. 第三/四批执行记录（2026-10-21）

### 6.1 修改文件与意图

| 文件 | 意图 |
|---|---|
| `entry/src/main/ets/core/db/BookmarkDao.ets` | 标签改名/合并/删除只处理含源标签的书签，并在同一事务内用变更前的标签快照重建 `search_text`；`fillTags` 按页 id 过滤；`summaryCounts` 合并单 SQL；LIKE 转义；clearAll/文本字段事务化；`countCreatedSince` 格式 |
| `entry/src/main/ets/repository/FlowRepository.ets` | 下载与冲突采用远端前保留本地 `folderPath/source`；卡片写入改用 `` 分隔符并压单行标题 |
| `entry/src/main/ets/common/CardFormat.ets` | 新增卡片行编码/解析纯函数，写入侧与两处卡片解析共用 |
| `entry/src/main/ets/core/sync/SyncEngine.ets` | 上传后条件更新失败时不计入 `uploaded`（保持待重传） |
| `entry/src/main/ets/components/DetailContent.ets` | 正文分段 key 掺入内容；删除改为 await + catch |
| `entry/src/main/ets/components/StreamHome.ets` | `load` 世代 token、`loadMore` 校验 `filtered` 是否被替换、`loading` 真正置位 |
| `entry/src/main/ets/widget/pages/{TodayCard,RecentCard}.ets` | 使用 `CardFormat.parseCardLine()` 解析新分隔符 |
| `entry/src/main/ets/pages/{TagsPage,SyncPage,SettingsPage}.ets` | 异步读取补 catch；输入框 42vp → 44vp |
| `entry/src/ohosTest/ets/test/{TagSync,SyncEngine,Conflict,Query,Import,Repository}.test.ets` | 新增/修正回归用例与基准口径 |
| `AGENTS.md`、`README.md`、`docs/{05,06,08,README}.md`、`docs/wiki/{02,03,04,05}` | 同步用例数、行为与遗留事实 |

### 6.2 测试与结果

- 套件数不变（10 个）；用例 67 → **77**。
- 新增/修改：`TagSyncTest`（8）、`SyncEngineTest`（11）、`ConflictTest`（4）、`RepositoryTest`（14）、`QueryTest`（7）、`ImportTest`（7）。
- 设备端：模拟器 `127.0.0.1:37565` → `Tests run: 77, Failure: 0, Error: 0, Pass: 77`。
- HUAWEI Pura 70（`10.201.65.94:36793`）：本批 P1/P2 修复版 `76/76` 通过；最终 77 版复跑时设备锁屏，`aa test`
  报 `10106102`（开发者模式禁自动解锁），待解锁后补跑。
- 基准（新口径）：
  - Pura 70：冷查询 10000 条 19ms（记录不判费）；热查询 1000 条 3ms、10000 条 17ms（断言 <100ms / <200ms）；
    5000 条导入 6603ms（保险阈值 12000ms）。
  - 模拟器：冷查询 15ms；热查询 1000 条 1ms、10000 条 12ms；5000 条导入 4551ms（clean 构建后终跑）。
- 提交前复核（同日代码审查清理后）：
  - 构建：`hvigorw clean assembleHap` BUILD SUCCESSFUL（12.4s）；测试 HAP BUILD SUCCESSFUL。
  - 设备端：模拟器 `127.0.0.1:37565` 与 HUAWEI Pura 70（`10.201.65.94:36793`，已解锁）均
    `Tests run: 77, Failure: 0, Error: 0, Pass: 77`。
  - 基准（复核轮，clean 构建后终跑）：手机冷查询 10000 条 15ms、热查询 1000 条 3ms / 10000 条 15ms、
    5000 条导入 6444ms；模拟器冷查询 12ms、热查询 1000 条 3ms / 10000 条 14ms、5000 条导入 5775ms
    （均在 12s 保险阈值内；前一轮复跑手机 6717ms / 模拟器 6669ms，波动来自设备负载）。
- T3.3 宽屏走查（模拟器 3120×2080）：InfoQ→阮一峰→HarmonyOS→Example Domain→阮一峰，标题与正文每次切换均更新；
  Example Domain 首次无快照，点「重试抓取」后正常（非 key 缺陷）。

### 6.3 命令与摘要

```bash
export DEVECO_SDK_HOME=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk
hvigorw clean assembleHap                 # BUILD SUCCESSFUL
hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap
hdc -t 127.0.0.1:37565 install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc -t 127.0.0.1:37565 install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc -t 127.0.0.1:37565 shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 180000
```

### 6.4 遗留

1. `R20`（存量 17 处 `as` 断言）未处理；本轮未新增 `as`。收尾批次已收敛到 5 处平台边界，见 §6.5。
2. `R10` 仅做本地保留的最小修；`SyncRecord` schema 2 端到端同步 `folderPath/source` 留 Backlog。收尾批次已落地 schema 2，见 §6.5。
3. `N6` 5000 条导入低端真机复测待办；当前 12s 保险阈值下模拟器 4090ms、Pura 70 6603ms。
4. P3 未做项：大小写同名 no-op、`readFileChunked` 流式、`splitIntoChunks` 空行保留、resolveConflict 不清 dirty。
5. 手机最终 77 版测试因锁屏未复跑；提交前设备已解锁并复跑通过（`77/77`，见 §6.2 复核行）。

---

## 6.5 收尾批次（代码审查清理与迭代前置项，2026-10-21）

### 6.5.1 修改与意图

| 项 | 变更 | 意图 |
|---|---|---|
| 卡片 preferences 损坏（新发现） | `CardFormat` 分隔符改为可打印 ASCII `%01`，三个字段分别 `encodeURIComponent`；`cardTitleOf` 清理全部 C0/C1 控制字符；`FlowRepository.init()` 启动后刷新一次卡片快照 | 旧实现把 `\u0001` 直接写进 preferences 的 XML，设备日志出现 `PCDATA invalid Char value 1`，文件被改名为 `flowpage_card.broken`，卡片进程只能读到默认值。改后设备上文件为合法 XML（含 `%01`），启动即重写修复 |
| R10 / `SyncRecord` schema 2 | 记录新增 `folderPath`、`source`，`schema=2`；`parse` 兼容 schema 1；下载/冲突仅在 schema 1 时保留本地这两字段 | 跨端同步文件夹与来源；旧客户端/旧文件不丢本地值 |
| 数据库迁移约定 | 抽出 `Database.applySchema(store)` + `addColumn()`，`init()` 复用 | 迁移逻辑可对旧库单独执行并测试 |
| 迁移回归用例 | `SyncStoreTest.appliesSchemaToLegacyBookmarkTable` 构造旧表、连跑两次 `applySchema`、断言新列默认值与旧行保留 | 防止下次加列漏写 `ALTER TABLE` |
| R20 | `as` 18 → 5（按 HEAD 实数）：页面不再原地断言 `Context/UIAbilityContext`（`AppState` 在 Ability 启动时持有类型化 context）；`BusinessError` 收口到 `common/PlatformError.ets`；`SyncConfigStore` 合并两处 `JSON.parse` | 剩余 5 处均为平台类型边界：`JSON.parse` ×2、WebDAV 动词、响应头、`PlatformError` |
| 本地测试入口 | 新增 `entry/src/test/List.test.ets`、`LocalUnit.test.ets`（卡片编码、高亮、分段） | 纯函数可在 `hvigorw test` 下跑；本机 SDK 缺 previewer 可执行文件，仅验证了编译（`UnitTestArkTS` 通过），运行需补装 previewer |
| 冗余 `await` | 去掉 9 处对同步 `beginTransaction()` 的 `await` | `beginTransaction/commit/rollBack` 均为同步 API；`codelinter` 从 9 warn 回到 0 warn |

### 6.5.2 验证

- `hvigorw clean assembleHap` BUILD SUCCESSFUL；测试 HAP BUILD SUCCESSFUL。
- 模拟器 `127.0.0.1:37565`：`Tests run: 81, Failure: 0, Error: 0, Pass: 81`（新增 4 例：schema 2 下载、SyncRecord 往返、旧库迁移、卡片 preferences 往返）。
- 手机 `10.201.65.94:36793`：收尾批次复跑时锁屏（`10106102`），未绕过；主功能 77 版已在提交前解锁跑通。
- 卡片修复设备证据：`flowpage_card.broken`（21:47，旧文件）→ 启动后生成合法 `flowpage_card`（21:49，`%01` + URL 编码字段），进程存活、无 `PCDATA` 错误。
- `hvigorw test`：`UnitTestArkTS` 编译通过，运行停在 `previewer/common/bin ENOENT`（SDK 未安装 previewer）。
- `codelinter -c code-linter.json5`：0 error / 0 warn / 1 suggestion（`startIcon` 性能建议）。
- 基准未退化（模拟器）：冷查询 10000 条 11ms、热查询 1000 条 2ms / 10000 条 12ms、5000 条导入 6029ms。

### 6.5.3 遗留

1. R20 余 5 处平台边界；如要归零，需改 `AGENTS.md` 规则或引入平台类型适配层（当前已集中在 `PlatformError`/`WebDavTransport`/JSON 解析）。
2. 本地纯函数测试需在安装 previewer 的 DevEco 环境跑一次，确认断言全绿。
3. 手机 81 版待解锁补跑。
4. N6 低端真机导入复测、2in1 测试 HAP 仍未做。

---

## 附录 A · 下一轮修复会话提示词

```text
你是 FlowPage（流笺）项目的实现代理。请先完整阅读：
1. AGENTS.md
2. docs/records/03-review-follow-up.md（本轮唯一任务来源；其中问题已经三个只读子代理独立复核确认）
3. docs/records/02-code-review.md §4（R 编号背景）
4. docs/wiki/03-data-layer.md、04-sync-and-services.md

目标：完成 docs/records/03-review-follow-up.md §2 第三批（T3.1–T3.4，P1）与 §3/§4 对应的测试补强、文档同步；若时间允许做第四批（T3.5–T3.8）。

项目事实：
- HarmonyOS API 26 / ArkTS + ArkUI 状态管理 V2，单 HAP entry。
- 构建必须用 SDK 自带 hvigorw：`hvigorw clean assembleHap`；不要用 `devecocli build`（不支持 modelVersion 26.0.0）。
- 设备测试命令见 docs/wiki/05-build-and-run.md；手机 10.201.65.94:36793 若锁屏需先解锁再跑。
- UI 只依赖 FlowRepository；常规写方法末尾必须 notify()。
- 颜色只用 $r('app.color.*')，深浅色成对维护。
- 禁止 any/unknown；不要新增 as 断言（存量 17 处是已知遗留，另立处理）。
- 未经明确要求不要 commit/push。

第三批（P1，先写复现用例再改实现）：
1. T3.1 标签合并误伤（BookmarkDao.mergeTags/renameTag 撞名路径）：touch 只圈"含源标签"的书签，
   不许碰只含目标标签的无关书签。测试：无关书签 dirty/rev 不变；含源书签 dirty=1、rev+1。
   注意复核确认的同步路径：误 touch 后本地 updated_at=now 会在 FETCH→planAfterFetch→UPLOAD 中
   以旧内容覆盖远端新修改且不写 conflict——回归测试要覆盖"远端 etag 已变"情形。
2. T3.2 标签 rename/merge/delete 重建受影响书签的 search_text（与 T3.1 同一事务/同一 id 集合）。
   测试：改名后 search_text 含新名不含旧名。
3. T3.3 DetailContent 正文分段 ForEach 的 index-only key（DetailContent.ets:631）：key 掺入内容
   （如 ${index}:${chunk.length}:${chunk.slice(0,32)}），不要回退整段单 Text。宽屏(≥700vp)人工走查
   一次：A→B 切换正文必须更新，结果记入 docs/quality/01-walkthrough-checklist.md。
4. T3.4 upsertFromRemote 与 resolveConflict 覆盖前保留本地 folderPath/source（照 snapshot 三字段的
   保留模式，FlowRepository.ets:209-211 附近）。测试：远端胜出下载后两字段不丢。

第四批（P2）：
5. T3.5 StreamHome load/loadMore 竞态：load 加世代 token；loadMore 完成时若 filtered 已被替换则丢弃。
6. T3.6 搜索 LIKE 转义（%、_、转义符 + ESCAPE 子句）。
7. T3.7 卡片序列化分隔符：'|' 换成标题中不可能出现的控制字符（如 \u0001），写入与 TodayCard/
   RecentCard 解析同步改，写入侧标题压单行。
8. T3.8 fillTags 按页 id 集合过滤；summaryCounts 合并单 SQL。
9. 测试口径：Query 基准热查询断言对齐 docs/engineering/02-implementation-plan.md:121（10k ≤100ms，可放宽到 200ms 内），冷启动单独
   记录不判费；Import 5000 条断言放宽保险阈值（12s）并在低端设备复测后回填。
10. 文档同步（docs/records/03-review-follow-up.md §4 全表）：用例数 63→67（AGENTS.md:16、wiki/05:77、docs/quality/01-walkthrough-checklist.md:69/104、
    docs/records/02-code-review.md §10.2、README.md:78、docs/README.md:38）；wiki/02 五处过期表述；wiki/03:70 事务表述；
    docs/records/02-code-review.md §10.5 补列 R10；docs/design/01-ui-spec.md §1 不变量在 T3.2 落地后恢复成立。

P3 顺手修（docs/records/03-review-follow-up.md §2 P3 清单 1-8，不改行为边界，逐条小 PR 粒度）。

工作方式：
- 每个修复先写能复现的自动化用例（不能自动化的记录人工步骤到 docs/quality/01-walkthrough-checklist.md）。
- 每改完一个 .ets 先跑快速 ArkTS 检查（DEVECO_HOME 未设置就直接 hvigorw 全量编译）。
- 批末 `hvigorw clean assembleHap` + 设备端 Hypium 全量（记录实际套件/用例数）。
- 不要顺手重构无关模块；不引入新依赖；不改 AGENTS.md 既有规则。
- 完成后在 docs/records/03-review-follow-up.md §2/§3 逐条勾选并回填验证记录（构建/测试命令与数字）。

最终交付：
1. 修改文件清单与每个文件的意图。
2. 新增/修改测试清单及通过结果（含基准新口径下的数字）。
3. 构建与设备测试命令、输出摘要。
4. docs/records/03-review-follow-up.md 勾选状态与遗留问题（含 R20 as 存量、N6 低端设备复测等待办）。
```
