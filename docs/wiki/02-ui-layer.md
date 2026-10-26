# 表现层

本篇说明 ArkTS/ArkUI 表现层：Ability 窗口、`Index` 的三断点布局、主要页面组件、服务卡片与主题。

## 1. `Index`：唯一主页面路由

[Index.ets](../../entry/src/main/ets/pages/Index.ets) 是 `@Entry @ComponentV2`，负责：

1. 注册 `mediaquery` 监听：`(width>=700vp)` → `isWide`，`(width>=1000vp)` → `isLarge`。
2. 恢复主题偏好并调用 `FlowRepository.init()`；成功后 `ready=true`。
3. 按断点渲染 `PhoneShell()` 或 `WideShell()`，并叠加 `InboxSheet` 与 toast。
4. 监听 `AppState.routeTick`：手机端消费一次路由请求并 push `detail`。

| 宽度 | 布局 |
|---|---|
| `< 700vp` | `Navigation` 单栏 + `StreamHome`；详情/标签/同步/设置用 `NavPathStack` 推入 |
| `700–999vp` | 两栏：列表（340vp）+ 右侧内容 |
| `>= 1000vp` | 三栏：`SideNav`（240vp）+ 列表（380vp）+ 右侧内容 |

宽屏右侧由 `AppState.pane` 决定显示 `DetailContent`、`TagsPage`、`SyncPage` 或 `SettingsPage`。
手机端 `NavDestination.onHidden` 会递增 `streamRefresh`，让从详情/设置返回时首页重新加载——系统返回手势也覆盖。

启动时若宽屏且没有选中项，会自动选中列表第一条；手机端不自动打开详情。

## 2. 首页流

[StreamHome.ets](../../entry/src/main/ets/components/StreamHome.ets) 负责列表、筛选和搜索：

- 数据源是 `FlowRepository.queryPage()`（SQL 过滤/排序/分页，每页 50 条），首次加载同时取汇总与今日计数；
  滚动到底继续 `queryPage(offset)`，`load()` 用世代 token 丢弃过期结果。
- 筛选：全部 / 未读 / 星标 / 归档 / 回收站；非回收站视图会排除 `deleted`，非归档视图会排除 `archived`。
- 搜索框 120ms 防抖，在 `Bookmark.searchText` 上做小写子串匹配；与 `AppState.tagFilter` 叠加。
- 标签筛选来自标签页，首页顶部显示可清除的“标签：xxx”条。
- 列表项 key 为 `id:rev:updatedAt`，编辑或同步后强制重建对应行。
- 空态区分“纸还空着 / 没有找到 / 回收站是空的”，空回收站不显示收笺入口。
- 顶部“粘贴”使用 `PasteButton` 获取剪贴板授权，`extractFirstUrl()` 找到第一个链接后打开收笺面板。

[BookmarkRow.ets](../../entry/src/main/ets/components/BookmarkRow.ets)：未读左侧竖线、两行标题、一行摘要、域名 ·
相对时间、最多两个标签；右侧星标按钮 32vp 视觉宽度、44×44vp 热区。

## 3. 详情页与阅读模式

[DetailContent.ets](../../entry/src/main/ets/components/DetailContent.ets) 同时用于手机（`compact=true`）和
宽屏右侧（`compact=false`），内容最大宽度 680vp。

- 打开时按 `bookmarkId` 读取；若是未读且未删除，自动 `setRead(READING)`，停留 30 秒后转 `READ`。
- 三个页签：正文、摘录、备注。正文由 [ReaderView.ets](../../entry/src/main/ets/components/ReaderView.ets)
  渲染；只要 `snapshotPath` 可读就读取（不要求 `snapshotStatus === DONE`），旧纯文本快照按段落降级。
- 正文页签内是行内阅读器：按段落/标题/引用/列表/代码块渲染，链接用下划线 + 墨色 `Span` 呈现并可点击；
  支持选中文本“存为摘录”；工具栏提供“字号”和“专注阅读”。
- **ReaderView 分窗挂载**：首屏只渲染前 `INITIAL_BLOCKS=200` 块（`visibleCount`），
  `SelectionContainer` 只包住已挂载块，单页节点数与内存随窗口而非全文增长。滚到已渲染内容底部
  （`onScrollEdge(Bottom)`）或点底部「继续阅读 · n/total」时按 `BLOCK_BATCH=200` 追加。
  目录/搜索跳转先 `ensureMounted(index)`；位置恢复若目标在窗口外会扩窗并重试（10 × 200 ms，
  超大页上该预算时序敏感——重试耗尽即回落顶部，已知边角见 AGENTS.md）。
  未全量挂载时进度按块下标估算，全量挂载后仍用像素比例；批次边界不会提前标记已读（`onReadComplete` 在全量挂载后进度 ≥90% 或到达末尾时触发）。
  实测 648 块页面：专注阅读首帧 2.5 s → 0.4 s，单次链接点击的主线程阻塞 5.7–7.2 s → 0.36–0.53 s。
- **ReaderView 搜索走 taskpool**：`applySearch` 异步化——索引（小写全文 + 每块偏移）按 `articleSignature`
  惰性构建并缓存（1,999 块约 6 ms，一次性留在 UI 线程），检索交给 `ReaderSearchService`（2 s 超时 + 同步回退），
  世代 token 丢弃过期结果；关闭搜索或换文/换书签时释放索引。命中集合与同步扫描严格等价
  （大小写不敏感、块内 containment、不跨块）。
- “专注阅读”打开 [ReadingShell.ets](../../entry/src/main/ets/components/ReadingShell.ets)（`Index` 根部
  `bindContentCover`，`enableSafeArea=true`）；`ReadingShell` 统一承载阅读栈与内置 Web，`ReaderView` 负责正文排版。
- 阅读模式点正文链接：http(s) 文档由 `ReaderPageLoader` 原生抓取后 push 临时条目；非文档链接直接进内置浏览器。
  临时页显示「临时阅读」，不写 RDB/阅读位置，底部与菜单提供「收藏这一页」。
- 顶部返回/系统返回/ESC 逐层回退：先走 Web 历史，再回到已有正文，再弹出条目，最后关闭覆盖层；
  系统返回由 ContentCover `onWillDismiss` 转为 `readingBackTick`。
- **阅读栈内存形态机**：`back()` 出栈即裁掉 `entries` 尾部（被弹层无前进路径，直接可 GC）；push 后 600 ms
  空闲把非当前层 `article` 压为 `ArticleCodec.encode()` 串（`entry.compact`），pop 回到该层时 decode 重建
  （648 块约 12–15 ms）。20 层下钻后逐层 pop 的 VmRSS 由恒定不降变为递降回收（第三轮实测 419.6 → 380 MB）。
- 内置浏览器为单标签 ArkWeb：地址可编辑，支持前进/后退/刷新、加载进度与错误态；「阅读」从实时 DOM 提取正文，
  生成新的临时阅读条目；「网页」从阅读模式回到当前 URL。
- `ReadingShell` 顶栏的阅读/网页切换使用组件内 `@Local mode`，避免 `@Builder` 参数标签不随状态刷新的问题。
- 阅读偏好（字号 15–23fp、行距三档、段距三档）存在 `flowpage_settings`；根书签阅读位置按书签存在
  `flowpage_reader`，临时页位置只在内存中，均不参与 WebDAV 同步。
- 正文页签固定显示“重新抓取”，可在提取规则更新后覆盖旧快照；没有快照时也显示“重试抓取”。
- 编辑态保存标题、标签、摘录、备注；标签同时按英文逗号和中文逗号切分并去重。
- 操作：打开原文（应用内浏览）、系统浏览器、分享原文 URL（`systemShare`）、复制 `flowpage://bookmark/{id}` 深链、
  星标、归档、查链接、重新抓取、删除。
- 删除是软删除并提示 30 天；已在回收站时提供“恢复 / 彻底删除”，彻底删除会先确认并删除快照。
- “查链接”调用 `MetadataService.checkLink()`，写入 `link_status`（1 可用 / 2 可能失效 / 0 未判断）。

## 4. 收笺与分享

- [InboxSheet.ets](../../entry/src/main/ets/components/InboxSheet.ets)：首页底部面板，可预填深链带来的 URL；
  校验 `isValidHttpUrl()` 后保存，来源固定为 `BookmarkSource.MANUAL`；新建成功才异步抓元数据。
- [SharePage.ets](../../entry/src/main/ets/pages/SharePage.ets)：`ShareAbility` 加载的 `@Entry` 页面，
  从 `AppStorage` 读 `shared_url` / `shared_title`；保存来源为 `SHARE`，无备注；保存后 `terminateSelf()`。
- [ShareAbility.ets](../../entry/src/main/ets/shareability/ShareAbility.ets)：用 `systemShare.getSharedData()`
  遍历 records，标题取首个非空 `title`，URL 从 `content` 或 `uri` 中用 `extractFirstUrl()` 提取。
  `module.json5` 只声明 `general.hyperlink` 与 `general.text` 两种 UTD。

## 5. 标签、同步、设置

- [TagsPage.ets](../../entry/src/main/ets/pages/TagsPage.ets)：按使用次数倒序列出标签；点标签写入
  `AppState.tagFilter` 并返回首页；支持重命名、删除（只解除关联）、合并到另一标签。
- [SyncPage.ets](../../entry/src/main/ets/pages/SyncPage.ets)：WebDAV 地址/账号/应用密码；测试连接只做
  PROPFIND，不保存配置；“连接并同步”才保存配置并执行同步。凭据失效时要求重新输入。分布式同步入口
  目前只是“下一阶段接入”的说明文字。
- [SettingsPage.ets](../../entry/src/main/ets/pages/SettingsPage.ets)：主题、数据统计、导入浏览器 HTML、
  导出 JSON/HTML、清空数据、关于。导入文件通过 `DocumentViewPicker` 选择 `.html/.htm`。
  导入时保留文件夹为标签；导出 HTML 使用 Netscape 书签格式。

## 6. 主题与视觉约定

- 颜色全部来自 `$r('app.color.*')`：`paper` / `surface` / `surface_alt` / `ink` / `ink_secondary` /
  `ink_tertiary` / `line` / `line_strong` / `inverse_ink` / `danger` / `overlay` / `highlight`。
  `resources/base/element/color.json` 与 `resources/dark/element/color.json` **必须成对维护**。
- 风格是米白纸面 + 墨色文字 + 发丝线，无彩色渐变；`danger`（朱砂）只用于删除类操作。
- 主题模式存 `flowpage_settings.theme_mode`（`system` / `light` / `dark`），通过
  `ApplicationContext.setColorMode()` 应用；`Index` 启动时恢复，`SettingsPage` 修改。
- 当前没有 i18n 层：页面文案是内联中文；只有应用名/Ability/卡片描述在 `string.json`。
  新增文案沿用现有内联方式，不要引入只改一半的资源体系。

## 7. 服务卡片

[TodayCard.ets](../../entry/src/main/ets/widget/pages/TodayCard.ets)（2×2）和
[RecentCard.ets](../../entry/src/main/ets/widget/pages/RecentCard.ets)（2×4）位于 `widget/pages/`，
是 FormKit 的 `@Entry` 卡片页面。

- 这是全仓库**唯一**使用 V1 `@Component` + `@LocalStorageProp` 的地方，不能改成 V2。
- 数据由 `CardSnapshot` 写入 `flowpage_card` preferences，字段为 `today_title` / `today_domain` /
  `today_id` / `recent_lines` / `total_count` / `today_candidates`。
- `recent_lines` 与 `today_candidates` 是「标题 `%01` 域名 `%01` id」以换行分隔的字符串，三个字段各自
  `encodeURIComponent`；`%01` 是不会出现在编码结果中的可打印 ASCII。不要改用 `\u0001` 等控制字符：
  preferences 以 XML 存储，控制字符会让整个文件变成 `*.broken`，卡片进程只能读到默认值。标题写入前
  还会压成单行并清掉控制字符。点击用 `postCardAction({ action: 'router' })` 带 `bookmarkId` 拉起
  `EntryAbility`（解析统一走 `common/CardFormat.ets`）。
- 卡片配置在 `resources/base/profile/form_config.json`，Ability 为 `TodayCardAbility`。
