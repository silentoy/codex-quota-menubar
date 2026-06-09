## SwiftUI UI / Design Rules
- **每次生成或修改 UI 前，请务必先阅读 DESIGN.md**，确保对本项目的 UI 规范（字号、间距、圆角、背景材质等）有清晰认知。
- **遵循 macOS 设计规范**：优先使用 SwiftUI 原生的布局原语（VStack, HStack, ZStack, Spacer），禁止在没有极特殊原因的情况下硬编码绝对的 view 宽高。
- **保证间距和圆角的一致性**：对卡片和输入框使用一致的圆角 `cornerRadius(8)`，边距遵循 `.padding(14)`（主容器）或 `.padding(10)`（子卡片）。
- **支持自适应外观 (Dark/Light Mode)**：禁止在 SwiftUI 中硬编码绝对的白色或黑色背景。必须使用语义化的系统颜色（如 `.primary`、`.secondary` 等）或自适应模糊材质（如 `.regularMaterial`、`.thinMaterial`），确保在 macOS 的浅色和深色主题下都完美呈现。
- **文本层级控制**：字号必须匹配 DESIGN.md 的定义。使用系统的动态文本样式（如 `.font(.headline)`、`.font(.caption)`），对于数值和时间等频繁变动的文字，必须附加 `.monospacedDigit()` 以避免布局因数字宽度变动产生抖动。
- **完善交互与无障碍支持**：所有交互元素都要拥有正确的 hover 效果，并包含 tooltip（`.help(...)`）和无障碍标签（`.accessibilityLabel(...)`）。
- **遵循合理的间距体系**：禁止随意使用神奇常数（如 `padding(13)`），必须严格按照 DESIGN.md 中的 `14`、`10`、`8` 的间距体系来控制排版。
