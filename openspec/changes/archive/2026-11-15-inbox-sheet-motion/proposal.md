# Proposal

## Why

收笺面板是全应用唯一无进场/出场动画的界面：`showInbox` 翻转时面板与遮罩瞬间出现/消失（`Index.ets` 条件挂载），与其余动效语言（抽屉 240ms 滑入、页签 D11 上浮进场）形成断档。收笺是流笺唯一的"写入仪式"，值得一套完整的滑动进场 + 级联编排，同时补齐出场与内部状态变化（域名提示、批量清单、点条移除）的动效。

## What Changes

- 收笺面板从条件挂载改为**常驻挂载 + 状态驱动动画**（抽屉同款机制，规避"条件渲染 + transition 不动画"的实测教训），出场动画因此可得
- 断点呈现矩阵（走查反馈修订）：<700vp 手机保持底部停靠全宽；≥700vp（折叠屏展开/平板/PC）改为**屏幕居中卡片**，700–999vp 宽 min(84%, 600vp)，≥1000vp 宽 min(70%, 720vp) 且表单响应式两栏（标题/标签并排一行）
- 面板进场为可感知的滑动动画（走查反馈「不要直接出现」）：全断点自屏下滑入（FastOutSlowIn 家族曲线、节点隐式 `.animation` 驱动——抽屉同款在产机制），面板本体无缩放/淡入（重绘成本与安全组件祖先链约束）；遮罩同步淡入
- 数值位移状态驱动（二轮走查修订）：面板位移由数值状态 `panelOffsetY` 直绑、`animateTo` 插值数值目标（对齐抽屉已验证模式），全断点禁用百分比字符串与 `Visibility` 切换（关闭态 `Visibility.None` 会让进场帧"重现+位移"同帧快照——二轮"仍瞬移"主因；隐藏靠几何离屏）；+5vp 下顿由嵌套内层节点承担
- 「收下」成功时刻采用"发射感"编排且上行位移全程可感知：按钮压缩回弹（~120ms）→ 面板轻微下顿（~70ms）后以 ≥300ms 强加速曲线数值全程上滑出屏；去重（已收过）场景面板不退场，按钮轻抖 + toast
- 表单字段（URL 行 / 标题 / 标签 / 备注 / 收下按钮）以 35ms 步进级联进场：fade + 12vp 上浮（复用 D11 动效词汇），级联期间可交互
- 出场：遮罩快速淡出（dismiss 160ms / launch 200ms），面板加速下滑出屏（数值位移），内容不级联
- 面板内条件内容纳入动效：域名提示对称展开/收起（高度 + fade），批量块容器展开 + 条目级联（至多 6 条逐条，其后整组浮现），点条移除时该行收缩消失、其余上滑补位
- 动效参数以局部常量收在 `InboxSheet.ets` 顶部（与 `Index.ets` 的 `DRAWER_*` 系列同风格），不建全局 Motion token

## Capabilities

### New Capabilities
- `inbox-motion`: 收笺面板的转场编排契约——进场/出场/成功退场三条转场路径的时序与曲线，面板内条件内容（域名提示、批量清单）的出现/收起/条目移除动效，以及级联期间的可交互性约束

### Modified Capabilities

（无——`interaction-feedback` 管输入反馈（悬停/按压/热区），与转场编排不重叠；本变更不改其任何需求）

## Impact

- `entry/src/main/ets/components/InboxSheet.ets`：主要改动面——常驻挂载后的状态机（open/closing/success-exit）、级联编排、内部条件内容动效
- `entry/src/main/ets/pages/Index.ets`：`if (this.appState.showInbox) { InboxSheet() }` 改常驻挂载（关闭态逐层 gate：`HitTestMode.None` + `enabled(false)` + `accessibilityLevel('no-hide-descendants')`，抽屉同款），并向 `InboxSheet` 传 `@Param isWide/isLarge` 断点参数（同源断点，勿组件内重建媒体查询）
- `entry/src/main/ets/common/AppState.ets`：`showInbox` 语义可能需要拆分（open / animating-out），`aboutToAppear` 重置表单逻辑迁移到 `@Monitor` 重放
- 风险点：键盘与进场级联的协动（不自动聚焦，维持现状）；常驻挂载后重开面板的表单状态重置；批量块高度动画与 `maxHeight: 216` 约束的交互
- 不涉及：RDB/同步/卡片；`main_pages.json` 路由；下滑手势关闭面板（单开变更）
