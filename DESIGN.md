# DESIGN.md — NotchMind Apple Native HUD 设计规范（A′ 灵动岛纯黑 + macOS 26 Liquid Glass）

本项目 macOS 原生应用（**NotchMind**）面向 **macOS 26+**，采用 **Apple HIG 与原生 Liquid Glass** 设计语言，对标 `NotchDrop`、`boring.notch`、`Ice`、`Maccy`、`TokenMonitor` 与 `Agent HUD`，并严格保持去 AI 味克制感。

## 1. HUD 本体形态（A′：不透明纯黑灵动岛）
- **刘海屏（MacBook）**：
  - **底色**：不透明纯黑（`#000000`），顶边与硬件刘海无缝融合，**不加顶部高光描边**（避免与刘海产生接缝，也不受系统「降低透明度」或全屏黑边影响）。
  - **空闲隐身**：空闲/隐私休眠时宽度收起至与硬件刘海一致，在透明菜单栏上完全隐形，不打扰桌面。
  - **工作伸耳**：仅在伴随同看或解析中时，以原生弹簧物理阻尼从刘海两侧平滑伸出对称“耳朵”，展示白色单色 SF Symbol 与 `.symbolEffect(.pulse)` 脉动。
  - **悬停展开**：鼠标移入刘海区平滑展开，采用苹果式同心连续圆角（`.continuous`）。**HUD 全界面只允许外壳一层材质；内部控件一律使用 fill token（禁止玻璃套玻璃，也禁止在纯黑底上叠加内层玻璃）**。
- **液态玻璃对比度兜底（Liquid Glass 规范）**：
  - 液态玻璃模式 = **外壳单层玻璃 + 对比度衬底（scrim）+ 按预设锁定色彩模式（`.dark` / `.light`）**，通过 `@Environment(\.notchPalette)` 统一注入语义 token。
  - 以纯白壁纸为最坏情况，4 种预设（`regular` / `clear` / `tintedDark` / `frosted`）下 primary 文字对比度均须 ≥ 4.5:1，并响应系统「降低透明度」与「增强对比度」辅助功能设置。
  - **刘海屏收起态始终纯黑**，仅在展开态启用液态玻璃，避免硬件刘海周围出现灰色光晕。
- **外接显示器 / 无刘海屏（双外观可选）**：
  - 在设置中提供两种悬浮胶囊外观切换（参考 TokenMonitor）：**纯黑灵动岛风（默认，保持跨屏识别一致）** 或 **系统液态玻璃材质（Liquid Glass）**。

## 2. 色彩与状态规范（Apple 菜单栏单色 + 极简黑白灰）
- **严格黑白灰**：HUD 本体文字使用 `NotchPalette` 三级对比度（`primary` / `secondary` / `tertiary`），状态指示遵循 Apple HIG 菜单栏单色模板图标规范，通过 SF Symbol 形态（`eye`、`sparkles`、`pause.circle`、`checkmark.circle.fill`）与脉动节奏区分，**严禁使用 `Color.cyan`、彩色呼吸光晕、彩虹分类标签与霓虹渐变**；成功状态仅靠 SF Symbol 形态变化表达，不使用绿色。
- **唯一语义色例外**：仅在真正发生错误时，使用 Apple 系统红（`Color.red`）做简短提示。
- **独立设置窗口**：采用标准 macOS 原生材质（对标 `Ice`），自动跟随系统浅色/深色模式。

## 3. 排版、图标与防误抓边界
- **排版**：全界面使用系统 `SF Pro`，时间与计数使用 `.monospacedDigit()`，最多 4 档字号（`15pt` / `13pt` / `12pt` / `11pt`），最小不低于 `11pt`。
- **文案与图标**：统一使用线性 `SF Symbols`，**严禁 Emoji**；标题与分区直写功能名，**严禁大标题下堆砌废话副标题**；按钮直写动作（`开始同看`、`抓当前帧`、`拆解链接`、`打开 Obsidian`）。
- **防自采机制**：截屏核心依赖 `ScreenCaptureKit` 的单窗口过滤器 `SCContentFilter(desktopIndependentWindow:)` 仅抓取目标窗口 `CGWindowID`，`NSPanel.sharingType = .none` 作为附加保险。
