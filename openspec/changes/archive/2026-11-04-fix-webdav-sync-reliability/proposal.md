# Proposal

## Why

用户实测报告两个严重同步缺陷：同步后云盘 `FlowPage/v1/folders` 目录始终为空（文件夹信息完全没有上传），且待上传书签较多时部分书签上传失败。经排查，引擎与数据层逻辑正确（设备端 185/185 用例通过，含文件夹上传/LWW/墓碑路径），缺陷根因在真实 WebDAV 服务器边界：

1. **传输层零容错**：`WebDavTransport.request()` 对每个实体紧密串行发请求（启动即 test + 5×MKCOL + 3×PROPFIND 连发；每实体 1×PUT，PUT 响应缺 ETag 头时再 +1×PROPFIND stat 回填），对瞬时失败（HTTP 429/502/503/504、网络抖动 NET_*）一律立即判死、计入 `failed`，无重试、无退避、不识别 `Retry-After`。坚果云等服务商对突发请求限流，批量书签上传必然触发 429/503 → 部分书签单轮硬失败（缺陷二）。历史上真实坚果云验收（docs/records/01-implementation-log.md §1.9）仅用 6 条书签、且早于文件夹功能（2026-10-28）完成，从未覆盖过批量与文件夹路径。
2. **文件夹阶段饥饿**：`SyncEngine.run()` 先同步书签集合（entry/src/main/ets/core/sync/SyncEngine.ets:345）、后同步文件夹集合（同文件 :384）。大批量书签上传耗尽服务商限流预算后，文件夹阶段每轮都落在限流窗口内，文件夹 PUT 系统性全部失败 → 云端 folders 目录持续为空；失败文件夹虽保持 dirty，但下一轮仍排在书签积压之后，形成持续饥饿（缺陷一）。

5.2 真实坚果云验收又暴露第三层缺陷（上传侧已修复、下载侧未覆盖）：**批量下载风暴**——全新设备逐条 GET 数百条远端记录触发服务商 ~1 req/s 限流，每条失败再消耗 1.5s 重试退避，366 条失败即 10–20 分钟纯等待且限流窗口无法恢复。单请求重试只适合零星瞬时失败，批量场景需要自适应节流与熔断早停（见 design D6/D7）。

附带缺口：`SyncErrorText` 无 429 文案，用户无法辨识限流失败。

## What Changes

- `WebDavTransport` 请求层新增瞬时失败自动重试：状态码 429/502/503/504 与网络异常（NET_*）按指数退避重试（上限 3 次尝试），尊重 `Retry-After` 响应头（设上限，超上限快速失败）；非瞬时失败（401/403/404/409/412 等）不重试，保持 LWW/If-Match 语义不变。
- 限流自适应节流与熔断早停：重试耗尽的限流失败激活全局节流（基础 1000ms、`Retry-After` 融合、成功按比例衰减退出），节流下连续 3 次耗尽即提前结束本轮并给出「剩余条目下次同步继续」文案，未处理条目不计失败。
- `SyncEngine.run()` 调整实体集合同步顺序：文件夹集合先于书签集合执行（墓碑对账与墓碑上传的相对位置不变），解除文件夹在限流场景下的饥饿。
- 抽出纯逻辑重试决策类（输入尝试次数/Retry-After/状态码 → 输出延迟或放弃），供传输层调用并支撑设备端纯逻辑测试。
- `SyncErrorText` 补 429 限流文案（自动重试耗尽后的最终失败描述）。
- 测试：FakeTransport 补「PUT 失败 N 次后成功」与「文件夹先于书签上传」顺序断言；重试决策纯逻辑用例；全量设备端回归。
- 真实坚果云端到端手动验收（批量书签 + 文件夹，需用户凭据配合）。

无 BREAKING 变更：远端目录结构、记录 schema、LWW/墓碑语义、配置存储均不变。

## Capabilities

### New Capabilities
- `webdav-sync`: WebDAV 同步传输可靠性——瞬时失败重试与退避策略、实体集合同步调度顺序（文件夹优先）、限流失败的最终报告行为。既有的实体级 LWW/墓碑语义仍由 `bookmark-folders` 等能力承载，本能力只覆盖传输层行为。

### Modified Capabilities

（无：`bookmark-folders` 的「文件夹作为同步实体」需求聚焦实体语义，本轮不改其行为；传输调度与重试是新维度的系统行为。）

## Impact

- 代码：`entry/src/main/ets/core/sync/WebDavTransport.ets`（重试接入、Retry-After 解析）、`entry/src/main/ets/core/sync/SyncEngine.ets`（集合顺序对调）、`entry/src/main/ets/core/sync/SyncErrorText.ets`（429 文案）、新增 `entry/src/main/ets/core/sync/` 下重试决策类。
- 测试：`entry/src/ohosTest/ets/test/SyncEngine.test.ets`（FakeTransport 顺序与失败注入）、新增重试决策用例（并入既有同步套件）。
- 不涉及 RDB schema、module 权限、第三方依赖、UI 路由。
- 行为风险：单次同步在重度限流下总时长可能增加（退避等待）；重试不改变幂等与收敛语义（412 仍交由下一轮 LWW 收敛）。
