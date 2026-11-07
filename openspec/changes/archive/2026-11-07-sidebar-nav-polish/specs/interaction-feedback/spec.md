# Spec Delta

## Purpose

约束主交互面的操作反馈与图标规范：悬停/按压视觉反馈的覆盖范围与形态、文本字形图标的 SymbolGlyph 化替代、触控热区下限，保证 phone/tablet/2in1 输入方式（触控/鼠标/键盘）下的操作可感知性。

## ADDED Requirements

### Requirement: 主交互点提供悬停与按压反馈

主页头部按钮（☰/批量/收笺）、侧边栏与抽屉的导航行、筛选 chips、书签行操作（星标/更多）SHALL 在鼠标悬停与按压时呈现可感知的系统按压阴影反馈（`hdsEffect` 白色混合效果），反馈 SHALL 随指针离开/抬手立即消失，MUST NOT 残留；选中态 chips 的选中背景 MUST NOT 被反馈效果覆盖。反馈样式 SHALL 深浅色模式均可用。阅读页（ReaderView/ReadingShell）内部 MUST NOT 因本需求引入反馈效果。

#### Scenario: 鼠标悬停导航行
- **WHEN** 2in1 上鼠标悬停在侧边栏任一导航行
- **THEN** 该行出现按压阴影反馈，移开后立即消失无残留

#### Scenario: 按压筛选 chip
- **WHEN** 手机端按压任一筛选 chip
- **THEN** 按压期间该 chip 呈现按压态视觉变化，抬手后消失无残留，选中 chip 的选中背景保持不变

#### Scenario: 点击后反馈不残留
- **WHEN** 点击 ☰ 展开收起按钮或任一交互点并完成点击
- **THEN** 按压反馈随抬手消失，界面无持续阴影或高亮残留

#### Scenario: 阅读页不受影响
- **WHEN** 打开阅读页并悬停/按压正文内元素
- **THEN** 不出现新增的悬停/按压反馈样式，阅读性能无回归

### Requirement: 文本字形图标 SymbolGlyph 化

清除筛选 `×`、收笺 `+`、行内更多操作 `…` SHALL 改用系统 Symbol 图标渲染，MUST NOT 保留文本字形作为图标；替换后各入口的无障碍标签与行为 SHALL 与替换前一致。

#### Scenario: 清除筛选图标
- **WHEN** 主页存在标签或文件夹筛选
- **THEN** 清除入口显示 Symbol 关闭图标，点击行为与无障碍标签与此前一致

#### Scenario: 收笺按钮图标
- **WHEN** 查看主页收笺按钮
- **THEN** 按钮以 Symbol 加号图标 + 文字组成，点击仍打开收笺面板

### Requirement: 触控热区下限

可视尺寸不足 44vp 的可点击入口（如弹层内「取消」等小按钮）SHALL 通过响应区扩展使实际触控热区达到 44vp，点击行为不变。

#### Scenario: 弹层取消按钮热区
- **WHEN** 打开行内操作弹层并点击「取消」文字周边空白
- **THEN** 命中范围覆盖至少 44vp 热区，点击即关闭移动面板
