# Proposal

## Why

宽断点（≥700vp：折叠屏展开 / 平板 / 2in1）下从列表侧彻底删除回收站书签（行菜单或批量栏「彻底删除」），右侧详情区仍显示这本已被删除的书签；同步远端墓碑清掉当前正在查看的书签时，任何断点都会出现同样的滞留。根因：`DetailContent` 的 refreshTick 刷新路径 `syncSnapshot()` 在书签已不存在时直接返回、不清空展示状态，右栏成了一具可交互的"尸体"——对着它点「恢复」报错、点「彻底删除」对空行静默谎报成功，直接违背用户直觉。

## What Changes

- **修复 `syncSnapshot()` 的「查无此笺」分支**：`repo.get(bookmarkId)` 返回 undefined 时，详情面板回到空态（对齐同文件 `load()` 既有语义），并触发既有 `onRemoved` 事件由宿主收口选中态（宽屏清空 `selectedId`、手机端弹出导航栈）。
- **补竞态守卫**：异步 `get` 返回后复查 `bookmarkId` 未在等待期间切换，防止旧响应覆盖新选中行、以及误清空新选中行的展示。
- **覆盖全部消失路径**：列表侧行菜单 / 批量彻底删除、同步远端墓碑（`purgeFromRemote` → `afterSync`）、启动期过期清理（`purgeExpired`），以及未来任何删除入口——收口在展示方，不依赖各删除入口自觉。
- **行为口径统一**：与详情面板内删除 / 恢复 / 归档的既有反应一致——「所看之物已离开此视图 → 详情腾空为『选一笺』空态」，全应用一个词汇。

## Capabilities

### New Capabilities
- `detail-vacate`: 详情面板对「当前展示的书签从事实源消失」的反应契约——腾空展示、清空选中，覆盖各删除 / 清理 / 同步路径与 phone / 折叠屏 / 平板 / 2in1 全断点。

### Modified Capabilities

（无。已核对 `navigation-shell` 的「详情页与返回语义」只约束导航 mechanics，`stream-row-actions` 只约束行操作交互本身，`webdav-sync` 只约束同步协议——三者的既有需求条文均不收编、也不需要为本变更改动。）

## Impact

- **代码**：`entry/src/main/ets/components/DetailContent.ets`（`syncSnapshot()` 的 undefined 分支 + `bookmarkId` 竞态守卫）为主落点；宿主接线宽屏侧（`pages/Index.ets` `onRemoved → clearSelection()`）已存在零改动，手机端 `PageMap onRemoved` 补一行 `clearSelection()`（与宽端口径对齐，见 design D3）。
- **不动**：数据模型、同步协议、`FlowRepository` 写路径、`main_pages.json` 路由、各删除入口（`StreamHome` 行菜单 / 批量栏）。
- **测试**：`DetailContent` 无组件级测试基建（ohosTest 全为 service/dao/逻辑层套件），验证以构建门禁 + 2in1 / 折叠屏真机 uitest 免键盘路径为准（回收站 → 点行 → 行菜单 → 彻底删除 → 确认，全程无文本输入，避开输入法拦截）；同步墓碑路径复用 `SyncEngine.test.ets` 既有 `purgesLocalWhenRemoteTombstoneArrives` 用例做回归（`purgeFromRemote` 本体由 `Snapshot.test.ets` 覆盖）。
- **兼容性**：纯缺陷修复 + 行为收口，无 schema / 权限 / API 变更；`skip_specs` 不适用（行为契约有净新增）。
