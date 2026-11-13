# Tasks

## 1. 分享出口模块

- [x] 1.1 新建 `entry/src/main/ets/common/ShareOut.ets`：静态 `shareBookmarks`（入参为 URL/标题/摘要列表，逐条构造 `HYPERLINK` 记录并 `addRecord`，DETAIL 预览）、`dismiss`（幂等、try/catch 吞错）、launch 前 dismiss 旧实例、context 缺失与 promise reject 走 `AppState.shared.toast('分享面板拉起失败，请重试')`；标题为空回退 URL。验证：`check_ets_files` 通过 + `hvigorw assembleHap` 成功。
- [x] 1.2 设备端测试 `entry/src/ohosTest` 新增 ShareOut 用例：标题回退、多条记录逐条构造、记录仅含 URL/标题/摘要字段。验证：`hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap` 构建通过且 `aa test` 新用例全绿。

## 2. 三入口接入

- [x] 2.1 `entry/src/main/ets/components/StreamHome.ets`：`QuickActionPanel` 非回收站分支「打开」之后加 `ActionChip('分享')` 调 `ShareOut.shareBookmarks`；回收站分支不加。验证：`check_ets_files` + `hvigorw assembleHap`。
- [x] 2.2 `entry/src/main/ets/components/StreamHome.ets`：`BatchActionBar` 非回收站分支、`selectedBookmarkIds.length > 0` 时加 `ActionChip('分享')`，从当前列表取选中书签构造记录批量交出。验证：`check_ets_files` + `hvigorw assembleHap`。
- [x] 2.3 `entry/src/main/ets/components/ReadingShell.ets`：`MoreMenu`「复制链接」后加 `MenuItem('分享')`，saved/transient 层均可用（URL=当前层 URL，标题=页面标题，摘要=saved 层书签摘要否则空）。验证：`check_ets_files` + `hvigorw assembleHap`。
- [x] 2.4 面板收口：`StreamHome` 与 `ReadingShell` 的 `aboutToDisappear` 调 `ShareOut.dismiss()`。验证：`check_ets_files` + `hvigorw assembleHap`。

## 3. 集成验收与门禁

- [ ] 3.1 真机/模拟器人工验收：三入口拉起面板并交出链接记录；批量多条一次交出；回收站视图无分享入口；仅选文件夹时无分享入口；分享后关闭面板切换页签/关闭阅读层无面板残留；面板预览呈现标题与摘要（单条 DETAIL / 多条 DEFAULT）。记录验收结论。
- [x] 3.2 构建门禁收尾：改动 `.ets` 全量 `check_ets_files` 无 ERROR、`hvigorw assembleHap` 成功、`codelinter -c code-linter.json5` 无新增 error。

## 4. App Linking（收端基础设施，发端暂缓——D7 修订）

- [x] 4.1 `common/ShareUtil.ets`：`SHARE_LINK_HOST/PREFIX` 常量与 `shareLinkOf`/`shareLinkTargetOf` 编解码（休眠保留，发端包装暂缓回退为原始 URL）。
- [x] 4.2 `module.json5`：EntryAbility 新增独立 browsable skill（https + dunodoge.com + pathStartWith "s" + domainVerify），不与 flowpage:// 深链混用。
- [x] 4.3 `EntryAbility.handleWant`：包装链接解包进阅读层（transient + autoLoad），非本域 http(s) 仍走 openInbox。
- [x] 4.4 设备端测试：编解码往返、聚合行为单行纯 URL 断言。
- [ ] 4.5 （暂缓）用户侧前置：服务器部署 `/.well-known/applinking.json` 与 `/s` 302 端点；AGC 发布 `https://dunodoge.com`。完成后恢复发端包装（ShareOut 两处 `shareLinkOf` + 测试断言）。
- [ ] 4.6 （暂缓）端到端验收：`aa start -U --pb appLinkingOnly true` 直达阅读层、`hidumper -s AppDomainVerifyManager` success、未装设备 302 原页面。

## Workflow follow-up

- 归档前按 `openspec/changes/share-out/specs/share-out/spec.md` 场景逐条对照验收结论。
- 归档后把「分享出」速查事实（三入口、`common/ShareOut.ets` 出口模块）吸收进 AGENTS.md。
