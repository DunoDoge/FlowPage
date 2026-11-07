# Design

## Context

见 `proposal.md`。当前事实：

- `TagsPage` 每次操作后都重新查询 `FlowRepository.listTags()` 并整体替换 `@Local tags`，但主列表与「合并到」列表的 `ForEach` 键值分别为 `tag.id` / `other.id`。`TagCount` 是普通 DTO（`model/Tag.ets`），不是 `@ObservedV2`。ArkUI 的 `ForEach` 在键值不变时复用既有组件、不重新执行行构建，因此名称与计数停在旧值；离开页面再回来会重建组件，才显示新值。
- 仓库已有同类正确做法：`FolderPanel` 的行键包含 `name|totalCount|depth|expanded`，`StreamHome` 的书签行键包含 `rev|updatedAt`。
- 标签筛选值 `AppState.tagFilter` 以标签名称做 SQL 等值匹配（`buildWhere` 中 `t.name = ?`）。若正被筛选的标签改名而未同步筛选值，主页会按旧名称查询而得到空/错误结果。
- `FolderPicker` 在 `appState.refreshTick` 时重新拉取 `folderTree()` 并重建 `columns`，但其行键只有 `node.folder.id`，名称与计数变化同样会被复用掩盖。
- `DetailContent` 的 `folderLabel` 只在 `bookmarkId` 变化触发 `load()` 时计算；`refreshTick` 只调用 `syncSnapshot()` 更新书签快照，不重算文件夹路径，文件夹改名后 chip 会保留旧名。

## Goals / Non-Goals

**Goals:**

- 用与仓库既有列表一致的最小改动，让标签/文件夹改名与计数变化在已挂载的界面上即时可见。
- 标签改名/合并时保持主页标签筛选与流内容一致。
- 不改变数据模型、Repository 通知链路、同步协议与无障碍标签。

**Non-Goals:**

- 不重写 `TagsPage` 的加载模型，不引入 `Repeat`/`LazyForEach` 或新的状态层。
- 不处理「删除正在筛选的标签」后的筛选清理（单独评估，避免扩大行为变更）。
- 不改变标签合并的数据库语义与 LWW/同步规则。
- 不重构阅读页目录等与改名无关的列表键值。

## Decisions

### D1：标签列表行键包含会显示的可变字段

`TagsPage` 主列表键改为 `${tag.id}|${tag.name}|${tag.count}`；「合并到」列表键改为 `${other.id}|${other.name}`。名称或计数变化时键变化，框架重建对应行，立即显示新值。

备选：

- **把 `TagCount` 改为 `@ObservedV2` + `@Trace`**：`listTags()` 每次返回新对象，`ForEach` 键不变时仍复用旧对象，必须额外实现「按 id 合并到旧对象并原地改字段」才能生效，状态面更大；否决。
- **改用 `Repeat`**：V2 能力更合适，但要点改造列表结构并引入新的渲染语义，超出本次缺陷修复；否决。
- **不做键值改动，改为手动刷新整页**：无法解决已挂载组件复用问题，且体验仍要求切换页面；否决。

### D2：标签改名/合并后同步 `AppState.tagFilter`

`TagsPage.rename()` 在调用 Repository 前记录被编辑标签的旧名称；成功后：

- 未合并：新名称即输入值（DAO 原样写入）。
- 已合并：在重命名前的列表中按 `name.toLowerCase()` 找到目标标签（排除自身），取目标标签的规范名称；找不到时回落输入值。
- 仅当 `appState.tagFilter` 等于旧名称时改写为新名称；`mergeInto(other)` 同理把筛选值改为 `other.name`。

Repository 的 `notify()` 仍负责触发主页重新查询；筛选值在通知后同步更新，`StreamHome` 的 `@Monitor('appState.tagFilter')` 会再按新条件加载一次。两次加载都由同一份已提交的 RDB 数据驱动，结果一致。

备选：

- **改名时清空筛选**：不会展示错误结果，但丢失用户上下文，需重新点选；否决。
- **让 Repository 感知 UI 筛选**：把 UI 状态耦合进数据层，破坏现有分层；否决。
- **按旧名称继续查询**：改名后必然空列表，正是本次要修的可见故障；否决。

### D3：文件夹选择器行键包含名称与计数

`FolderPicker` 的 `column.nodes` 行键改为 `${node.folder.id}|${node.folder.name}|${node.totalCount}`。该组件已在 `refreshTick` 时重拉树，补上键值即可覆盖「同步/改名后选择器仍显示旧值」。

备选：

- **保持 `node.folder.id`**：选择器打开期间远端同步改名时会保留旧行文本；与标签问题同源；否决。
- **打开时重建整个选择器**：组件生命周期不受改名事件控制，且会丢失当前列/滚动位置；否决。

### D4：详情页在库变更时重算文件夹展示名

将 `DetailContent` 的文件夹上下文刷新拆成可重复调用的方法：始终按 `bookmark.folderId` 重算 `folderLabel`；仅非编辑态时重算 `draftFolderPath`，避免覆盖用户正在选择的草稿。`refreshTick` 处理器在 `syncSnapshot()` 之外调用该刷新。

备选：

- **新增 `AppState.folderTick` 精确通知**：可减少无关写操作触发的树查询，但增加状态字段并需覆盖同步路径；当前 `refreshTick` 已能承担，先不引入。
- **不刷新，等重新进入详情**：正是审核所指的「需切换页面」症状；否决。
- **在 `syncSnapshot` 里判断 `folderId` 是否变化**：改名不改变 `folderId`，无法检测到；否决。

## Risks / Trade-offs

- [标签/文件夹行因计数变化而重建] → 标签与单层文件夹数量规模小，重建成本可忽略；避免在行内放重资源。
- [合并后按输入名找不到规范目标名] → 回落到输入值；SQL 的 `name_key` 合并仍正确，最坏只影响筛选显示的大小写形式。
- [详情页每次 `refreshTick` 多一次 `folderTree()` 查询] → 仅在该书签属于文件夹或处于编辑态时执行；树只含文件夹记录，规模有限。若后续出现大目录性能问题，再引入精确的文件夹版本信号。
- [Repository 通知与筛选值更新之间的短暂旧筛选查询] → 两次查询都针对已提交数据，第二次以新条件覆盖结果，不产生持久错误状态。
- [键值字符串拼接引入重复键] → 标签 id 唯一；文件夹 id 在同一层内唯一，拼接名称与计数不改变唯一性。

## Migration Plan

无数据迁移。改动随 HAP 升级生效；回滚仅需还原上述键值与筛选同步逻辑，RDB 与同步数据不受影响。

## Open Questions

无。
