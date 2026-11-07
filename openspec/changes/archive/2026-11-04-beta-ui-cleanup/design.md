# Design

## Context

见 proposal.md 的动机。现状事实：全应用仅一处未实现功能占位（`SyncPage.ets` 的「分布式」卡）与四处定位式短语（`NavigationRail.ets` footer、`SettingsPage.ets` 关于 tagline、`TagsPage.ets` 副题）；设置页版本号为硬编码字符串。文案均为内联中文（项目无 i18n 层，AGENTS.md 约定如此）。

## Goals / Non-Goals

**Goals:**

- 占位区块与定位语整块删除，不留空壳容器。
- 删除处周边布局（间距、留白、底部安全边距）视觉上自然收口。
- 版本号运行时取自包配置，异常时有确定回退。

**Non-Goals:**

- 不引入集中文案表 / i18n 层（项目明确无此层）。
- 不改动保留类文案（数据行为告知、空状态引导、输入提示、toast、弹窗）的措辞。
- 不新增「关于」页信息（版本号之外不加更新日志、反馈入口等）。

## Decisions

### D1：整块删除，不留占位容器

每处删除直接移除对应 `Column`/`Text` 节点及其容器样式，而非保留空容器或替换为空串。
备选：留空容器（`if (false)` 或空文本）占位——否决：留下死代码与无意义留白，正是本次要清除的「占位」本身。

- `NavigationRail.ets`：footer Column（含 slogan 两行及其 `padding({ left: 24, bottom: 24 })`）删除；`FolderPanel` 容器（`layoutWeight(1)`）会自然延伸到底，需给该容器补 `padding({ bottom: 24 })` 维持底部边距。
- `SyncPage.ets`：「分布式」整张卡片 Column 删除，滚动区以冲突记录区块收尾。
- `SettingsPage.ets`：关于区 tagline `Text` 删除，保留「流笺 FlowPage」名称与隐私告知两行。
- `TagsPage.ets`：标题下副题 `Text` 删除，若父容器 `space` 因此产生多余间距则一并收紧。

### D2：版本号读 `bundleManager`，aboutToAppear 一次同步读取

`SettingsPage.aboutToAppear()` 中调用 `bundleManager.getBundleInfoForSelfSync(BundleFlag.GET_BUNDLE_INFO_DEFAULT)` 取 `versionName`，存 `@Local`，显示为 `v${versionName}`；读取抛错时置空串并隐藏该 `Text`（`visibility` 按内容为空判断），不回退显示任何硬编码版本。
备选一：继续硬编码——否决，公测迭代必失真，正是要修的问题。
备选二：异步 `getBundleInfoForSelf()` + Promise——否决，设置页非热点路径但同步 API 更简单，且避免首帧闪旧值；该 API 为 SDK 公开同步接口，无线程问题。
备选三：从 `AppScope/app.json5` 构建期注入——否决，无现成通道，为一条字符串引入构建改动不成比例。

### D3：保留清单显式化，靠 grep 门禁防回归

被删短语（`本地优先`、`数据在这台设备`、`分布式`、`没有账号`、`文件夹记得来处`、`将在下一阶段接入`、硬编码 `v1.0.0`）作为禁词在实施收尾时对 `entry/src/main/ets/` 与 `entry/src/ohosTest/` 全量 grep 复核；注意 `SyncPage` 的 `已断开。数据仍在这台设备上。` 与未配置态 `数据只在这台设备上。` 属保留的状态/告知文案，不命中禁词的精确匹配（grep 用完整短语「本地优先」「数据在这台设备上」并人工复核命中行）。
备选：引入 lint 规则自动拦截——否决，codelinter 无自定义中文文案规则通道，grep 门禁已足够。

## Risks / Trade-offs

- [宽屏侧边栏底部留白变化] → 补 padding 后需在 ≥1000vp 断点人工核对 FolderPanel 底缘不贴边、无滚动异常（`clip(false)` 行为不变）。
- [`getBundleInfoForSelfSync` 在极端环境抛错] → 空串回退隐藏版本号；不会显示错误版本。
- [设备端测试（ohosTest 16 套件）可能断言被删文案] → 探查未发现引用；实施时先 grep `ohosTest/` 复核，再跑全量设备端套件。
- [删除后视觉密度变化（同步页、标签页变短）] → 纯减法，无功能影响；人工过一遍三断点即可。

## Migration Plan

纯 UI 删除与一处读取方式变更，无数据/存储/同步影响。回滚即 revert 对应提交。

## Open Questions

无。
