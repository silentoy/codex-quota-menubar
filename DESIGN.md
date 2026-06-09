# DESIGN.md — Codex Quota Menubar

## 视觉主题 (Visual Theme)
极简、信息密集、现代的 macOS 原生菜单栏应用风格（Menu Bar App style）。采用结构化的列表、进度条和精致的描边，使用系统模糊材质材质底色（`.regularMaterial` 或 `.thinMaterial`）以显得原生且高级。

## 配色方案 (Color Palette)
- **主文本 (Primary Text)**: `.primary`（自动适应系统深色/浅色模式）
- **次要文本 (Secondary Text)**: `.secondary`（淡化标签或状态描述）
- **背景 (Background)**: `.regularMaterial`（主 Popover 的背景色）
- **卡片/分块背景 (Card Background)**: `.thinMaterial`（用于瓶颈提示、趋势图表等卡片区块）
- **边框/描边 (Border / Stroke)**: 统一使用带透明度的描边（`.opacity(0.12)` 或 `.opacity(0.24)`），线宽统一为 `1`
- **动态额度状态颜色 (Dynamic Quota States)**:
  - 正常 (Normal/Success): `store.menuColor` 或系统 Accent
  - 偏低 (Warning/Low): `.quotaLow` (黄色/橙色)
  - 临界/失败 (Critical/Failed): `.quotaCritical` (红色)

## 排版系统 (Typography)
统一使用 macOS 系统字体字重与规格：
- **标题/头部**: `.font(.headline)`
- **正文加粗/次级标题**: `.font(.subheadline.weight(.semibold))`
- **正文/标准标签**: `.font(.subheadline)`
- **副标题/辅助说明**: `.font(.caption)`
- **微型标签/徽章**: `.font(.caption2.weight(.medium))` 或 `.font(.caption2.weight(.semibold))`
- **等宽数据**: 对于百分比、重置时间、额度数值等经常变动的数字，统一追加 `.monospacedDigit()` 以免排版抖动

## 间距与布局 (Spacing & Layout)
- **容器边距**: 统一使用 `.padding(14)`
- **主容器垂直间距**: `VStack(spacing: 14)`
- **子模块/卡片内部垂直间距**: `VStack(spacing: 10)`
- **卡片内部边距**: `.padding(10)`
- **圆角**: 卡片、高亮区块和交互按钮使用统一的圆角 `RoundedRectangle(cornerRadius: 8)`
- **按钮尺寸**: 合理配合 `.controlSize(.regular)` 或 `.controlSize(.small)` 

## 组件模式 (Component Patterns)
- **卡片区块**: 使用 `.thinMaterial` 背景，配合 `RoundedRectangle(cornerRadius: 8)`，并通过 `.overlay` 追加 `RoundedRectangle(cornerRadius: 8).stroke(color.opacity(0.12), lineWidth: 1)` 描边。
- **按钮布局**: 多按钮横排时，利用 `.frame(maxWidth: .infinity)` 进行等宽平铺，并配合 `HStack` 装载图标和文案。
- **信息展示行**: 统一使用两端对齐的 `HStack`（中间用 `Spacer()`），左边是 `.secondary` 标签，右边是 `.primary` 值。
