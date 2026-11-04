# Proposal

## Why

应用此前为默认非沉浸布局：页面绘制止步于安全区边界，状态栏与底部导航条区域显示系统默认底色，与页面 paper 背景形成色带断层——浅色模式下底部导航条区域呈「白条」、顶部状态栏区域与页面背景不连续，深色模式同样有边界。用户要求「修改应用UI，背景沉浸适配底部白条和顶部状态栏」。

需求澄清确认三个关键口径：沉浸策略取**全屏沉浸**（背景延伸到系统栏下方、内容避让）；适配范围取**全应用统一**（不逐页渐进，覆盖手机导航栈、宽屏两栏/三栏、标签/同步/设置、弹层与分享页）；阅读层取**统一沉浸**（阅读/浏览器全屏层一并纳入，不单独豁免）。

## What Changes

- 采用**组件安全区方案**（决策依据见 design.md D1）：不调用任何 window API，布局系统保持安全区内布局，由携带背景色的容器通过 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])` 把背景绘制延伸到状态栏与导航条区域，系统栏区域透出应用背景色（浅色 #F7F6F2 / 深色 #0E0E0D），可交互内容自动保留在安全区内避让。
- 6 处容器扩展（3 个文件，+6 行）：
  - `entry/src/main/ets/pages/Index.ets`：根 Stack（TOP+BOTTOM，一次覆盖手机导航栈全部 NavDestination、宽屏两栏/三栏与启动占位）；FolderDrawer 抽屉列（TOP+BOTTOM，paper 背景与右侧边框线贯通至屏幕上下缘）；抽屉遮罩（TOP+BOTTOM，抽屉打开时系统栏区域同步压暗）。
  - `entry/src/main/ets/components/InboxSheet.ets`：全屏遮罩（TOP+BOTTOM）；底部面板（仅 BOTTOM，surface 延伸至导航条下方，消除与 paper 的色差接缝）。
  - `entry/src/main/ets/pages/SharePage.ets`：根 Column（TOP+BOTTOM，ShareAbility 独立窗口）。
- 阅读全屏层**零代码改动**：`bindContentCover` 保持 `enableSafeArea: true`，覆盖层内容继续避让系统栏，系统栏区域透出底层 Index 根 Stack 扩展后的 paper，与 ReadingShell 自身 paper 同色无缝。
- 状态栏内容色（时间/电量图标）依赖系统随深浅色自动联动，不设 `setWindowSystemBarProperties`（对比度实测不足才触发兜底，见 design.md D2，未触发）。
- 动态窗口形态（旋转/折叠/分屏/自由窗/三键栏与手势条切换）由框架安全区机制自动跟踪，零 insets 计算、零监听。
- 不改：业务逻辑、数据层（RDB/同步/卡片快照）、路由（main_pages.json 仅 2 路由不变）、颜色资源、权限、widget 卡片进程。

## Capabilities

### New Capabilities

- `immersive-ui`: 应用背景延伸至系统栏下方且交互内容避让系统栏——组件安全区方案的容器扩展规则（按背景色归属确定扩展点）、弹层/抽屉沉浸一致性、阅读全屏层经 bindContentCover enableSafeArea 承接、动态窗口形态自动跟踪。

### Modified Capabilities

（无——现有规格 `bookmark-folders`、`bookmark-transfer`、`docs-governance` 与本题无关。）

## Impact

- **UI 层**（属性级修改，3 文件 +6 行）：`entry/src/main/ets/pages/Index.ets`、`entry/src/main/ets/components/InboxSheet.ets`、`entry/src/main/ets/pages/SharePage.ets`——每处仅追加一行 `expandSafeArea` 通用属性。
- **不改**：`entry/src/main/ets/entryability/EntryAbility.ets`（零 window 调用）、`entry/src/main/ets/components/ReadingShell.ets`（零改动承接）、`module.json5`、颜色资源、`main_pages.json`。
- **风险面**：纯绘制期扩展、零布局开销，阅读链路性能预算（transient 首屏 ≤600ms、下钻 ≤1.7s）无威胁；深浅色资源成对未动。
- **验证**：`check_ets_files` 对 3 文件零特性诊断（仅存量弃用告警）→ `hvigorw assembleHap` 构建成功（产物 entry-default-signed.hap）→ `codelinter -c code-linter.json5` 0 error → HUAWEI MateBook Pro 部署启动存活 → 真机目视验证通过（用户完成，深浅色/弹层/边框线贯通均确认）。
