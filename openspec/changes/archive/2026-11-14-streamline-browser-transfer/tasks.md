# Tasks

## 1. HTML 文件直达导入

- [x] 1.1 `entry/src/main/module.json5`：`ShareAbility` skill 增加 `general.html`（scheme file、maxFileSupported 1）；`EntryAbility` 增加 `entity.system.browsable` + `ohos.want.action.viewData` + `general.html` skill。收尾：`hvigorw assembleHap` 通过
- [x] 1.2 `entry/src/main/ets/common/AppState.ets`：新增 `pendingImportHtml: string` 暂存字段。收尾：`check_ets_files` + `hvigorw assembleHap`
- [x] 1.3 `entry/src/main/ets/shareability/ShareAbility.ets`：onSessionCreate 分支——uri 以 `.html`/.htm 结尾（或 utd 命中）时会话内读完文件字符串、暂存 `AppState`、`terminateSelf()` 并 `startAbility` 拉起主入口（带导入标记）；`general.text` 单链接路径行为不变。收尾：`check_ets_files` + `hvigorw assembleHap`；真机验证分享书签 HTML 文件直达导入预览
- [x] 1.4 `entry/src/main/ets/entryability/EntryAbility.ets` 与 `entry/src/main/ets/pages/SettingsPage.ets`：want 路由新增导入分支（导入标记 / `general.html` viewData uri → 读文件 → 暂存 → `pane=SETTINGS`）；SettingsPage 激活时消费暂存走 `previewHtml` 预览；非书签 HTML 出空态提示不落库。收尾：`check_ets_files` + `hvigorw assembleHap`；真机验证「打开方式」路径与空态

## 2. 合并导入模式

- [x] 2.1 `entry/src/main/ets/repository/FlowRepository.ets`：`ImportOptions` 增加 `mergeFolders`（默认 false）；`importHtml` 命中存量且开启时，仅 `source=IMPORT` 且目标链不同才搬迁（复用 `resolveFolderChain`），先比较后写、单次 `notify()`。收尾：`check_ets_files` + `hvigorw assembleHap`
- [x] 2.2 `entry/src/main/ets/model/ImportPreview.ets` 与 `entry/src/main/ets/pages/SettingsPage.ets`：预览统计可搬移数；预览区新增「按文件同步文件夹归属」Toggle（默认关）。收尾：`check_ets_files` + `hvigorw assembleHap`
- [x] 2.3 `entry/src/ohosTest`：合并语义设备用例——搬迁传导、非 IMPORT 来源不动、同文件重复合并第二次不改变 rev/updatedAt。收尾：ohosTest 套件执行通过

## 3. 导出降阻

- [x] 3.1 `entry/src/main/ets/pages/SettingsPage.ets`：HTML 导出默认文件名 `flowpage-bookmarks-YYYYMMDD.html`（当日）；导出完成提示改为「已导出，可在浏览器书签导入中使用」，JSON 与失败清单命名不变。收尾：`check_ets_files` + `hvigorw assembleHap`；真机导出一次核对文件名与提示

## 4. 批量收笺

- [x] 4.1 `entry/src/main/ets/common/UrlUtil.ets`：模块级正则实现 `extractAllUrls`（仅显式 http(s)、`trimPunctuation`、保持 `extractFirstUrl` 不变）；`entry/src/ohosTest` 补提取用例（多行多链接、去重、无 scheme 不认、中文标点截尾）。收尾：`check_ets_files` + `hvigorw assembleHap` + 用例通过
- [x] 4.2 `entry/src/main/ets/repository/FlowRepository.ets`：新增 `saveUrls(urls, source)`——逐条按单链接保存语义去重、单次 `notify()`、返回收下/跳过计数。收尾：`check_ets_files` + `hvigorw assembleHap`
- [x] 4.3 `entry/src/main/ets/components/InboxSheet.ets`：PasteButton 点击后 `extractAllUrls`，展示识别数量 +「全部收下」，完成后汇总 toast「收下 N 条、跳过 M 条」；无可识别链接提示且面板不变。收尾：`check_ets_files` + `hvigorw assembleHap`；真机粘贴多链接验证
- [x] 4.4 `entry/src/main/ets/components/StreamHome.ets`：列表根容器 `allowDrop([HYPERLINK, PLAIN_TEXT])` + `onDrop` → 提取链接 → `saveUrls(..., BookmarkSource.BROWSER)` + 轻提示；`FolderDragSession` 活跃时忽略。收尾：`check_ets_files` + `hvigorw assembleHap`；平板/2in1 真机验证浏览器拖入落库、重复拖入跳过、内部书签/文件夹拖拽全路径回归

## 5. 收口

- [x] 5.1 全量 `codelinter -c code-linter.json5`（0 error）+ 设备端全量套件（16 套件 + 本变更新增）执行通过 + `hvigorw assembleHap` 最终产物构建
- [x] 5.2 更新 `AGENTS.md` 易变事实（HTML 文件直达导入入口、合并模式语义、批量收笺入口），纯文档任务以全量内链 grep 校对收尾

## 6. 真机反馈修复

- [x] 6.1 分享进流笺不出预览：`general.html` skill 从 `ShareAbility` 挪到 `EntryAbility`（`viewData`+`sendData`，官方收文件模式），分享面板直接拉起主应用、`getSharedData` 趁授权新鲜读文件；`ShareAbility` 回退纯单链接收笺。收尾：`check_ets_files` + `hvigorw assembleHap` + 套件 225/225
- [x] 6.2 批量粘贴只有数量说明不直观：`InboxSheet` 批量区改为链接清单预览（域名 + 完整 URL、可滚动、点击移除），按钮文案「收下这 N 条」。收尾：`check_ets_files` + `hvigorw assembleHap`
- [x] 6.3 design.md D1/D3 与 `AGENTS.md` 对应条目同步修订（含首版方案否决记录）
- [x] 6.4 分享面板出现「收进流笺/流笺」双入口：UTD 中 `general.html` 是 `general.text` 子类型，收笺扩展声明父类型把 HTML 文件也吸进来——`ShareAbility` skill 收窄为精确类型 `general.hyperlink` + `general.plain-text`，HTML 文件唯一入口为主应用。收尾：`hvigorw assembleHap` + 套件 225/225 + 文档同步

## Workflow follow-up

- 实现完成后按项目流程走 `/openspec-verify-change` 校验，再归档（archive 后按 AGENTS.md 吸收结论）。
