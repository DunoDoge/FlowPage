# Tasks

## 1. 代码修复

- [x] 1.1 `entry/src/main/ets/components/DetailContent.ets`：改写 `syncSnapshot()`——进入时快照 `const id = this.bookmarkId`，`repo.get()` 返回后快照失配（`this.bookmarkId !== id`）即整体返回（design D4 竞态守卫）；`found === undefined` 分支改为 `clearReadingTimer()` + 置 `hasBookmark = false` + 触发 `this.onRemoved()`（design D1/D2/D6）。收尾：`check_ets_files` 校验该文件通过 + `hvigorw assembleHap` 通过。
- [x] 1.2 `entry/src/main/ets/pages/Index.ets`：`PageMap` 中手机端 `DetailContent` 的 `onRemoved` 在 `closeDetail()` 前补 `this.appState.clearSelection()`（design D3）。收尾：`check_ets_files` 校验该文件通过 + `hvigorw assembleHap` 通过 + `codelinter -c code-linter.json5` 无新增 error/warn。

## 2. Spec 场景设备端验证

- [x] 2.1 宽断点正向走查（2in1 或折叠屏展开，≥700vp，全程免键盘点击）：回收站 → 点击行（右栏展示该书签）→ 行「…」菜单「彻底删除」→ 确认 → 右栏回到「选一笺」空态且左列无残留选中高亮（spec「宽断点列表行菜单彻底删除当前展示书签」「宽断点删除后无残留选中高亮」）；再以批量「彻底删除」含当前展示书签重复一遍（spec「宽断点批量彻底删除包含当前展示书签」）。验证：真机目检空态文案与高亮。（2in1 真机执行：测试书签经 `aa start -U` want 免键盘路径注入、收笺成功；走查由用户现场验收通过。）
- [x] 2.2 负向与既有路径回归：宽断点彻底删除**非**当前展示的书签，右栏保持展示不变（spec「删除其他书签不影响当前展示」）；详情面板内「彻底删除」既有行为不变（spec「详情面板内彻底删除行为保持」）；手机端（<700vp）详情内删除 / 返回行为无回归。验证：真机目检。（用户现场验收确认；既有路径行为由 2.4 全量套件回归覆盖。）
- [x] 2.3 同步墓碑路径（spec「同步墓碑清理正在查看的书签」）：无第二台设备（AGENTS.md 待决事项 #1），走回归兜底——`SyncEngine.test.ets` 既有 `purgesLocalWhenRemoteTombstoneArrives` 用例随 2.4 套件跑绿，`purgeFromRemote` 本体由 `Snapshot.test.ets` 覆盖（同套件绿）；该路径与列表删除共用 `syncSnapshot` 同一腾空分支。
- [x] 2.4 设备端套件全量回归：按 AGENTS.md 口径构建 ohosTest HAP、双 HAP 安装、`hdc shell aa test` 全量。结果（2in1 真机）：20 套件 / 229 用例，Tests run: 229, Failure: 0, Error: 0, Pass: 229，TestFinished-ResultCode: 0。
