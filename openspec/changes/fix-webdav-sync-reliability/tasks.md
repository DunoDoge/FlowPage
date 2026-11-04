# Tasks

## 1. 重试决策纯逻辑类

- [x] 1.1 新增 `entry/src/main/ets/core/sync/WebDavRetryPlanner.ets`：输入尝试序号/失败形态（HTTP 状态码或网络错误标记）/`Retry-After` 秒数，输出等待毫秒或放弃；实现退避序列 500/1000/2000ms、最多 3 次尝试、`Retry-After` 优先且 5000ms 上限、可重试集合限定 429/502/503/504 与网络错误（401/403/404/409/412 等不重试）；以 `check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 1.2 新增设备端用例 `entry/src/ohosTest/ets/test/WebDavRetry.test.ets` 并注册进测试 Ability：覆盖退避序列、`Retry-After` 优先、5s 上限放弃、非瞬时状态码不重试、网络错误可重试、3 次尝试上限；按 AGENTS.md 流程构建安装后 `aa test` 该套件全通过，`check_ets_files` + `hvigorw assembleHap` 收尾

## 2. 传输层接入重试

- [x] 2.1 `entry/src/main/ets/core/sync/WebDavTransport.ets` 的 `request()` 接入 `WebDavRetryPlanner`：响应码落在可重试集合或捕获 `NET_*` 异常时按决策延迟（setTimeout 等待）后重发，读取并透传 `Retry-After` 响应头，重试与耗尽写入 hilog（含次数与延迟）；成功路径行为不变（ETag/stat 回填逻辑不动）；`check_ets_files` + `hvigorw assembleHap` 收尾

## 3. 引擎调度顺序与失败注入用例

- [x] 3.1 `entry/src/main/ets/core/sync/SyncEngine.ets` 的 `run()` 把文件夹 `syncCollection` 调到书签 `syncCollection` 之前（墓碑对账与墓碑上传位置不变）；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 3.2 `entry/src/ohosTest/ets/test/SyncEngine.test.ets` 补用例：FakeTransport 记录跨集合调用顺序，断言同轮两者皆 dirty 时文件夹 PUT 先于任意书签 PUT；FakeTransport 增加「put 前 N 次抛 PUT_429 后成功」注入，断言该实体最终计成功、dirty 清零，以及「持续失败→计入 failed、保持 dirty、下一轮 `run()` 重传成功」两条；既有 185 用例不回归；`check_ets_files` + `hvigorw assembleHap` 收尾

## 4. 限流失败文案

- [x] 4.1 `entry/src/main/ets/core/sync/SyncErrorText.ets` 的 `write()` 增加 429 分支（「请求过于频繁（429），已自动重试仍失败，请稍后再同步」），在既有同步套件补一条文案断言；`check_ets_files` + `hvigorw assembleHap` 收尾

## 5. 回归、真实验收与文档

- [x] 5.1 全量设备端回归：按 AGENTS.md 构建 ohosTest 并安装运行全部套件（185+ 新增用例）全通过，`codelinter -c code-linter.json5` 0 error 收尾
- [ ] 5.2 真实坚果云手动验收（需用户提供应用密码）：导入 ≥200 条书签与 ≥3 层文件夹后触发同步——首轮云端 `FlowPage/v1/folders` 出现全部文件夹记录、书签零失败或仅限流失败并在第二轮 `run()` 后零积压；记录观察到的限流表现（触发规模/恢复节奏）到本变更目录验收备注，供 D2 参数后续微调
- [x] 5.3 文档收尾：按 AGENTS.md 把「传输层瞬时失败重试（429/502/503/504+NET_*，3 次退避，Retry-After≤5s）」「文件夹集合先于书签集合同步」写入易变事实段；全量内链 grep 校对（proposal/design/tasks/specs 与 AGENTS.md 间路径与结论一致）收尾

## 6. 限流自适应节流与熔断早停（5.2 验收反馈）

- [x] 6.1 `entry/src/main/ets/core/sync/WebDavRetryPlanner.ets` 增加纯逻辑 `WebDavPacer`（节流间隔激活/衰减/退出、`Retry-After` 融合上限 30000ms、连续 3 次耗尽→abort 判定，成功清零连击），在 `entry/src/ohosTest/ets/test/WebDavRetry.test.ets` 补节流器用例；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 6.2 `entry/src/main/ets/core/sync/WebDavTransport.ets` 接入节流器：请求前等待节流间隔、限流耗尽喂入节流器、abort 后置 `hardThrottled` 使后续请求立即抛 `THROTTLED_ABORT`，hilog 记录节流进入/退出/熔断；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 6.3 `entry/src/main/ets/core/sync/SyncEngine.ets` 贯穿熔断：`uploadOne`/远端循环/墓碑循环捕获 `THROTTLED_ABORT` 向上传播并跳过后续阶段，`SyncReport` 增 `throttled` 并在汇总文案给出「服务器限流，本轮提前结束，剩余条目下次同步继续」；`SyncErrorText` 补 `THROTTLED_ABORT` 与 `read(429)` 文案；`SyncEngine.test.ets` 补 FakeTransport 熔断注入用例（部分完成后提前结束、剩余不计失败、下一轮续传完成）；`check_ets_files` + `hvigorw assembleHap` 收尾
- [x] 6.4 全量设备端回归（含新增用例）全通过 + `codelinter -c code-linter.json5` 0 error 收尾
- [x] 6.5 按 AGENTS.md 把「限流自适应节流 + 熔断早停」口径写入易变事实段（修订既有重试条目），全量内链 grep 校对收尾

## Workflow follow-up

- 实现与验收完成后走 `/openspec-archive-change` 归档，归档后把重试口径与调度顺序结论吸收进 AGENTS.md（openspec/config.yaml 的 operations.archive 指引）。
- 未经明确要求不 commit/push。
