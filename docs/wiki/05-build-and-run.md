# 构建与运行

## 1. 工具链

| 工具 | 要求 / 来源 |
|---|---|
| DevEco Studio / HarmonyOS SDK | API 26，`compileSdkVersion` / `targetSdkVersion` / `compatibleSdkVersion` 均为 `26.0.0` |
| hvigor | **7.26.8 或更高**，必须支持 `modelVersion 26.0.0` |
| ohpm | 随 HarmonyOS command-line-tools 提供 |
| hdc | 随 SDK toolchains 提供 |
| CodeLinter | 随 command-line-tools 提供（当前 6.0.140） |

`build-profile.template.json5` 与 `hvigor/hvigor-config.json5` 是版本信息的源头；`build-profile.json5` 是本地
签名配置，被 `.gitignore` 忽略，不要提交。新克隆先复制模板并在 DevEco Studio 的
**File > Project Structure > Signing Configs** 中配置签名。

## 2. 关键工具链陷阱

本工程 `modelVersion` 是 `26.0.0`，而 `devecocli build` 当前内置的 hvigor 只支持到 `6.1.0`，会直接失败：

```
ERROR: 00303028 Configuration Error
Unsupported modelVersion of Hvigor 26.0.0.
The supported Hvigor modelVersion is 6.1.0.
```

**不要**为了让它通过而改低 `modelVersion`。改用 SDK 自带 hvigor：

```bash
hvigorw --version    # 7.26.8
```

若 PATH 中没有 `hvigorw`，使用 command-line-tools 中的路径：

```bash
/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/hvigor/bin/hvigorw --version
```

## 3. 构建

```bash
# 首次克隆 / 依赖变化后
ohpm install

# 命令行构建需指向 API 26 SDK（本机路径）
export DEVECO_SDK_HOME=/data/service/hnp/hmos-clt.org/hmos-clt_1.0.0/sdk

# 构建 HAP
hvigorw clean assembleHap
```

产物：

```
entry/build/default/outputs/default/entry-default-signed.hap
entry/build/default/outputs/default/entry-default-unsigned.hap
```

`hvigorw assembleHap` 默认等价于 `--mode module -p module=entry@default -p product=default -p buildMode=debug`。
Release 构建在 `entry/build-profile.json5` 中关闭了混淆（`obfuscation.ruleOptions.enable=false`）。

## 4. 安装与运行

```bash
hdc list targets
hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc shell aa start -a EntryAbility -b com.dunodoge.flowpage
```

- 真机首次安装需已配置有效签名；签名失败不要在命令行反复重试，回到 DevEco Studio 配置 Signing Configs。
- 深链验证：从服务卡片进入，或使用带 `flowpage://bookmark/<id>` 的 Want 拉起 `EntryAbility`。
- 分享扩展验证：在系统浏览器/备忘录分享一个链接，选择“流笺”。
- 服务卡片需在桌面长按添加；`form_config.json` 已注册 2×2 今日笺与 2×4 最近。

## 5. 设备端测试

测试位于 `entry/src/ohosTest`，10 个套件、81 个 Hypium 用例（2026-10-21 第三/四批 + 收尾批次；模拟器 81/81，手机主功能 77/77，81 版因锁屏未复跑）：

| 套件 | 覆盖 |
|---|---|
| `WebDavXmlTest` | ETag 大小写/缺失、目录过滤、URL 解码 |
| `SyncPlannerTest` | 上传/下载/跳过/采纳 ETag 的规划分支 |
| `SyncEngineTest` | FakeTransport 驱动上传、下载、墓碑删除、重试、不复活、标签合并不覆盖远端、schema 1 下载保留本地 folderPath/source、schema 2 下载采用远端值、恢复本地后下轮上传 |
| `SyncStoreTest` | URL 归一化、去重、墓碑、dirty 竞态、冲突记录、SyncRecord schema 2、旧库 `applySchema` 迁移 |
| `TagSyncTest` | 标签改名/合并/删除 dirty 与 `search_text` 重建、只含目标标签的书签不受影响、重名合并、回收站计数 |
| `SnapshotTest` | clearAll/purgeExpired/purge/purgeFromRemote 快照文件清理 |
| `ConflictTest` | 冲突计数、列表、恢复本地/采用远端、采用远端保留 folderPath/source |
| `RepositoryTest` | 单次编辑 rev、阅读状态、自动快照开关、摘要口径、批次回滚、卡片序列化与 preferences 往返、纯函数 |
| `QueryTest` | SQL 分页、关键字/标签过滤、LIKE 转义、域名排序、冷/热查询基准 |
| `ImportTest` | 解析统计、预览、去重、取消、失败清单、5000 条导入记录（12s 保险阈值） |

```bash
hvigorw --mode module -p module=entry@ohosTest -p product=default -p buildMode=debug assembleHap

hdc install -r entry/build/default/outputs/default/entry-default-signed.hap
hdc install -r entry/build/default/outputs/ohosTest/entry-ohosTest-signed.hap

hdc shell aa test -b com.dunodoge.flowpage -m entry_test \
  -s unittest OpenHarmonyTestRunner -s timeout 90000
```

- 设备端用例依赖 `UIAbility` 上下文（`abilityDelegatorRegistry.getCurrentTopAbility()`），**不能当本地单测跑**。
- 纯函数（卡片编码、高亮、分段）另有本地入口 `entry/src/test`：`hvigorw test`。它需要 SDK 的 previewer
  可执行文件；本机 SDK 未安装该包时会报 `previewer/common/bin ENOENT`，属环境缺失。
- `SyncEngineTest` / `SyncStoreTest` 各用独立数据库名，并在 `beforeEach` 调 `Database.reset()`；不要并行跑两个测试进程。
- 测试 HAP 的模块名是 `entry_test`（`entry/src/ohosTest/module.json5`）。

## 6. 静态检查

```bash
codelinter -c code-linter.json5
```

当前结果：**0 error / 0 warn / 1 suggestion**（`startIcon.png` 超过 256×256 的启动性能建议）。
`code-linter.json5` 排除 `ohosTest`、`test`、`mock`、`build` 与依赖目录。

改动 `.ets` 后优先跑会话内的 `check_ets_files` 做快速 ArkTS 严格模式检查，再跑完整构建。已知构建警告：

- `getContext`、`AlertDialog`、`matchMediaSync` 被标记 deprecated；
- 这些是 warning，不影响构建，但新代码应优先使用 `UIContext`/`this.getUIContext()` 等新接口。

## 7. 排错

| 现象 | 处理 |
|---|---|
| `Unsupported modelVersion of Hvigor 26.0.0` | 换用 SDK hvigor 7.26.8+，不要改工程 modelVersion |
| 签名失败 / 未生成 signed HAP | 复制模板后在 DevEco Studio 配置 Signing Configs |
| 增量构建异常 | 删除 `.hvigor/` 与 `entry/build/` 后重跑（都是生成物） |
| 同步 401 | 坚果云使用“应用密码”，不是登录密码 |
| 同步 409/412 | 清理旧服务器 ETag（同步页换地址会自动清），确认远端目录权限 |
| 卡片不刷新 | 检查 `flowpage_card` 快照、卡片是否已添加；跨进程读 preferences 必须清缓存 |
| 数据没更新 | 是否绕过 `FlowRepository` 直接写 DAO；直接写不会触发 `refreshTick` 与卡片推送 |

## 8. 生成物与提交边界

不要提交：`build-profile.json5`、`.hvigor/`、`entry/build/`、`oh_modules/`、`local.properties`、`.idea/`、
`.bitfun/`、`*.hap`、签名材料。可提交：源码、`build-profile.template.json5`、`code-linter.json5`、`docs/`、
`README.md`、`AGENTS.md`。
