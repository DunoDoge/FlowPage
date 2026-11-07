# Proposal

## Why

应用准备发布公开测试。当前 UI 中存在一处为未实现功能预埋的占位卡（同步页「分布式」），以及散布在侧边栏、设置「关于」、标签页副题等处的定位/抒情式短语；这些文案面向开发者自证设计意图，对公测用户只添噪音。另外设置页版本号硬编码 `v1.0.0`，公测迭代后必然失真。

## What Changes

- 删除同步页「分布式」占位卡（`SyncPage.ets` 底部「将在下一阶段接入」区块）——全应用唯一的未实现功能占位 UI。
- 删除宽屏侧边栏底部 slogan「本地优先 / 数据在这台设备上」（`NavigationRail.ets` footer）。
- 删除设置页「关于」tagline「本地优先的链接收笺工具。没有账号、没有推荐、没有埋点。」。
- 删除标签页副题「文件夹记得来处，标签记下想法。」。
- **保留**（不做改动）：数据行为/隐私告知文案（如「流笺不读取其他浏览器的书签数据库」「同步只上传链接与标签，不上传正文快照」「云端保留，下次同步会恢复」）、同步页状态文案（「已断开。数据仍在这台设备上。」等）、空状态引导、输入占位提示、toast 与确认弹窗——公测用户需要这些实际信息。
- 设置页右上角版本号从硬编码 `v1.0.0` 改为运行时读取包配置 `versionName`。

## Capabilities

### New Capabilities

- `ui-copy`: 应用内文案与占位元素规范——约束公开展示面上占位 UI 的禁用、文案分层（定位语不得出现、数据行为告知必须保留）与版本号真实性。

### Modified Capabilities

（无——`immersive-ui` 管安全区背景、`webdav-sync` 管同步语义，本次改动不触及它们的既有需求。）

## Impact

- 代码：`entry/src/main/ets/pages/SyncPage.ets`（删占位卡）、`components/NavigationRail.ets`（删 footer）、`pages/SettingsPage.ets`（删 tagline + 版本号改读 `bundleManager`）、`pages/TagsPage.ets`（删副题）。
- 无数据模型、权限、依赖、路由变化；无 **BREAKING**。
- 设备端测试若断言了上述文案需同步调整（探查中未发现引用，实施时以 grep 复核）。
