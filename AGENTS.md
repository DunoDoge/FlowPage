# AGENTS.md — FlowPage / 流笺

本地优先的 HarmonyOS 链接收笺应用：单 HAP（`entry`），ArkTS + ArkUI 状态管理 V2，RDB 为唯一事实源，WebDAV 增量同步。
完整分层说明见 [docs/wiki/](docs/wiki/README.md)；本文件只记录代理容易踩错的事实。

## 项目快照

| 项 | 值 |
|---|---|
| 包名 / 版本 | `com.dunodoge.flowpage` / 1.0.0（`AppScope/app.json5`） |
| 平台 | HarmonyOS Stage 模型，API 26，phone / tablet / 2in1 |
| 模块 | 仅 `entry`（HAP）；无 HAR、无多端模块、无第三方运行时依赖 |
| 状态 | `@ObservedV2` + `@Trace` + `@ComponentV2` + `@Local` / `@Param` / `@Event` / `@Monitor` |
| 数据 | RDB `flowpage.db`（7 表 + 9 索引）、preferences、`filesDir/snapshots/*.txt` |
| 同步 | WebDAV（Basic Auth），ETag 增量 + LWW；书签/文件夹/墓碑三类实体；无分布式 KV、无账号体系 |
| 测试 | `@ohos/hypium`，`entry/src/ohosTest` 20 个套件 / 229 个用例，仅设备端 |

## 构建与验证（顺序有讲究）

- **`devecocli build` 对本仓库不可用**：其内置 hvigor 只支持 `modelVersion 6.1.0`，本工程是 `26.0.0`，会报
  `Unsupported modelVersion of Hvigor 26.0.0`（已实测）。改用 SDK 自带 hvigor 7.26.8：

```bash
hvigorw --version                 # 必须 >= 7.26.8
hvigorw assembleHap               # 产物 entry/build/default/outputs/default/entry-default-signed.hap
codelinter -c code-linter.json5   # 当前 0 error / 1 warn（PageHeader 自定义组件建议改 @Builder）/ 1 条 startIcon 性能建议
```

- 若 `hvigorw` 不在 PATH，本机位于
  `/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/hvigor/bin/hvigorw`。
- 首次克隆或依赖变化后先 `ohpm install`；然后每次改完 `.ets` 先跑会话内的 `check_ets_files`
  （快速 ArkTS 严格模式检查），再跑 `hvigorw assembleHap`；不要用 `devecocli build` 作为验证门禁。
- 纯函数测试入口是 `entry/src/test`（`hvigorw test`），与设备端 `entry/src/ohosTest` 分开；本机 SDK
  未安装 previewer 包时 `hvigorw test` 会停在 `previewer/common/bin ENOENT`，此时只能跑设备端套件。
- UI 自动化注意（2in1 真机实测）：中文输入法面板会拦截 `uitest` 注入的点击（坐标命中但事件不达应用，
  hilog 刷 `ImsaKit updateCursor` 错误）；驱动收笺面板等表单流程用免键盘路径——`aa start -U <url>` 经
  want 预填，收笺面板整体流程不唤起输入法。
- 设备端测试（真机/模拟器）：

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000
```

- `build-profile.json5` 含本机签名材料且被 gitignore；新克隆先从 `build-profile.template.json5` 复制生成，
  不要提交。`.hvigor/`、`entry/build/`、`oh_modules/` 均为生成物。
- `main_pages.json` 只有 2 个页面路由：`pages/Index`、`pages/SharePage`。标签/同步/设置是组件，经
  `Index` 内的 `NavPathStack` 或宽屏 pane 切换，不要往 `main_pages.json` 里加路由。桌面卡片是独立的
  `@Entry` 表单页面（`widget/pages/`），不属于页面路由。

## 架构与数据流

```
EntryAbility ─┬─ flowpage://bookmark/{id} / want.bookmarkId ─▶ AppState.openBookmark
              ├─ http(s) URL ─▶ AppState.openInbox
              └─ ShareAbility ─▶ pages/SharePage
Index (breakpoint 700/1000vp) ─▶ StreamHome / DetailContent / TagsPage / SyncPage / SettingsPage
                                      │
                                      ▼
                          FlowRepository（单例，UI 只依赖它）
                           ├─ BookmarkDao + FolderDao + Database（RDB）
                           ├─ MetadataService / SnapshotStore / ReaderPageLoader
                           ├─ SyncEngine + WebDavTransport（书签 + 文件夹 + 墓碑）
                           └─ CardPublisher / CardSnapshot
```

- **刷新靠 tick**：`AppState.notifyChanged()` 递增 `refreshTick`；Repository 的常规 UI 写方法完成后会自动
  `notify()`（`setLinkStatus` 与同步内部方法除外）。直接调 `BookmarkDao` 不会刷新 UI，也不会推送卡片。
  新写入口必须走 Repository，或在末尾补 `notify()`。
- **所展书签消失时详情腾空**：`DetailContent.syncSnapshot()` 查无此笺即 `clearReadingTimer()` + 置空 +
  触发 `onRemoved`（宽屏接线 `clearSelection()`，手机端弹栈 + `clearSelection()`），带 `bookmarkId` 快照
  守卫防误腾空新选中；任何消失路径（列表/批量/同步墓碑/过期清理）都经 refreshTick 收敛到该分支，勿在各
  删除入口重复清选中。能力规格见 `openspec/specs/detail-vacate/`。
- `AppState.openBookmark()` 写 `routeTick` 触发手机端 push `detail`；`onContinue` 只携带当前 `selectedId`。
- 断点矩阵：<700vp 手机壳 = `Navigation` 栈（只 push `detail`）包裹底部悬浮页签 `HdsTabs`；700–999vp 两栏 =
  左栏 `StreamHome` 单实例 + 右栏 `HdsTabs`（页签只切右栏，左栏滚动/筛选/选中不因切换重建）；≥1000vp 三栏 =
  停靠 `SideNav`（`components/NavigationRail.ets`），无页签。页签与停靠栏导航同源 `common/Constants.ets`
  的 `NAV_ITEMS`（label/pane/icon 一份定义，页签 `SymbolGlyph`+文字、停靠栏纯文字；首项 label 为「笺流」，
  区别于品牌标题「流笺」，真机反馈更名）。
- `AppState.pane` 仍是目的地唯一事实源：`Index.activeTabIndex` 是喂给 `Tabs` 的影子下标，由
  `@Monitor('appState.pane')` 推导；`Tabs.onChange` 只写 `goPane()`。页签内容走「首次激活再挂载」惰性门控
  （`visitedTabs`），挂载后常驻。`openPane()` 只写 pane 不碰导航栈；系统返回在导航栈空且 pane 非
  `DETAIL` 时回到流笺页签（<1000vp 生效）。tags/sync/settings 是页签目的地，不再是导航栈子页；
  `PageHeader` 只剩 trailing 状态槽（无返回/☰）。
- 品牌文字只由主页头部承载（34fp「流笺」），全断点同一结构；<1000vp 头部与页签页同构（`PageHeader` +
  34fp 标题，标题顶边跨页对齐——真机反馈修订），计数副题「N 条 · 今天收下 N 条」位于 `PageHeader`
  trailing 状态槽（与「N 个标签/已连接/v1.0.0」同位），≥1000vp 随 ☰ 行 trailing（自由窗时 ☰ 与计数迁至
  窗口标题条，见「自由窗窗口装饰」条）；收笺按钮与标题顶对齐
  （`VerticalAlign.Top`，底对齐会因按钮 44vp 高于标题把标题顶边压低约 3.5vp，实测）。侧边栏 `SideNav` 无品牌块、四项导航
  仍由 `components/NavList.ets` 渲染（`NAV_ITEMS` 同源、`TOP_INSET=26` 顶部留白、20vp 标签缩进、按压
  surface_alt 反馈；`showItems=false` 时仅渲染 26vp spacer——空 Column 会被算成 0 高，必须显式
  `.height(TOP_INSET)`）。☰ 仅存在于 ≥1000vp——自由窗在窗口标题条左缘（见「自由窗窗口装饰」条），
  非自由窗在主页头部，为 `SymbolGlyph` 图标按状态映射：展开显
  `sys.symbol.open_sidebar`、收起显 `sys.symbol.close_sidebar`（切换 `AppState.sideNavOpen`，
  默认展开，收起时拖拽书签自动展开）；<1000vp 资料库入口为悬浮页签迷你栏（见「悬浮页签」条），图标同一状态
  映射。抽屉面板常驻挂载，
  `translate`/`opacity` 隐式动画：面板 240ms 推入、内容延迟 100ms 跟进，收起不延迟；≥1000vp 停靠栏
  按宽度过渡推挤内容区。勿改回条件渲染 + `transition`（实测面板本体不动画）；关闭态须逐层 gate：
  `HitTestMode.None` 只关自身不关子节点，根/全屏遮罩各设 None、面板另加 `enabled(false)`，
  根再 `accessibilityLevel('no-hide-descendants')`，否则透明遮罩会吞掉迷你栏点击；
  无障碍标签按动作（展开/收起侧边栏、打开/收起资料库抽屉）。
- 自由窗窗口装饰（2in1/平板自由多窗，`isInFreeWindowMode`）：`EntryAbility` 在 `loadContent` 后调
  `setWindowDecorHeight(40)` → `setWindowDecorVisible(false)` → `setWindowTitleMoveEnabled(false)` →
  `setWindowTitle` → `setDecorButtonStyle`（Stage 约束：必须 loadContent 生效后调），并挂
  `freeWindowModeChange` / `windowStatusChange` / `windowTitleButtonRectChange` 三监听写 `AppState`
  （挂载后同步读一次初值；rect 真值约 90ms 后由事件送达，init 的 0/0 陈旧值已被事件兜住）。标题条
  `WindowTitleBar`（40vp paper）仅自由窗 FLOATING/MAXIMIZE 渲染——谓词 `showStrip` 与避让
  `avoidanceWidth` / `sunkButtonAvoidance` 是 `common/WindowChrome.ets` 纯函数（设备端套件覆盖）。`Index`
  根部为常驻 `Column`：条作条件子节点、根 `Stack` 高度在 `calc(100% - 40vp)` / `100%` 间切换，勿改回
  双分支条件包裹（浮动↔最大化切换会销毁重建 Stack 子树丢滚动/筛选状态，实测否决）。拖拽面 `onTouch` Move
  触发 `startMoving()`（每次触点一次、Up/Cancel 重置）；双击空白按 `windowStatus` 切 `maximize()` /
  `recover()`，`maximize` 必须传 `MaximizePresentation.EXIT_IMMERSIVE`——默认 presentation 在设备上
  映射 FULL_SCREEN(1)、条谓词假且 UI 不可恢复（真机修复）。≥1000vp 条左缘承载 ☰（状态映射同口径）、
  尾部计数副题（数据源 `AppState.streamLoading/streamTotal/streamTodayCount` 镜像，单写者
  `StreamHome.load()`）；StreamHome ☰ 行在自由窗整行让位、以 26vp 状态带占位保持品牌标题与右栏标题
  顶边对齐（对齐差值与 <1000vp 实测一致）。右缘三键避让 = `rect.right + rect.width + 12vp`
  （`getTitleButtonRect` 单位 vp，真机校准）；阅读层 TopBar 尾部同走 `sunkButtonAvoidance` 避让。深色
  三键目检待 2in1 真机（`DecorButtonStyle` 未 pin colorMode，随系统主题）。能力规格见
  `openspec/specs/window-chrome/`。
- 抽屉与停靠栏都是「资料库」：<1000vp 抽屉只含智能视图（`components/SmartViews.ets`，全部/未读/星标/
  归档/回收站 + 计数，写 `appState.homeFilter`）+ 文件夹树，无目的地导航；≥1000vp 停靠栏依次为四项导航、
  智能视图、文件夹树、标签分区（`components/TagSection.ets`，空标签集整块隐藏）与同步摘要
  （`components/SyncSection.ets`），均随 `refreshTick` 刷新。`appState.homeFilter` 是筛选唯一所有权
  （StreamHome 无本地 filter，`@Monitor('appState.homeFilter')` 负责退批量、关弹层、重载）。
  资料库查询必须等 `AppState.libraryReady`（仓库 init 完成后置位，否则 `Database.getStore()` 抛错被吞、
  界面停留 0 计数/加载态）；抽屉侧首查再推迟到抽屉首次打开（`deferUntilDrawerOpen`/`docked=false` +
  `folderDrawerOpen` 门控），停靠栏 eager——启动查询窗口让给首页首屏（真机实测树查询会压后列表首绘）。
- 悬浮页签：载体为 `@kit.UIDesignKit` 的 `HdsTabs`（`import { HdsTabs, HdsTabsFloatingStyle, hdsMaterial }
  from '@kit.UIDesignKit'`；<700vp 嵌在 `Navigation` 内、700–999vp 嵌在右栏 `Row` 内，嵌套原型已验证）。
  `systemMaterialEffect` 用 ADAPTIVE 档（PC/2in1 免 `getSystemMaterialTypes()` 查询），材质只作用于页签栏
  与迷你栏背板；`barBottomMargin` 显式 0——页签紧贴底部导航避让区上缘，系统默认间距在真机上偏高，勿改回。
  自定义 `tabBar` 必须直调 `this.TabBarItem(n)`——箭头包装会丢 UI 上下文导致 item 渲染为空（实测，
  HdsTabs 下同）；`HdsTabsAttribute.barHeight` 只有单参数版本。<1000vp 配置资料库迷你栏（design D12）：
  纯图标 26fp、无文字（真机反馈），图标镜像抽屉状态——开显 `open_sidebar`、关显 `close_sidebar`（与 ☰
  状态映射同口径，真机反馈校准，勿按动作反着映射），点击开合切换抽屉，热区 ≥44vp。迷你栏固定圆形：HdsTabs
  宽度 >600vp（折叠屏）初始为展开样式并向 328vp 上限膨胀，须 `miniBarStyle: COLLAPSE` +
  `miniBarWidth` 三档全钉 56（= 页签栏高）——样式参数仅 <600vp 生效，宽度钉住覆盖其余分档（真机反馈）。批量态隐藏：
  `barHeight(0)` + `barFloatingStyle` 传 `undefined` 取消悬浮样式（`HdsTabsController.applyHideAnimation`
  是瞬态滚动/点击 API、不适配持久批量态，已否决）；`barHeight` 最小高度限制会残留约 7.5vp 空条，
  无蒙层无内容，属可接受残留（兜底方案见 design.md D8）。页签可见时其下可滚动内容需预留
  `TAB_BOTTOM_RESERVE=88` 底部内边距（StreamHome/TagsPage/SyncPage/SettingsPage/DetailContent 的
  `bottomReserve` 参数，仅页签宿主传入）。能力规格见
  `openspec/specs/navigation-shell/`、`openspec/specs/library-sidebar/`、`openspec/specs/interaction-feedback/`。
- 主页头部不放统计条/批量/粘贴/筛选：「批量」在排序行行尾（`BatchButton`，全断点同位）；主页**没有**筛选
  chips 行（真机反馈后移除），智能视图是主列表筛选唯一入口；剪贴板粘贴入口在收笺
  面板（`InboxSheet`）URL 行内的 `PasteButton`（安全组件，点击即获读取授权，读出首个 URL 回填输入框）。
- **收笺面板动效（inbox-motion）**：`InboxSheet` 在 `Index` **常驻挂载**（勿改回 `if (showInbox)` 条件挂载），
  内部 `InboxPhase` 相位机（closed/entering/open/exiting/launching）由 `@Monitor('appState.showInbox')` 驱动；
  `AppState.showInbox` 仍是唯一意图源，退场口味（launch 发射感/dismiss 下滑）是组件内 `launchExit` 私有状态。
  呈现矩阵（`@Param isWide/isLarge` 由 Index 同源断点传入）：<700vp 贴底悬浮卡（四角 16 圆角 + 左右/底 12vp 留边，手机宽度须
  `calc('100% - 24vp')`——`width('100%')` 按父容器全宽解析、左右 margin 被吞不渲染，像素实测；方角全宽板起飞有"掀幕布"割裂感——板 vs 物，真机反馈）；≥700vp 居中卡片（Stack 对齐 Center、
  700–999vp 宽 min(84%,600vp)、≥1000vp 宽 min(70%,720vp) + 标题/标签两栏响应式、四角圆角、无 BOTTOM 安全区扩展）。
  面板本体转场由外层节点的**隐式 `.animation(this.motionParams())` 驱动**（按相位给参：进场 400ms
  `FastOutSlowIn` / 退场 300ms `EaseIn` / launch 先 100ms 下顿蓄力再 400ms 与进场同速上滑——六轮反馈放缓，原
  320/220ms；下顿深度断点分档：
  手机 32vp「缩回底边脱锚」（直接上飞会有底边割裂感，真机反馈）、宽屏居中卡 6vp）——这是全仓库
  唯一在产的 translate 驱动机制（抽屉/PaneEntrance 同款）；**勿在面板本体上依赖 `animateTo` 驱动位移**：三轮实测
  其事务捕获不到面板 translate（onFinish 探针会误测同闭包里其他属性——曾把 scale 弹簧的 1s settle 误当进场动画，
  该 scale 逐帧重绘整面板还是级联卡顿源，已删）。**隐式动画会捕获该节点一切 translate 变更——屏外归位跳变必须
  零时长**：`motionParams()` CLOSED 分支返回 `duration: 0`（否则发射终位 -hidden 与归位 +hidden 的跳变会被播成
  "向下滑过屏幕"）；三条转场入口均为纯状态写 + 带守卫 `setTimeout` 链，相位交接不依赖 `onFinish`（其时序在该节点
  不可靠）。字段级联/遮罩/toast/域名提示/批量块同样走隐式 `.animation`
  （单状态翻转 + 每节点 delay），动效常量收在 `InboxSheet.ets` 顶部。**面板位移必须由数值状态直绑**
  （`@Local panelOffsetY: number` + `.translate({ y: this.panelOffsetY })`，数值目标：手机 900vp / 宽屏 2000vp
  离屏）；**禁用百分比字符串位移与 `Visibility` 切换参与转场**（首轮/二轮瞬移根因），隐藏只能靠几何离屏
  （断点切换时 `@Monitor('isWide')` 在 closed 态重设隐藏位）。注意 `uitest dumpLayout` 看不见渲染侧
  translate——验证动画需人眼或带属性区分的探针。
  **URL 行级联只上浮不淡入、面板本体（含外层运动节点）全程无 opacity**——`PasteButton` 是安全组件，祖先链 opacity≠1 直接注册失效
  （`SecurityComponentCheckFail`，模拟器实测；scale 0.97→1 点缀实测无害）；同理勿给面板本体加 opacity 动画（translate/scale 不受影响）。
  退场即 `clearFocus()` 收键盘（常驻挂载后 TextInput 不再随卸载失焦）；关闭态 `Visibility.None` 兜底 + 逐层 gate 与抽屉同款
  （根/遮罩 `None` + 面板 enabled/hitTest）。toast（`Index`）已常驻化 + 180ms 浮现，`HitTestMode.None`；带操作
  toast 另渲染「撤回」chip，仅 chip 放开 hit-test（`None` 只关自身不关子节点），容器与其余区域仍 None。
  能力规格见 `openspec/specs/inbox-motion/`。
- 卡片在独立进程读取 preferences，`CardSnapshot.open()` 必须先
  `removePreferencesFromCacheSync`，否则读到旧快照。`FlowRepository.notify()` 已做“写快照 + 推送”串行合并。
- 所有 URL 先经 `normalizeUrl()`：补 `https://`、小写 host、去 fragment、去跟踪参数、query 排序；`url_key`
  唯一索引负责去重。新增入口不要自己比较原始字符串。
- 正文快照是 `filesDir/snapshots/<id>.txt` 的结构化文本（`FLOWPAGE-ARTICLE-2` 版本头，每块第三字段是
  `start,end,encodeURIComponent(url)` 链接区间），**不上传同步**；同步只传链接、元数据、标签和状态。
  `FLOWPAGE-ARTICLE-1` 仍可读但无链接；旧文章需“重新抓取”。根书签阅读位置存本机 `flowpage_reader`，不参与同步。
- 阅读/浏览器统一走 `Index` 根部的 `bindContentCover` + `ReadingShell`，不要往 `main_pages.json` 加路由；
  临时链接页不写 RDB/快照/`flowpage_reader`，只保留在 `ReadingEntry` 内存栈中。正文链接点击 → 原生抓取
  （`ReaderPageLoader`）→ 临时阅读页；非文档链接 → 内置 `Web`。浏览器「阅读」用
  `runJavaScriptExt('document.body.innerHTML')` 提取实时 DOM，同样复用 `ArticleExtractor`。
- **沉浸式系统栏**：组件安全区方案（`expandSafeArea` 绘制延伸，非 `setWindowLayoutFullScreen`），系统栏区域
  透出容器自身背景、内容留在安全区自动避让。已扩展 6 处屏幕边缘背景容器：`Index` 根 Stack、`FolderDrawer`
  抽屉列与遮罩、`InboxSheet` 遮罩（面板改贴底悬浮卡后不再自行扩展，遮罩独自承担弹层沉浸）、`SharePage` 根。新增屏幕边缘容器（弹层/抽屉/独立
  窗口页）背景色 ≠ 根 paper 时需自行附加 `expandSafeArea`；paper 同色界面由根 Stack 单点覆盖，勿逐页加。
  `bindContentCover` 保持 `enableSafeArea: true`（阅读层零改动承接）。能力规格见 `openspec/specs/immersive-ui/`。
- 删除语义：软删除 `deleted=1` 保留 30 天；彻底删除/过期清理会写 `tombstone`，同步先传墓碑再删远端文件。
  墓碑是“不复活”的唯一保障，任何清理路径都不能跳过 `addTombstone`。
- **浏览器书签流转（导入降阻 + 合并语义 + 批量收笺）**：书签 HTML 文件经系统分享面板或文件管理「打开方式」直达导入预览——`general.html` skill（`viewData`+`sendData` 双动作）注册在 `EntryAbility`：分享面板直接拉起主入口，`handleWant` 对 sendData want 用 `systemShare.getSharedData` 取文件记录、趁 want 授权新鲜读成字符串（官方收文件模式；勿改回「ShareAbility 中转暂存再拉起」——真机实测预览不出现，中转链路任一环断裂即失效）。`ShareAbility` skill 必须用精确类型 `general.hyperlink`+`general.plain-text`，勿声明父类型 `general.text`——UTD 里 `general.html` 是其子类型，会把 HTML 文件吸进收笺扩展造成分享面板双入口（真机反馈）；`EntryAbility` 文件 uri 路由统一 `pane=SETTINGS`，`SettingsPage` 以 `@Monitor('appState.pendingImportHtml'/'appState.libraryReady')` 消费（libraryReady 门控冷启动竞态）。`Index.aboutToAppear` 必须手动同步初始 pane——`@Monitor` 不重放挂载前变更。导入预览可选「按文件同步文件夹归属」（`ImportOptions.mergeFolders`）：仅 `source=IMPORT` 存量跟随文件文件夹（find-or-create 建链），先比较 folderId 再写（`setFolder` 走 dirty+rev 路径），重复导入零写零流量；语义标记应用抽为 `applyTopFolderMark` 供插入/合并两路共用。HTML 导出默认文件名带日期（`flowpage-bookmarks-YYYYMMDD.html`）。批量收笺：`extractAllUrls` 只认显式 http(s) 且在首个非 ASCII 字符处截断（中文行文无空格会把后续文字吞进路径）；收笺面板粘贴多链接出清单预览（域名+URL、点击移除——真机反馈：只报数量不直观）；`FlowRepository.saveUrls` 有显式 scheme 前置门——`normalizeUrl` 会把纯中文文本提升为合法 https 主机名，勿绕过；批量路径不做元数据抓取（N 链接 = N 网络请求）。`StreamHome` 根容器 `onDrop`（HYPERLINK/PLAIN_TEXT）收外部拖入链接（source=BROWSER），  `FolderDragSession` 活跃时必须忽略（内部书签拖拽会话优先）。能力规格见 `openspec/specs/bookmark-transfer/`、`openspec/specs/link-intake/`。
- **分享出**：三入口（书签行「…」面板「打开」后、批量栏仅选中书签>0、阅读层「⋯」菜单「复制链接」后）统一走
  `common/ShareOut.ets`（单条 HYPERLINK 记录 + DETAIL 预览；多条聚合为一条 PLAIN_TEXT 记录、内容单行空格分隔
  URL、DEFAULT 预览）。平台约束（真机实测）：系统分享不支持多条纯文本/链接记录分发——BATCH 批量通道仅对
  File 记录有效（错误码 1003702001），QQ 把文本记录按整段 schema 解析（行内标题、换行均触发「schema不合法」），
  备忘录只收首条、华为分享拒发多记录；故多条只能聚合单行文本。API 26 无面板 `close()`，`ShareOut.dismiss()` 落地
  为 off('dismiss')+释放引用（幂等吞错），宿主 `aboutToDisappear` 收口。App Linking 收端基础设施已休眠预置：
  `module.json5` 独立 skill（https + dunodoge.com + pathStartWith "s" + domainVerify）+ `EntryAbility` /s 路由进阅读层
  + `ShareUtil.shareLinkOf/shareLinkTargetOf`；发端包装暂缓——待服务器 `/.well-known/applinking.json`（appIdentifier
  6917619579162930870）与 `/s` 302 端点、AGC 应用链接发布上线后，ShareOut 两处 `link.url` 改回 `shareLinkOf(...)` 即启用。
  能力规格见 `openspec/specs/share-out/`。
- **书签行快捷操作（单列菜单 + 左滑 + 可撤回删除 + 全屏文件夹选择页）**：行尾「…」弹层为单列菜单——`MenuRow`
  私有 struct（`StreamHome.ets`）：44vp 行高、hover/press `surface_alt`、危险项红字、focusable + Enter/Space；非回收站
  操作集 = 分享/多选/移动到文件夹/归档/标记已读/删除（「打开」「加星标」已移除，由行主体点击与行尾星标承担），回收站 =
  恢复/彻底删除/多选。左滑走内建 `ListItem.swipeAction`，end 用 `SwipeActionItem` 对象形态：分享/删除两块 64vp
  `surface_alt` 图标块（分享 `sys.symbol.share` 复用 `ShareOut.shareBookmarks`，删除 danger 红 `sys.symbol.trash`）+
  `onAction` 长距删除区（默认 56vp，超阈值抬手直接删除）；`edgeEffect` 默认 Spring 即非线性展开/回弹，勿自研手势。
  禁用谓词 = 回收站视图 || 批量选择态 || 已删行，禁用时 `SwipeActionOptions` 不设 end（无划出内容即无手势）。
  删除按钮与 `onAction` 统一软删（`deleteMany`）+ 带「撤回」toast（回调 `restoreMany`，失败提示「恢复失败，请到回收站
  找回」）；分享后 `ListScroller.closeAllSwipeActions()` 收起露出区（`streamScroller` 与 List 一对一绑定）；swipe
  展开即关「…」弹层（`onStateChange` 到 EXPANDED 置 `showActions=false`）；菜单「删除」仍走 AlertDialog 确认。
  toast 基建：`AppState.toastWithAction(text, ToastAction.of(label, run))`——显式类禁裸对象字面量，带操作停留
  5000ms、纯 `toast` 2400ms 且清空操作，`runToastAction` 执行回调并清空（ohosTest `Toast.test.ets` 覆盖）。
  全屏文件夹选择页 `FolderPickerPage` 挂 `Index` 根 Column 的第二个 `bindContentCover`——阅读层 cover 在根 Stack，
  一节点一 cover 勿同节点双绑；入口 = 行菜单「移动到文件夹」写 `AppState.folderPickOpen` / `folderPickBookmark`
  （整 Bookmark 对象非裸 id：选择页同步取标题与当前归属，免挂载期异步查询）；`FolderPicker` 的 `confirmMode` 仅供
  该页（`pick`/`pickRoot`/`submitCreate` 只高亮暂存 + 下钻并发 `onStage`，MUST NOT `onPick`），详情编辑器/批量栏/
  文件夹面板三个内联使用点不传参行为零变化；未点底部「移到这里」确认条离开零归属写入——只暂存不落库
  （confirmMode 下「新建文件夹」是真写入，离开仍保留；`onWillDismiss` 放行 + `onDisappear` 复位）。
  能力规格见 `openspec/specs/stream-row-actions/`、`openspec/specs/bookmark-folders/`。
- 上传竞态：PUT 前记录 `rev + updatedAt`，成功后仅当仍匹配才回填 ETag 并清 `dirty`；不匹配说明同步期间
  又被编辑，必须保持 dirty。
- 传输层瞬时失败重试（`WebDavTransport.request()` 内，覆盖所有动词）：429/502/503/504 与 `NET_*` 网络错误
  按 500/1000/2000ms 退避、最多 3 次尝试；`Retry-After` 优先但 >5s 快速失败；401/403/404/409/412 等不重试
  （LWW/If-Match 快速失败语义不变）。决策纯逻辑在 `WebDavRetryPlanner`，重试成功不计入报告失败数。
- 限流自适应节流与熔断早停（`WebDavPacer`，同文件）：重试耗尽于 429/503 才激活全局节流（基础 1000ms，
  `Retry-After` 融合上限 30s，成功 ×0.8 衰减、<100ms 退出）；节流下连续 3 次耗尽 → 传输层置熔断、后续请求
  立即抛 `THROTTLED_ABORT`，引擎跳过剩余阶段并报「服务器限流，本轮提前结束，剩余条目下次同步继续」，
  未处理条目不计失败（`SyncReport.throttled`）。坚果云等 ~1 req/s 服务商的批量上传/下载靠节流磨过、
  硬限流窗口靠早停兜底；正常服务器零额外等待。
- 同轮集合同步顺序：文件夹先于书签（`SyncEngine.run()`），避免服务商限流时大批书签上传耗尽配额导致
  文件夹阶段持续饥饿（云端 folders 目录空）。能力规格见 `openspec/specs/webdav-sync/`。
- 数据库没有版本号/事务迁移框架：建表用 `CREATE TABLE IF NOT EXISTS`，加列同时改 `Database.SQL_BOOKMARK`
  并在 `Database.applySchema()` 的 `addColumn()` 列表补一条吞异常的 `ALTER TABLE`（现有 `dirty` /
  `link_status` / `link_checked_at` / `domain` 即此模式）；`SyncStoreTest` 用旧表结构验证迁移幂等。

## 性能约束（阅读页）

- **禁止在 UI 线程循环调用 `ArticleExtractor.extract()` 或 `ReaderSearchCore.searchBlocks()`**。阅读页链路
  （`ReaderPageLoader.load()`、`ReadingShell.extractFromWeb()`、`FlowRepository.applyMetadata()`）必须走
  `ArticleExtractService.extractAsync()`（taskpool，4 s 超时 + 同步回退）；阅读页搜索必须走
  `ReaderSearchService.search()`（taskpool，2 s 超时 + 同步回退，索引构建 ≤10 ms 留 UI 线程一次性）。
  `ArticleDocument` 不是 Sendable，跨线程只传 HTML 与 `ArticleCodec` 字符串/`number[]`。
- 热点正则必须模块级复用（`ArticleExtractor`、`MetadataService` 均如此），不要在函数内 `new RegExp`
  或堆重复 `replace` 链；改动抽取器后要复测耗时。
- transient 页性能预算（Pura 70 / 648 块 / 101,620 字符）：首屏布局 ≤ 600 ms，单次「点击链接→新页可读」
  ≤ 1.7 s。模拟器口径（2026-10-25 第三轮）：layout 中位 259 ms、click→layoutDone 672 ms、
  leaf500(1,999 块) layout 272 ms / 总 1,048 ms。`ReaderView` 首屏 `INITIAL_BLOCKS=200`、每次
  `BLOCK_BATCH=200`，**不要**一次挂载整篇（实测 648 块一次挂载约 3 s、VmRSS 553 MB）；改窗口/恢复/搜索
  逻辑后要复测 `uitest dumpLayout` 节点数、`VmRSS` 与 1/5/10/20 次下钻。
- **下钻整帧间隔由新页 200 块构建主导**（第三轮对照实验：初次打开 ≈ 下钻 layout），旧页销毁边际成本
  ≈0–20 ms——不要再把该帧归因给「拆解」，也不要为拆解引入双槽延迟销毁（收益/风险倒挂，已评估否决）。
- 改 `ReaderView` 必须保留：目录、进度、位置恢复（含窗口外块）、搜索命中、链接点击、临时页「收藏这一页」。
  **已知边角（未修）**：位置恢复到窗口外块在超大页上时序敏感（10×200 ms 重试内测量未完成即耗尽则回落顶部
  且进度条残留目标值，第三轮 4 试 1 失）；改恢复逻辑时优先验证 leaf500 尾部恢复。
- **阅读栈内存形态机**：`ReadingShell.back()` 出栈即裁 `entries` 尾部（被弹层无前进路径）；push 后 600 ms
  空闲把非当前层 article 压为 `ArticleCodec.encode()` 串（`entry.compact`），pop 回时 decode（12–15 ms/648 块，
  ≪100 ms 门限）。改栈逻辑必须保持这两条不变量，并复测 20 层 VmRSS。
- 判断主线程阻塞用 20 ms `setInterval` 心跳并记录最大间隔；只看 hilog 阶段时间戳会把「上一页拆解/GC」
  误判成网络耗时。模拟器测量注意：连续 `dumpLayout`+`hdc file recv` 会触发病毒扫描风暴污染心跳
  （出现过 6.7–8.1 s 假阻塞），心跳采样必须在无并发 hdc 操作的静默窗口；`uitest keyEvent`（ESC）在长会话
  后可能被系统焦点吞掉，UI 驱动 pop 用界面「返回」按钮。
- 本节性能数字是当前权威口径（易变数字唯一维护点）；复测方法与各轮原始数据见
  `docs/records/05-browser-link-reading.md` 与 `openspec/changes/archive/reader-perf-round3/`。

## 代码约定

- ArkTS 严格子集：禁止 `any`、`as` 断言、结构化类型、动态属性访问；对象字面量必须有显式类型上下文。
  存量 `as` 只剩 5 处平台类型边界（`JSON.parse` ×2、WebDAV 动词/响应头、`BusinessError` 统一收口在
  `common/PlatformError.ets`），新增业务代码不要再用 `as`。
- 主 UI 统一 V2 装饰器；**只有** `entry/src/main/ets/widget/pages/` 的桌面卡片使用 V1
  `@Component` + `@LocalStorageProp`（FormKit 约束），不要混用。
- 文件夹管理属主页：`FolderPanel` 挂在最左页面栏——≥1000vp 停靠在 `SideNav` 内（导航项下方，栏宽 280vp，
  ☰ 可收起/展开，默认展开）；<1000vp 由悬浮页签迷你栏打开左侧抽屉（遮罩，点外部/返回关闭，入口唯一）。
  抽屉主导航同源 `NavList`，主页头部不放 标签/同步/设置，<1000vp 无 ☰ 只剩品牌块，≥1000vp 保留 ☰。
  树的展开集合、滚动位置与抽屉开合在
  `AppState`；跨列多选与拖拽会话也走 `AppState` / `FolderDragSession`，投放由侧栏直接提交。点树行把流过滤到
  该文件夹的**直属书签**（`BookmarkQuery.folderId` 等值，子文件夹内容经其行下钻；树行计数仍含全部子孙）。
  长按拖拽只改归属（`bookmark.folder_id` / `folder.parent_id`），**不写** `position` / `createdAt`；
  批量与拖拽共用 `FlowRepository.batchMove/batchMoveOut/batchDelete`，单次 `notify()`。行操作入口是行尾
  「…」`sys.symbol.more` 锚定面板（桌面右键同入口；单列菜单与左滑操作集见「书签行快捷操作」条），不要再加长按菜单
  或 context menu；无拖拽路径经 `FolderPicker`。
- 动态文案不要只放在带参 `@Builder` 里：实测 `ReadingShell` 的「网页/阅读」标签在模式切换后会残留旧值，
  改为直接内联 `Text` 或提升到 `@Local` 状态；其余带参 builder 的静态文案不受影响。
- `ForEach` 键值必须覆盖行内会显示的可变字段（如 `${id}|${name}|${count}`）：普通 DTO 不是 `@ObservedV2`，
  只用稳定 id 作键时数据源替换会复用旧行、名称/计数停在旧值，直到页面重建才更新。现有示例见
  `FolderPanel` 树行、`StreamHome` 书签行（含 `rev|updatedAt`）与 `TagsPage` 标签行；往行内加新可变字段时同步加入键值。
  嵌套 `ForEach` 时外层键也必须随内层可见内容变化，否则外层行复用、内层不会重建。
- 图标一律 `SymbolGlyph` + `sys.symbol.*`（☰ 与资料库迷你栏图标按状态映射 `open_sidebar`/`close_sidebar`
  ——展开/打开显 open、收起显 close，真机反馈校准勿反；加=`plus`、更多=`more`、
  关=`xmark`；资源名以 SDK `ets-loader/sysResource.js` symbol 组为准，勿凭记忆猜名）。`SymbolGlyph.fontColor`
  只收 `Array<ResourceColor>`（`[$r(...)]`）。hover/按压反馈用 `onHover((isHover: boolean)=>…)` 与
  `onTouch` Down/Up/Cancel 驱动 `@Local`，条件切换 `surface_alt` 背景（`hdsEffect.pressShadow`
  在非 HDS 组件实测不渲染）；Button 先 `stateEffect(false)`；**不要用 `stateStyles`**
  （plain 组件按压背景残留、hover 误触发），API 26 也无 `hoverable` 属性。小按钮热区用 `responseRegion`
  扩到 44vp，别放大可视尺寸。
- 内置 Web 复用 `INTERNET` 权限，不要新增权限；`target=_blank`/`window.open` 用
  `javaScriptOnDocumentStart` 中和，ArkTS 不能给 `ControllerHandler.setWebController` 传 `null`。
  离开浏览模式后 Web 会卸载，调用 `WebviewController` 前必须检查 `webMounted`。
- 颜色一律 `$r('app.color.*')`（`resources/base|dark/element/color.json` 成对维护）。当前没有 i18n 层，
  页面文案是内联中文，只有应用名/Ability 标签在 `string.json`。
- 界面文案禁未实现功能预告占位与定位/抒情式 slogan（侧边栏 footer、关于 tagline、页面副题已删），
  数据行为/隐私告知与空状态引导保留；设置页版本号运行时读包配置 `versionName`，不要硬编码。
  规格见 `openspec/specs/ui-copy/`。
- 日志 `hilog`，domain `0x0000`，TAG `'flowpage'`。
- 注释只写代码表达不出的约束，英文，与该文件现有风格一致。
- 提交遵循现有 Conventional Commits（`fix(sync): ...`、`docs: ...`）；**未经明确要求不要 commit/push**。

## 待决事项

1. 是否提供第二台鸿蒙设备，用于碰一碰、分布式与更多跨端验收。
2. 是否配置 App Linking 域名并完成 `/.well-known/applinking.json` 校验。
3. 内置浏览器是否扩展为多标签/无痕（当前单标签、可编辑地址、阅读模式切换）。
4. 服务卡片与键盘完整路径的人工验收由谁在何时完成。

## 文档地图

- 文档索引：[docs/README.md](docs/README.md)；分层架构详解：[docs/wiki/](docs/wiki/README.md)。
- 方向性决策（为什么这样做）：[docs/adr/](docs/adr/README.md)，append-only，推翻走 Superseded 链。
- 进行中与已完成变更：`openspec/changes/`；能力规格（系统持久行为契约）见 `openspec/specs/`；规划新变更先看 `openspec/config.yaml` 内的项目约束。
- `docs/quality/`、`docs/records/` 是只追加的历史快照；文档里的勾选只是声明，落地与否必须回代码与测试
  验证。现有 `docs/records/01-implementation-log.md` 含历史批次记录，可能落后于代码（例如“28 个用例”、
  已删除的 `BrowserPage`/Permissions），以源码和本文件为准。
