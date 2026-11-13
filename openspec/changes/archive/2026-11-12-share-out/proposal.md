# Proposal

## Why

应用目前「只进不出」：`ShareAbility` 能接收系统分享进来的链接，但用户想把一条书签发给其他应用、其他设备时，只能手动复制 URL 再粘贴。PRD V1.1 已把碰一碰/隔空传送列入规划，而它们的前置基础正是「把书签作为标准分享数据交出去」；接入系统分享面板后，面板自带的「复制到中转站」等系统动作还能免费获得中转站/跨端流转入口，是当前唯一无外部依赖（无新权限、无 AGC/域名配置、单机可验收）的跨端能力。

## What Changes

- 新增「分享出」能力：通过 Share Kit `systemShare` 拉起系统分享面板，把书签以标准 `HYPERLINK` 记录（URL + 标题 + 摘要）交出。
- 新增三个分享入口，行为一致：
  - 书签行「…」锚定面板（`QuickActionPanel`）加「分享」动作；
  - 阅读层「⋯」菜单（`ReadingShell.MoreMenu`，含临时链接页）加「分享」菜单项；
  - 批量多选栏（`BatchActionBar`）对已选书签支持一次分享多条记录。
- 分享只交出链接与文本元数据（URL、标题、摘要），不涉及正文快照，与现有同步隐私口径一致。
- 不改动收向链路（`ShareAbility`、收笺面板）、不加新权限（仍仅 `INTERNET`）、不加第三方依赖。

## Capabilities

### New Capabilities

- `share-out`: 书签对外分享——从三个入口以标准超链接记录发起系统分享，单条与多条、已保存与临时页行为一致。

### Modified Capabilities

<!-- 无既有能力的需求变更：interaction-feedback 与 ui-copy 的既有要求对新入口自然适用，不修改其 requirement。 -->

## Impact

- `entry/src/main/ets/components/StreamHome.ets`：`QuickActionPanel` 与 `BatchActionBar` 新增分享动作。
- `entry/src/main/ets/components/ReadingShell.ets`：`MoreMenu` 新增分享菜单项。
- 新增分享出口模块（构建 `SharedData` 并拉起 `ShareController`，含面板生命周期处置），复用 `AppState.abilityContext`。
- `module.json5`、`oh-package.json5` 无变化；`@kit.ShareKit` / `@kit.ArkData` 为系统 kit。
- 设备端测试（`entry/src/ohosTest`）新增分享出口用例。
