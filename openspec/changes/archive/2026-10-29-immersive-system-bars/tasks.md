# Tasks

## 1. 基线与容器扩展

- [x] 1.1 基线检查：对 `entry/src/main/ets/pages/Index.ets`、`entry/src/main/ets/components/InboxSheet.ets`、`entry/src/main/ets/pages/SharePage.ets` 运行 check_ets_files，确认修改前无既有语法/类型错误
- [x] 1.2 `entry/src/main/ets/pages/Index.ets`：根 Stack（paper 背景，bindContentCover 宿主）附加 `expandSafeArea([SafeAreaType.SYSTEM], [SafeAreaEdge.TOP, SafeAreaEdge.BOTTOM])`，背景绘制延伸至状态栏/导航条区域、子内容保持安全区布局；同文件 FolderDrawer 抽屉列（paper + 右侧边框线）与抽屉遮罩（overlay）各附加 TOP+BOTTOM 扩展；check_ets_files + hvigorw assembleHap 收尾
- [x] 1.3 `entry/src/main/ets/components/InboxSheet.ets`：全屏遮罩 Column（overlay）附加 TOP+BOTTOM 扩展；底部面板 Column（surface、上圆角）附加仅 BOTTOM 扩展（surface 延伸至导航条下方消除与 paper 的色差接缝，面板内容与圆角不变）；check_ets_files + hvigorw assembleHap 收尾
- [x] 1.4 `entry/src/main/ets/pages/SharePage.ets`：根 Column（paper，ShareAbility 独立窗口）附加 TOP+BOTTOM 扩展，顶部操作栏与底部保存按钮保持安全区布局；check_ets_files + hvigorw assembleHap 收尾
- [x] 1.5 零改动回归确认（不变量）：`entry/src/main/ets/pages/Index.ets` 的 `bindContentCover` 保持 `enableSafeArea: true`、`entry/src/main/ets/components/ReadingShell.ets` 无任何修改；`entry/src/main/ets/entryability/EntryAbility.ets` 无新增 window API 调用；`entry/src/main/resources/base|dark/element/color.json` 成对未动；D2 兜底 A 与 D1 兜底 B 均未触发

## 2. 规范与验证

- [x] 2.1 代码规范自查（3 个修改文件）：ArkTS 严格子集（无 any/as）、V2 装饰器无 V1 混入、颜色一律 `$r('app.color.*')`；check_ets_files 对 3 文件零特性诊断（仅存量 matchMediaSync/getContext 弃用告警）+ hvigorw assembleHap 构建成功（产物 entry/build/default/outputs/default/entry-default-signed.hap）收尾
- [x] 2.2 `codelinter -c code-linter.json5`：0 error / 0 warning（1 条存量 startIcon 性能建议，与本次无关）
- [x] 2.3 部署 `devecocli run --skip-build` 至 HUAWEI MateBook Pro，应用启动、进程存活；真机目视验证（用户完成）：深浅色整屏背景贯通、系统栏无色块边界、内容零遮挡、抽屉边框线贯通——通过
