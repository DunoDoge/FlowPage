# Spec Delta

## Purpose

浏览器书签导入导出：把 Netscape 书签 HTML 解析为文件夹树引用而非路径标签，导出时按树嵌套重建，保证「浏览器 → 应用 → 浏览器」round-trip 结构无损，并保留 ADD_DATE 时间信息。

## ADDED Requirements

### Requirement: 导入解析文件夹结构
导入 Netscape 书签 HTML 时，系统 SHALL 把嵌套文件夹结构解析为文件夹树中的逐级引用（find-or-create），书签归属其最深一级文件夹；同父同名文件夹合并为同一文件夹。

#### Scenario: 嵌套路径建立文件夹链
- **WHEN** 导入的书签位于「书签栏/开发/前端」
- **THEN** 应用内建立对应的三级文件夹链，书签归属于最深一级

#### Scenario: 同父同名文件夹合并
- **WHEN** 导入文件中同一父级下出现两个同名文件夹
- **THEN** 两者合并为同一文件夹，成员书签归属相同位置

#### Scenario: 文件夹名含斜杠保持原样
- **WHEN** 导入文件中存在名字包含「/」的文件夹
- **THEN** 名字按字面保留为单个文件夹段，不拆分为层级

### Requirement: 导入不派生路径标签
导入 SHALL NOT 依据文件夹路径生成任何标签；标签仅来源于用户手工标注。

#### Scenario: 导入后标签列表不含路径
- **WHEN** 导入带文件夹结构的书签文件
- **THEN** 标签列表不出现「书签栏/开发/前端」之类的路径字符串或路径段

### Requirement: 导入保留 ADD_DATE
导入时书签的 ADD_DATE SHALL 写入书签创建时间；缺失 ADD_DATE 的书签回退为导入时刻。

#### Scenario: ADD_DATE 写入创建时间
- **WHEN** 导入 ADD_DATE 为某历史时间的书签
- **THEN** 该书签的创建时间等于该历史时间

### Requirement: 导出嵌套重建结构
导出 Netscape 书签 HTML 时，系统 SHALL 按文件夹树输出嵌套结构：文件夹按其顺序字段排列，文件夹内书签按创建时间排列，无文件夹书签直接置于根；HTML 格式不携带标签，标签信息仅在 JSON 导出中保留。

#### Scenario: 嵌套结构按树输出
- **WHEN** 应用内存在多层文件夹且导出 HTML
- **THEN** 输出为逐级嵌套的文件夹层级，不出现名字内含「/」的扁平文件夹

#### Scenario: 标签不进入 HTML 导出
- **WHEN** 书签带有用户标签并导出 HTML
- **THEN** HTML 中不出现标签的任何表示，标签在应用内保持不变

### Requirement: 浏览器语义标记保真
导入 SHALL 捕获顶层文件夹 H3 上的 PERSONAL_TOOLBAR_FOLDER / UNFILED_BOOKMARKS_FOLDER 标记并记入该文件夹的语义类别（toolbar / unfiled；仅顶层生效、深层忽略、同名首个生效）；类别 SHALL 随文件夹记录同步；导出 SHALL 按类别回写对应标记属性；重复导入同一文件时类别赋值幂等，不产生额外同步流量。

#### Scenario: 书签栏标记 round-trip 不丢
- **WHEN** 导入含 PERSONAL_TOOLBAR_FOLDER="true" 的「书签栏」后导出 HTML
- **THEN** 输出的该 H3 带 PERSONAL_TOOLBAR_FOLDER="true"，识别标记的浏览器再导入时不把它嵌进自身书签栏

#### Scenario: 未标记文件夹不带属性
- **WHEN** 导入无标记的普通文件夹后导出
- **THEN** 该 H3 不携带任何标记属性

#### Scenario: 深层标记被忽略
- **WHEN** 源文件在非顶层 H3 上携带 PERSONAL_TOOLBAR_FOLDER
- **THEN** 该文件夹按普通文件夹处理，导出不回写标记

#### Scenario: 重复导入幂等
- **WHEN** 同一文件导入两次
- **THEN** 第二次不改变文件夹记录的 rev/updatedAt，不产生新的同步上传

### Requirement: Round-trip 结构无损
对未经用户编辑的导入数据，再次导出 SHALL 还原与源文件一致的文件夹层级与文件夹名；书签在文件夹内的顺序按创建时间（ADD_DATE）近似还原。

#### Scenario: 导入后导出还原层级
- **WHEN** 导入浏览器导出的书签 HTML 后立即导出
- **THEN** 输出文件包含与源文件相同的文件夹嵌套路径与名字，浏览器导入后结构与源一致

#### Scenario: 悬空引用落根目录
- **WHEN** 某书签引用的文件夹记录尚未同步到达本机
- **THEN** 导出时该书签置于根目录，导出过程不失败
