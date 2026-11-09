# Verification Record

## 2026-11-09 · 冷启动修复（用户真机反馈：智能视图计数为 0 + 页签页启动延迟）

- **根因**：`FolderDrawer` 常驻挂载，`SmartViews`/`FolderPanel` 的 `aboutToAppear` 在 `Index.initRepository` 完成 `Database.init` 之前即查询，`Database.getStore()` 抛「Database is not initialized」被吞错 → 计数留 0 / 树卡「正在整理…」，直到下一次 `refreshTick`（如点开书签触发已读写）才恢复。停靠栏 `TagSection`/`SyncSection` 同模式隐患。
- **修复**：`AppState.libraryReady`（`@Trace`）门控——四个资料库组件 `aboutToAppear` 仅在 ready 时加载并 `@Monitor('appState.libraryReady')` 首载；`initRepository` 在 `ready=true` 前置位。启动期不再产生注定失败的查询。
- **模拟器复验**（127.0.0.1:37565）：冷启动 ≈3s 即开抽屉，智能视图 全部=667、文件夹树 全部=667 直接正确（修复前同时机为 0/加载态）；冷启动到 shell+首行内容 <300ms（轮询口径，dump 耗时主导）。
- **待真机复验**：手机无线调试端口轮换失联（192.168.8.240:36793 不再注册）；重连后复测冷启动计数与启动观感（含材质首帧）。

## 2026-11-09 · 启动延迟收尾（用户真机复测：计数问题已解决，仅剩页签页冷启动延迟）

- **判断**：`libraryReady` 修复让抽屉侧 summary/树查询在启动瞬间真实执行（修复前静默失败），与首页首屏
  `queryPage` 在同一 RDB 队列排队；527 条真机数据下树查询较重 → 列表首绘被压后。
- **修复**：抽屉侧 `SmartViews`（`deferUntilDrawerOpen: true`）与 `FolderPanel`（`docked=false`）首查推迟到
  抽屉首次打开（`@Monitor('appState.folderDrawerOpen')` 置位 `started`/`loaded`），停靠栏保持 eager；
  组件仍常驻挂载，展开/滚动状态不受影响。
- **模拟器复验**：冷启动→首开抽屉，智能视图 667 + 树 667 即时正确；抽屉选「未读」联动回页签；二开抽屉
  无重载闪烁。`hvigorw assembleHap` ✓。
- **待真机复验**：装机后确认冷启动页签内容首绘不再有明显延迟；HAP 位于
  `entry/build/default/outputs/default/entry-default-signed.hap`。



## 2026-11-08 · 页签贴底二次校准（用户澄清：调的是距底间距，非页签高度）

- 48vp 高度试验撤销，`TAB_BAR_HEIGHT` 回到 56vp 系统默认；`barBottomMargin` 8→0。
- 真机（手势导航）复测：TabBar 高 189px=56.0vp，底缘距屏底 94px≈27.9vp = 手势条避让区本身，应用侧附加间距 0——物理极限贴底。
- 截图：`~/.tmp/deveco/phone_tabs_margin0.jpeg`（此前 8vp 版 `phone_tabs.jpeg`、48vp 试验版 `phone_tabs_48.jpeg`）。


## 2026-11-08 · 手机真机（192.168.8.240，深色为主，527 条真实数据）第二轮走查（7.1/7.2 + 5.2/6.2 部分）

- **7.1 筛选行移除**：主页无 全部/未读/星标/归档/回收站 chips 行；抽屉智能视图选「未读」→ 抽屉关闭、列表筛出未读子集（6 行）；批量栏/空态回收站判断正常。
- **7.2 页签贴底**：显式 `barBottomMargin: 8`。真机（手势导航）TabBar [74,2450][1182,2639] / 屏 1256×2760（密度 3.375）→ 条底距屏底 121px≈36vp = 手势条避让(~28vp) + 8vp 设计间距，无双倍留白。截图：`phone_tabs.jpeg`（深色）、`phone_light.jpeg`（浅色切换成功，TabBar 结构一致）。
- **批量态**（真机复验）：页签塌缩为 26px≈7.7vp 空条（无内容无蒙层），全选/完成/移动到…/删除 完整可见。
- **冷启动**（debug 签名 HAP，hilog 设备时钟）：ScheduleLaunchAbility→`NotifyFrameLayoutFinishFromApp` 首帧 **272ms**；轮询口径 1.9–2.0s 为采样开销（250ms 粒度 + dump/recv），不作为口径。无启动明显回归信号（惰性挂载门控生效，tags/sync/settings 不在启动期构建）。
- **详情打开**（手机壳回归代理）：click→detail `onShown` in-app ≈15ms（nav 节点创建→onShown 14ms）。阅读页代码路径本变更零触及（AGENTS.md 沉浸承接不变量），未跑深 perf 环路。
- **codelinter**：0 error / 1 warn（PageHeader 存量）/ 1 suggestion（startIcon 存量），与基线一致，无新增。

### 待人工/三键导航项（阻塞 5.2 完结与 6.2 收尾）

- 三键导航下的底部留白复测：需在系统设置切换导航方式后重测（自动化不可达）。
- 悬浮材质胶囊/蒙层观感与 8vp 间距的目测确认（截图已存 `~/.tmp/deveco/phone_tabs.jpeg`、`phone_light.jpeg`）。


## 2026-11-07 · 手机真机反馈（用户实测）

- 悬浮页签位置偏高（悬空感）→ 修订：显式收紧 `barBottomMargin` 贴底（design D1 增补，任务 7.2）。
- 智能视图已覆盖筛选诉求 → 修订：移除主页筛选 chips 行，筛选入口收敛到资料库智能视图（design D7 增补，任务 7.1）。

## 2026-11-07 · 2in1（HUAWEI MateBook Pro 16, 127.0.0.1:37565, 深色模式）布局驱动走查

通过 `hdc install` + `uitest dumpLayout`（文本断言，非截图目测）在真机 2in1 上验证：

- **<700vp（窗口拖至 ≈545vp）**
  - `Navigation`（栈）内四项 `Tabs`，`TabBar` 悬浮于底部居中（bounds ≈ 全宽 62%，两侧留边），四项 label 齐全、流笺项 `selected=true`。
  - 切「标签」页签 → TagsPage 顶层化渲染（34fp 标题 + 空态），页头无返回/☰。
  - 系统返回（Back key）→ 回到流笺页签，应用不退出。
  - 打开书签 → `NavDestination` 全屏覆盖、TabBar 消失；返回 → 恢复原页签与页签栏。
  - 批量态：进入后 `barHeight(0)` + `barFloatingStyle(undefined)` → 四项与蒙层全部消失（`TabBar` 仅剩 ≈7.5vp 空容器，无子节点、无背景），`BatchActionBar`（全选/完成/移动到…/移出一级/删除）完整可见；退出批量后页签恢复悬浮位。
  - ☰ 抽屉：仅 智能视图（全部 667/未读 650/星标/归档/回收站 + 计数）+ 文件夹树，无四项目的地导航；顶部留白 ≈26vp（`NavList` spacer 生效）。点「未读」→ 抽屉关闭、chip 选中（深色 ink 背景）、列表仅未读项。
- **700–999vp（≈745vp）**
  - 左栏 `StreamHome` 单实例 + 右栏 `Tabs`；`TabBar` 在右栏底部居中悬浮；流笺选中态指向右栏 DetailContent。
  - 跨断点往返（≥1000 → <700 → 700–999）pane/筛选状态保持（tags 页签、未读筛选均延续）。
- **≥1000vp（≈1045vp）**
  - 停靠栏依次：四项导航（26vp 顶部留白保留）、智能视图（计数、选中态与 `homeFilter` 一致）、文件夹树、同步摘要（「上次同步 10 月 29 日 + 去同步」）；无页签。
  - 标签分区：为一条书签新增「验证标签」→ 分区与计数即时出现（refreshTick 联动）；点行 → 列表筛选到该标签、指示行出现、列表列保持可见。测试标签已删除还原数据。
- **2in1 窗口缩放**：<700 ↔ 700–999 ↔ ≥1000 来回切换，页签位置、无材质效果下的默认背板样式、返回语义均正常。

### 已知残留（按 design.md D8 主方案验收）

- `barHeight(0)` 受最小高度限制，批量态残留 ≈7.5vp 空条（无蒙层、无内容、不可交互），未触发 D8 兜底（批量栏浮在页签上方）；真机如视觉不可接受再降级。
- `check_ets_files` 对 `SmartViews.ets`/`PageHeader.ets` 输出过一次缓存旧诊断（ResourceStr→Resource），`hvigorw assembleHap` 实际编译通过，以构建为准。

### codelinter（任务 6.3）

`codelinter -c code-linter.json5`：**0 error** / 1 warn（PageHeader @performance/avoid-overusing-custom-component-check，自定义组件改 @Builder 建议，沿用既有组件形态）/ 1 suggestion（start-window-icon，存量）。

## 待真机/手机模拟器补验（阻塞 5.2 / 6.2）

- 手势导航与三键导航下的底部留白校准（2in1 无手机导航条，无法切换）。
- 浅色模式走查、悬浮材质（ImmersiveMaterial）在支持设备上的胶囊/蒙层观感、44vp 热区手感。
- 冷启动耗时与阅读页性能回归测量（对照 AGENTS.md 性能口径）。
