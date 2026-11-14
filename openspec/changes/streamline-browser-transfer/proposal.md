# Proposal

## Why

与鸿蒙端主流浏览器（华为浏览器、海泰浏览器等）的书签流转目前只有「设置 → 导入 → 文件选择器翻找」一条高摩擦路径，而平台没有第三方读取浏览器书签库的 API，文件 + 分享是仅有的两条通道。用户已确认目标浏览器均支持书签 HTML 导出/导入，应把这条通道的摩擦压到最低，并让「重复导出 → 重复导入」升级为可传导文件夹整理的合并语义，逼近单向收集同步。

## What Changes

- **HTML 文件直达导入**：分享（`general.html`）或「打开方式」进入流笺时，直接读取文件并转入既有的导入预览流程，不再落入收笺面板空 URL 分支。
- **合并导入模式**：导入预览新增可选项「按文件同步文件夹归属」——对已存在的书签，仅当其来源为浏览器导入（`source=IMPORT`）时，把文件夹归属跟随导入文件更新；手工收进的书签不受影响；无实际变化时不产生写与同步流量。
- **导出降阻**：HTML 导出默认文件名附带导出日期，导出完成后提示可在浏览器中导入。
- **批量收笺**：收笺面板粘贴支持一次提取多个链接批量收下（去重、跳过已有）；平板/2in1 分屏下支持把链接拖拽进书签流直接收下。
- **明确不做**：持续双向同步、删除传播、以浏览器为镜像的裁剪、浏览器云（华为账号）桥接、桌面浏览器 XBEL/floccus 互通。

## Capabilities

### New Capabilities

- `link-intake`: 收笺入口的批量链接接收行为——多链接粘贴批量收下与拖拽链接落库的可见结果（去重、跳过已有、失败反馈），不改变单链接分享收笺的既有行为。

### Modified Capabilities

- `bookmark-transfer`: 新增三条需求——HTML 文件经分享/打开方式直达导入预览；可选「按文件同步文件夹归属」的合并导入模式（边界为 `source=IMPORT` 存量、幂等、同步可见）；HTML 导出默认文件名附带日期。

## Impact

- 配置：`entry/src/main/module.json5`（ShareAbility 增加 `general.html` 收取 skill；EntryAbility 增加 `general.html` viewData skill）。
- 代码：`shareability/ShareAbility.ets`（HTML 分支）、`entryability/EntryAbility.ets`（导入路由）、`common/AppState.ets`（待导入 HTML 暂存）、`pages/SettingsPage.ets`（消费暂存、合并选项、导出文件名）、`repository/FlowRepository.ets`（合并导入、批量收笺写路径）、`components/InboxSheet.ets`（多链接粘贴）、`components/StreamHome.ets`（onDrop 拖拽接收）、`common/UrlUtil.ets`（多链接提取）。
- 同步：合并搬迁走 Repository 写路径（`updatedAt` + `dirty` + `notify()`），WebDAV 侧无协议变化；无新权限、无新依赖。
- 测试：`entry/src/ohosTest` 增补合并语义与多链接提取用例。
