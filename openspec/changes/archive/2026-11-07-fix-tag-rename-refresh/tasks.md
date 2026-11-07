# Tasks

## 1. 标签列表即时刷新

- [x] 1.1 修改 `entry/src/main/ets/pages/TagsPage.ets`：主列表 `ForEach` 键值改为 `${tag.id}|${tag.name}|${tag.count}`，「合并到」列表键值改为 `${other.id}|${other.name}`；以 `check_ets_files` 检查该文件无 ArkTS 错误，并运行 `hvigorw assembleHap` 成功
- [x] 1.2 在设备上复现审核步骤「标签 → 编辑 → 重命名」：保存后当前行立即显示新名称、计数不变；改名到已存在名称时来源行立即消失且目标行计数增加；确认无需切换页面后，运行 `hvigorw assembleHap` 作为收尾验证

## 2. 标签筛选同步

- [x] 2.1 修改 `entry/src/main/ets/pages/TagsPage.ets`：`rename()` 记录旧名称，成功后按「未合并用输入名、已合并用目标标签规范名」更新 `AppState.tagFilter`，仅当筛选值等于旧名称时改写；`mergeInto()` 在筛选值等于来源标签名时改写为目标标签名；以 `check_ets_files` 检查该文件无 ArkTS 错误，并运行 `hvigorw assembleHap` 成功
- [x] 2.2 设备验收筛选联动：在宽屏（≥1000vp）按标签 A 筛选后重命名 A，主页筛选条与流内容立即切到新名称且仍有原书签；把 A 合并到 B 时筛选切到 B 且不为空；重命名非当前筛选标签 B 时主页流不变；运行 `hvigorw assembleHap` 作为收尾验证

## 3. 文件夹展示面同步

- [x] 3.1 修改 `entry/src/main/ets/components/FolderPicker.ets`：`column.nodes` 的 `ForEach` 键值加入 `node.folder.name` 与 `node.totalCount`；以 `check_ets_files` 检查该文件无 ArkTS 错误，并运行 `hvigorw assembleHap` 成功
- [x] 3.2 修改 `entry/src/main/ets/components/DetailContent.ets`：抽出可重复调用的文件夹上下文刷新，`folderLabel` 始终按当前 `bookmark.folderId` 重算、`draftFolderPath` 仅在非编辑态重算，并在 `appState.refreshTick` 处理器中调用；以 `check_ets_files` 检查该文件无 ArkTS 错误，并运行 `hvigorw assembleHap` 成功
- [x] 3.3 设备验收：宽屏打开某书签详情，在侧栏重命名其所属文件夹，详情页文件夹 chip 立即显示新名称；编辑态下改选文件夹的草稿不被 `refreshTick` 覆盖；运行 `hvigorw assembleHap` 作为收尾验证

## 4. 回归与设备测试

- [x] 4.1 运行 `hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap`，安装测试 HAP 并执行 `hdc shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000`，确认 `TagSync`、`Folder`、`Repository`、`Import` 套件全部通过
- [x] 4.2 人工回归删除标签、合并标签、文件夹改名/移动、主页标签+文件夹叠加筛选，确认无新的刷新异常或空列表，并运行 `hvigorw assembleHap` 与 `codelinter -c code-linter.json5` 无 error

## 5. 文档

- [x] 5.1 在 `AGENTS.md`「代码约定」补充列表键值约定：普通 DTO 列表的 `ForEach` 键值须包含会显示的可变字段（名称/计数等），否则状态变更后行复用不刷新；以仓库内链与相关文件通读校对收尾

## Workflow follow-up

- 评审通过后归档该 change，并按归档流程把影响速查事实的结论吸收进 `AGENTS.md`。
