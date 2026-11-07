# Tasks

## 1. 删除占位 UI 与定位语文案

- [x] 1.1 `entry/src/main/ets/pages/SyncPage.ets`：删除「分布式」预告卡整块（约 389–402 行的 Column 区块），确认滚动区以冲突记录等真实功能区块收尾；以 `check_ets_files` 通过 + `hvigorw assembleHap` 成功收尾
- [x] 1.2 `entry/src/main/ets/components/NavigationRail.ets`：删除底部 slogan footer Column（约 76–86 行），并给 FolderPanel 容器补 `padding({ bottom: 24 })` 维持底部边距；以 `check_ets_files` 通过 + `hvigorw assembleHap` 成功收尾
- [x] 1.3 `entry/src/main/ets/pages/SettingsPage.ets`：删除「关于」区 tagline 行（「本地优先的链接收笺工具。没有账号、没有推荐、没有埋点。」），保留「流笺 FlowPage」名称与隐私告知两行；以 `check_ets_files` 通过 + `hvigorw assembleHap` 成功收尾
- [x] 1.4 `entry/src/main/ets/pages/TagsPage.ets`：删除标题下副题「文件夹记得来处，标签记下想法。」，父容器多余 spacing 一并收紧；空状态引导「收笺时写一个；标签只来自你的手。」按规格保留；以 `check_ets_files` 通过 + `hvigorw assembleHap` 成功收尾

## 2. 版本号改为读取包配置

- [x] 2.1 `entry/src/main/ets/pages/SettingsPage.ets`：`aboutToAppear()` 用 `bundleManager.getBundleInfoForSelfSync(BundleFlag.GET_BUNDLE_INFO_DEFAULT)` 读 `versionName` 存 `@Local`，右上角显示 `v${versionName}`；读取抛错时置空串并隐藏该文本，不保留任何硬编码版本。改 `AppScope/app.json5` 的 `versionName` 为临时值构建验证显示跟随后改回，以 `check_ets_files` 通过 + `hvigorw assembleHap` 成功收尾

## 3. 门禁与回归验证

- [x] 3.1 禁词残留复核：对 `entry/src/main/ets/` 与 `entry/src/ohosTest/` grep `本地优先|没有账号、没有推荐|文件夹记得来处|将在下一阶段接入|'v1.0.0'`，确认零残留；再单独 grep `数据在这台设备` 逐行人工确认命中仅为保留的状态文案（SyncPage 未配置/已断开提示），非侧边栏 slogan 复发
- [x] 3.2 `codelinter -c code-linter.json5` 通过（不新增 error）
- [x] 3.3 设备端全量回归：`hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap` 构建并 `hdc install -r` 两个 HAP 后 `hdc shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000`，202 个用例全过
- [x] 3.4 三断点人工核对：≥1000vp 宽屏侧边栏底部边距正常（FolderPanel 不贴边、无 slogan）、700–999vp 与手机端不受影响；同步页底部、标签页标题区、设置页「关于」+ 右上角版本号显示与包配置一致

## Workflow follow-up

- 实施完成后按 openspec/config.yaml 的 apply 指引检查 AGENTS.md 易变事实是否需要更新（预期无需：被删文案未被 AGENTS.md 引用）。
- 归档本变更（`openspec archive`）并在归档后复核 `openspec/specs/ui-copy/spec.md` 生成完整。
