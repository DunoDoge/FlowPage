# Design

## Context

见 proposal.md「Why」。现状事实：导入/导出唯一入口在 `SettingsPage`（DocumentViewPicker）；`ShareAbility` 只按 `extractFirstUrl` 提取单链接落收笺面板，HTML 文件记录会解析出空 URL；`importHtml` 是 skip-by-url_key 的纯增量合并，不更新已有书签的归属；平台无浏览器书签 API，文件 + 分享是仅有的通道（探索阶段已与用户确认）。

## Goals / Non-Goals

Goals：把「导出 HTML → 进流笺」压缩到一次分享/打开；让重复导入能传导浏览器端文件夹整理（合并语义）；批量收笺（多链接粘贴、拖拽）。
Non-Goals：持续同步、删除传播、镜像裁剪、浏览器云桥接、解析 taskpool 化（沿用现状，超大文件的解析线程优化另立变更）。

## Decisions

### D1 HTML 文件接收：主 Ability 直收（官方收文件模式），不经分享扩展

- `module.json5`：`EntryAbility` 注册 `ohos.want.action.viewData` + `ohos.want.action.sendData` 双动作 skill（`scheme: file`、`utd: general.html`、`maxFileSupported: 1`，无 entities——官方 FAQ 同款）；`ShareAbility` 保持只收单链接文本，且 skill 必须用**精确类型** `general.hyperlink` + `general.plain-text`——UTD 里 `general.html` 是 `general.text` 的子类型，声明父类型 `general.text` 会把 HTML 文件也吸进收笺扩展，分享面板出现「收进流笺/流笺」双入口（真机反馈），勿改回。
- 分享路径：分享面板直接拉起 `EntryAbility`，`handleWant` 检测 `action === sendData` → `systemShare.getSharedData(want)` 取 HTML 文件记录 → 趁 want 授权新鲜读成字符串 → `AppState.pendingImportHtml` + `pane=SETTINGS`，`SettingsPage` 双 Monitor 消费进导入预览。
- 打开方式路径：viewData want 的文件 uri 后缀判定 → 同一读文件与暂存链路。
- 首版（已被真机反馈否决）：`general.html` 挂在 `ShareAbility`，会话内读文件暂存后再 `startAbility` 带标记拉起主入口——真机实测分享进来不出预览（中转链路：会话读权限、跨 Ability 拉起、状态接力，任一环脆弱即断），且官方 FAQ 的推荐模式就是主 Ability 直收。勿改回。
- 备选 A：分享会话内嵌预览——否决：需在 `SharePage` 复刻预览/进度/取消 UI，双份维护且面板空间不足。

### D2 合并模式：仅 `source=IMPORT` 存量跟随归属，比较后写、单次 notify

- `ImportOptions` 增加 `mergeFolders: boolean`（默认 false）。`importHtml` 主循环在命中 `existingKeys` 且 `mergeFolders` 时：查该书签当前 `source` 与 `folderId`，仅 `source === IMPORT` 且目标链不同才搬迁；目标链复用 `resolveFolderChain` 的 folderCache。
- 搬迁走 Repository 标准写路径（更新 `updatedAt`、置 `dirty`），循环结束后单次 `notify()`——与批量移动同构，同步侧零协议变化。幂等由「先比较 folderId 再写」保证，重复合并零流量（对应 spec 场景）。
- 预览界面：`Toggle`「按文件同步文件夹归属」，默认关；`previewHtml` 附带可搬移数预估（新增统计：命中存量中 `IMPORT` 来源的条数）。
- 备选 A：全部存量跟随——否决：覆盖用户在应用内的手工组织（探索阶段已否决）。
- 备选 B：镜像裁剪（删掉文件中不存在的导入书签）——否决：流笺是归档库，不应被源端删除连坐；且删除需墓碑，放大同步副作用。

### D3 批量收笺：显式 scheme 提取 + 单次汇总写

- `UrlUtil` 新增模块级正则（全局化现有 `https?://` 模式 + `trimPunctuation`）实现 `extractAllUrls`：只认显式 http(s) 链接，不做裸域名推断（批量场景噪声不可接受）；`extractFirstUrl` 保持现状不动。
- `InboxSheet`：`PasteButton` 点击后 `extractAllUrls`，面板内展示**链接清单预览**（域名 + 完整 URL、可滚动、点一条移除一条——真机反馈：只报数量不直观），确认「收下这 N 条」后走 `saveUrls` 并汇总 toast（收下 N、跳过 M，全跳过时提示「这些都已收过」）。单链接粘贴保持旧行为（含裸域名回退）。新增 `FlowRepository.saveUrls(urls, source)`——内部循环复用单链接保存语义（去重跳过已有），单次 `notify()`。来源沿用收笺面板现有保存的 source 取值。
- 修订记录：首版批量区只有「识别到 N 条链接」一行文字说明，真机反馈不直观，改为清单预览。
- 拖拽：`StreamHome` 列表根容器 `allowDrop([HYPERLINK, PLAIN_TEXT])` + `onDrop`：从 `DragEvent` 取 uri/content → 提取 → `saveUrls(..., BookmarkSource.BROWSER)`（枚举已有值，不新增）。`FolderDragSession` 活跃时忽略外部 drop（内部书签拖拽会话优先，避免自吞）。
- 备选 A：拖放也弹收笺面板预填——否决：拖放语义是快速归档，多一步确认违背初衷。
- 备选 B：`extractAllUrls` 兼做裸域名推断与单链接对齐——否决：单链接场景用户看得见结果可改，批量场景错收不可逆。

### D4 导出降阻：文件名带日期 + 收口提示

- `saveText` 调用处生成 `flowpage-bookmarks-YYYYMMDD.html`（当日）；HTML 导出 toast 改为「已导出，可在浏览器书签导入中使用」。JSON/失败清单导出命名不变。
- 备选：文件名带时分秒——否决：冗长且对浏览器导入侧排序无增益。

## Risks / Trade-offs

- [分享文件读权限随会话失效] → 在 `onSessionCreate` 内读完转成字符串暂存，绝不跨会话持有 uri。
- [`UIExtensionContext.startAbility` 拉起主应用的行为差异] → 实现时真机验证；失败兜底：toast 引导用户打开应用，暂存仍在 `AppState`，主应用下次启动消费。
- [同一 HTML 文件同时命中 `general.html` 与 `general.text` 两条 skill] → 分支判定以 uri 后缀为准，与声明解耦；`general.text` 单链接路径行为不变。
- [内部书签/文件夹拖拽与外部链接拖入同容器冲突] → `FolderDragSession` 活跃时忽略外部 drop；真机回归内部拖拽全路径。
- [合并模式取消语义] → 沿用现有导入取消：已搬迁部分保留，无回滚（与既有写入语义一致，预览文案说明）。
- [超大文件解析仍在 UI 线程] → 沿用现状（既有进度反馈），不在本变更扩展；如真机复测出现卡顿另立性能变更。

## Migration Plan

纯增量：新入口、新可选项、新接收通道；无 schema、无同步协议、无权限变化。回滚 = 还原代码 + 删除两条 skill 声明，存量数据不受影响。

## Open Questions

- 两家浏览器重复导入同一 HTML 是否去重——只影响回写频率（重复条目会不会涨），真机观察即可，不影响本设计。
- `HYPERLINK` UTD 拖拽物在浏览器侧的实际数据形态（uri 还是 text）——实现时真机验证，两种都兼容（提取函数已覆盖）。
