# 流笺 FlowPage

把散落在浏览器、聊天和剪贴板里的链接收进一册可离线、可搜索、可同步的「笺」。

FlowPage 是一款本地优先的 HarmonyOS 链接收笺应用：数据先落在本机 RDB，WebDAV 只负责在设备之间增量同步；
没有账号体系，也不依赖云端即可使用。支持手机、平板与 2in1。

## 功能

- **收笺**：手动输入、粘贴板识别、系统分享扩展、浏览器 HTML 书签导入。
- **整理**：标签、未读/星标/归档/回收站、全文搜索（标题、域名、描述、摘录、备注、标签）。
- **阅读**：抓取标题/摘要/站点/图标，保存纯文本正文快照；正文、摘录、备注三态阅读与编辑，字号可调。
- **同步**：标准 WebDAV（坚果云、群晖、Alist 等），Basic Auth + 应用密码；按 ETag 增量、LWW 合并、
  本地修改 `dirty` 标记、墓碑删除，凭据经 HUKS AES-256-GCM 加密后落盘。正文快照不上传。
- **系统能力**：`flowpage://bookmark/{id}` 深链、应用接续、系统分享面板、2×2「今日笺」与 2×4「最近」服务卡片。
- **一多**：手机单栏、平板两栏、2in1 三栏（1000vp 以上显示侧栏）；米白纸感黑白主题，支持跟随系统/浅色/深色。
- **数据迁移**：导入 Netscape 格式 HTML、导出 JSON / HTML、清空本地数据。

## 技术栈

- HarmonyOS Stage 模型，ArkTS + ArkUI，状态管理 V2
- 单模块 `entry`（HAP），API 26，设备类型 `phone` / `tablet` / `2in1`
- 关系型数据库 RDB（`flowpage.db`，6 表 + 6 索引），preferences，应用沙箱文件快照
- 无第三方运行时依赖

## 目录结构

```
FlowPage/
├── AppScope/                     # bundleName / 版本 / 应用图标
├── build-profile.template.json5  # 根构建配置模板（本地 build-profile.json5 含签名，已被 gitignore）
├── code-linter.json5             # CodeLinter 规则
├── docs/                         # 产品、技术、UI、验收文档 + wiki/ 分层 Code Wiki
├── entry/
│   └── src/
│       ├── main/
│       │   ├── module.json5      # 权限、Ability、页面与卡片配置
│       │   ├── ets/
│       │   │   ├── entryability/ # EntryAbility：深链、接续、仓库初始化
│       │   │   ├── shareability/ # ShareExtensionAbility
│       │   │   ├── formability/  # FormExtensionAbility（服务卡片）
│       │   │   ├── pages/        # Index、SharePage（仅有的两个页面路由）
│       │   │   ├── components/   # 首页流、详情、收笺面板、导航
│       │   │   ├── common/       # AppState、URL/日期工具、枚举
│       │   │   ├── model/        # Bookmark、Tag、Tombstone 等
│       │   │   ├── repository/   # FlowRepository（UI 唯一数据入口）
│       │   │   ├── core/db/      # Database、BookmarkDao
│       │   │   ├── core/service/ # 元数据、快照、服务卡片
│       │   │   ├── core/sync/    # WebDAV、同步规划与合并
│       │   │   ├── core/parser/  # 浏览器书签 HTML 解析
│       │   │   ├── core/security/# HUKS 凭据加密
│       │   │   └── widget/       # 服务卡片 UI（V1 装饰器）
│       │   └── resources/        # 颜色、字符串、路由、卡片配置、图标
│       └── ohosTest/             # Hypium 设备端测试
└── hvigor/
```

## 构建与运行

前置：DevEco Studio / HarmonyOS SDK（API 26 与 `modelVersion 26.0.0`）以及 hvigor 7.26.8。

```bash
# 首次克隆：生成本地签名配置（含本机签名材料，不要提交）
cp build-profile.template.json5 build-profile.json5

# 构建（使用 SDK 自带 hvigor；devecocli 内置 hvigor 仅支持 modelVersion 6.1.0）
hvigorw assembleHap

# 安装并启动
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.dunodoge.flowpage
```

更完整的设备端测试、静态检查与故障排查见 [docs/wiki/05-build-and-run.md](docs/wiki/05-build-and-run.md)。

## 测试

`entry/src/ohosTest` 共 10 个 Hypium 套件 / 81 个用例，覆盖 URL 归一化与去重、ETag 解析、同步上传/下载/跳过、
墓碑删除与重试、`dirty` 竞态、标签 `search_text` 重建、冲突记录与导入/查询基准。测试需要设备或模拟器，且需先安装主 HAP：

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap
hdc shell aa test -b com.dunodoge.flowpage -m entry_test -s unittest OpenHarmonyTestRunner -s timeout 90000
```

## 已知边界

- 2026-10-21 复审结论与下一步清单见 [docs/08-代码复审与下一步计划.md](docs/08-代码复审与下一步计划.md)；当前为内部 Alpha，不建议直接按 1.0 发布。
- 鸿蒙沙箱无法直接读取其他浏览器的书签库；迁移通过 HTML 导入、分享收笺与粘贴完成。
- 分布式 KV 同局域网同步、App Linking HTTPS、碰一碰、冲突记录 UI 尚未实现。
- 同步采用 LWW，极端并发修改时冲突记录会写入 `conflict` 表，但当前没有查看/合并入口。
- 正文快照是纯文本，不保留图片与复杂排版；网页抓取受登录、反爬与网络限制。

## 文档

- [docs/wiki/](docs/wiki/README.md)：分层 Code Wiki（架构、UI、数据、同步与服务、构建运行）
- [docs/README.md](docs/README.md)：产品与设计文档索引
- [AGENTS.md](AGENTS.md)：给编码代理的项目约定与构建注意事项
