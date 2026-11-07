# Proposal

## Why

应用审核在「标签 → 编辑 → 重命名」路径发现：保存新名称后，标签列表仍显示旧名称与旧计数，必须离开页面再回来才更新。根因是列表项键值只含稳定 id，而 `TagCount` 不是可观察对象；数据源整体替换后 `ForEach` 按相同键值复用旧组件，不会重新执行行内容构建。同一类「改名/计数变化后列表不刷新」的风险还存在于其他以稳定 id 作键、却展示可变字段的列表，以及详情页缓存的文件夹名称。

## What Changes

- 修复标签列表：重命名、合并、删除后，标签名称与计数在列表内立即更新，无需切换页面。
- 修复标签重命名后的筛选联动：当主页正按被改名标签筛选时，筛选条件同步改为新名称；合并时同步为目标标签名称。
- 按同一键值规则排查并加固其他列表：文件夹选择器的文件夹名称/计数、详情页文件夹 chip 在文件夹改名后即时更新。
- 不改变数据模型、同步协议、RDB 表结构与用户可见文案。

## Capabilities

### New Capabilities

- `tag-management`: 标签列表的展示与实时刷新契约，包括改名、合并、删除后的名称/计数即时一致性，以及改名与主页标签筛选的联动。

### Modified Capabilities

- `bookmark-folders`: 文件夹改名的可见结果补充「已打开的详情页与文件夹选择器同步新名称」，不改变改名只写文件夹记录、不重写成员的既有语义。

## Impact

- 代码：`entry/src/main/ets/pages/TagsPage.ets`、`entry/src/main/ets/components/DetailContent.ets`、`entry/src/main/ets/components/FolderPicker.ets`，以及必要的列表键值生成函数。
- 数据与同步：无 schema、无迁移、无 WebDAV 协议变化；标签/文件夹改名仍走现有 Repository 通知链路。
- 测试：设备端 `TagSync`、`Folder`、`Repository` 套件需保持通过；新增针对列表键值与筛选联动的可验证断言。
- 文档：若最终结论影响 AGENTS.md 的「刷新靠 tick / ForEach 键值」约定，按归档流程吸收。
