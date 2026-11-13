# Design

## Context

应用收向链路（`ShareAbility` → 分享页 → 收笺）已就绪。出向曾有一处遗留内联实现（`DetailContent.shareBookmark`，深链回退 + 域名摘要 + DEFAULT 预览），本变更收编为 `ShareOut` 统一出口后移除。三个落点组件均已确认：`StreamHome.QuickActionPanel`（行内锚定面板，非回收站分支含「打开/多选/移动…」等 chip）、`StreamHome.BatchActionBar`（批量动作 chip 组，书签类动作由 `selectedBookmarkIds.length > 0` 门控）、`ReadingShell.MoreMenu`（阅读层「⋯」菜单，已有「复制链接/收藏这一页/用系统浏览器打开」等项）。上下文源 `AppState.abilityContext` 已由 `EntryAbility.onCreate` 发布。见 proposal.md 的动机，specs/share-out/spec.md 的行为契约。

## Goals / Non-Goals

**Goals:**

- 一处出口、三处入口：分享构造与面板生命周期集中在一个无 UI 模块，入口只做调用。
- 交出标准 `HYPERLINK` 记录（URL + 标题 + 摘要），多条分享一次交出。
- 面板生命周期与宿主组件绑定，销毁即收口。

**Non-Goals:**

- 不做分享出方向的接收方选择 UI（系统面板负责）。
- 不做碰一碰（独立变更，见探索记录）。
- 不改动 `ShareAbility` 收向链路。
- ~~不做 App Linking~~（真机验收后按用户决策纳入本变更，见 D7；AGC 发布与域名部署为用户侧前置）。
- 不改动 `module.json5` 权限（新增的仅为 skills 域名声明，无新权限）。

## Decisions

### D1 出口模块形态：独立无 UI 模块 `common/ShareOut.ets`

静态入口 `ShareOut.shareBookmarks(records)` / `dismiss()`；内部持有当前 `ShareController`，重复 launch 前 dismiss 旧实例保证幂等。

- 备选 a：各入口组件内直接调 `systemShare` —— 否决：三处重复构造逻辑，dismiss 无统一落点，违反「一处出口」。
- 备选 b：挂到 `FlowRepository` —— 否决：Repository 是数据写路径（写 RDB + notify + 卡片），分享是纯 UI 出口，不产生本地状态，混入会污染职责与测试面。

### D2 数据构造：单条 `HYPERLINK`，多条聚合单条 `PLAIN_TEXT`

单条：`{ utd: uniformTypeDescriptor.UniformDataType.HYPERLINK, content: url, title, description }`；标题为空回退 URL；saved 层摘要取 `bookmark.description`，transient 页摘要为空。

多条：聚合为**一条** `{ utd: PLAIN_TEXT, content: 单行空格分隔 URL 串, title: 'N 条链接' }`，DEFAULT 预览。原因（真机验收修订）：平台不支持多条纯文本族记录分发——Share Kit FAQ「分享数据不支持多条纯文本类型分享」，实测 BATCH+多条 HYPERLINK 面板虽可拉起但接收方全线异常（QQ 拼成一行、备忘录只收一条、华为分享拒发），批量通道实际只对多文件记录可用（API 1003702001 注释同口径）；聚合文本 QQ 按整段 schema 解析，行内标题前缀与换行均报「schema不合法」（两轮真机实测），故取单行空格分隔——与 QQ 收到多记录时自行拼接的形态一致。

- 备选 a：TEXT 记录拼 URL 文本（单条场景）—— 否决：单条丢失标准类型语义，接收方无法按链接处理。
- 备选 b（原否决，真机实测后复活为多条定案）：多选拼成一条多行文本 —— 当时否决理由「接收方无法逐条打开」实测不成立：多记录才是全军覆没的形态，聚合多行文本反而是唯一全接收方可用的形态。
- 备选 c：多条 HYPERLINK 记录 + BATCH —— 否决：见上，平台分发链路不支持。

### D3 面板生命周期：宿主 `aboutToDisappear` 收口 + 模块内幂等 dismiss

`StreamHome` 与 `ReadingShell` 的 `aboutToDisappear` 调 `ShareOut.dismiss()`（try/catch 吞错）；模块内 launch 前 dismiss 旧 controller。

- 备选 a：各入口自持 controller —— 否决：三处重复，入口间切换时旧面板残留风险。
- 备选 b：不做 dismiss 依赖系统回收 —— 否决：宿主销毁后悬浮面板在真机可能残留，spec「生命周期一致」要求主动收口；应用整体退后台时面板本身随全屏模态不可见，由系统兜底。

### D4 入口位置与形态

- 行内面板：`QuickActionPanel` 非回收站分支，「打开」之后加 `ActionChip('分享')`（高频正向动作靠前）；回收站分支不加。
- 阅读层：`MoreMenu` 在「复制链接」后加 `MenuItem('分享')`，对所有层可用（含 transient，不要求先收藏）。
- 批量栏：`BatchActionBar` 非回收站分支、`selectedBookmarkIds.length > 0` 时加 `ActionChip('分享')`。
- 均为纯文字项，与现有 chip/MenuItem 同构。

- 备选 a：行内放在「删除」旁末位 —— 否决：分享是正向高频动作，与「打开」同类应靠前。
- 备选 b：阅读层 TopBar 加独立图标按钮 —— 否决：TopBar 已有 返回/标题/模式切换/「⋯」，空间紧张；菜单项即可发现。
- 备选 c：chip 带 SymbolGlyph 图标 —— 否决：现有 `ActionChip` 均为纯文字，引入图标破坏同构。

### D5 失败兜底：toast 轻提示

`launch` 前 context 缺失、或 promise reject 时 `AppState.shared.toast('分享面板拉起失败，请重试')`，无本地状态变更。

- 备选：静默失败仅记 hilog —— 否决：spec 要求用户可感知并重试。

### D6 批量无硬上限

记录仅含 URL/标题/摘要文本，不设条数上限；全选规模受列表分页天然约束。

- 备选：上限 N 条 + 截断提示 —— 否决：无实测性能问题前引入额外文案与截断语义；验收含大批量实测项，异常再补。

### D7 App Linking（收端就绪、发端暂缓——用户决策修订）

收端已落地并保留为休眠基础设施：`common/ShareUtil.ets` 的 `SHARE_LINK_HOST/PREFIX`、`shareLinkOf`/`shareLinkTargetOf` 编解码；`module.json5` 独立 skill（browsable + viewData + `{scheme:"https", host:"dunodoge.com", pathStartWith:"s"}` + `domainVerify:true`，与 flowpage:// 深链分 skill）；`EntryAbility.handleWant` 解包 `u` 进阅读层（transient + autoLoad，不写 RDB），非本域 http(s) 仍走 openInbox。

发端包装暂缓（2026-11-12 用户决策：AGC 配置受阻）：`ShareOut` 记录内容回退为原始 URL——服务器 `/s` 端点与 AGC 发布上线前，包装链接对未装应用/未过域名校验的设备是死链。恢复启用 = ShareOut 两处 `link.url` 改回 `shareLinkOf(link.url)` + 测试断言同步（见 spec「App Linking 收端路由」）。

用户侧前置（恢复启用前完成）：服务器部署 `/.well-known/applinking.json`（appIdentifier=6917619579162930870）与 `location /s { return 302 $arg_u; }`；AGC「App Linking → 应用链接」发布 `https://dunodoge.com`（交集校验，≤24h 生效）。

- 备选 a：包装链接先行上线 —— 否决：服务器未就绪时所有分享外链 404，比原始 URL 更糟。
- 备选 b：AGC 聚合链接（agconnect.link 前缀）—— 否决：需 agconnect-services.json 与短链服务，链接域名不受自己控制；自有域名 + /s 302 无状态、零数据落库，符合本地优先。

## Risks / Trade-offs

- [2in1 上分享面板 popup 形态与自由窗装饰的避让关系未知] → 面板属系统 UI，真机验收确认；若遮挡为系统行为，不在应用侧绕行。
- [数百条记录的面板预览性能未实测] → 记录轻量；验收任务含大批量档位，异常时回补 D6 上限。
- [宿主销毁与 dismiss 的竞态] → dismiss 全部 try/catch + 幂等，重复调用无害。
- [接收方对多条链接的兼容差异（已裁决）] → 真机实测 QQ/备忘录/华为分享均不能正确处理多条 HYPERLINK 记录（拍平/取首条/拒发），D2 改为聚合单条 PLAIN_TEXT；验收覆盖 QQ、备忘录、华为分享、中转站。

## Migration Plan

纯新增能力，无数据结构与权限变更。回滚 = 移除三入口调用与 `ShareOut` 模块，无残留状态。
