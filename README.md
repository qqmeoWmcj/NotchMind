# NotchMind — 原生 macOS 灵动岛伴随式学习与 AI 认知提炼系统

面向创作者与自学者的本地 AI 认知提炼工具：全局常驻 **macOS 26+ Liquid Glass 灵动岛 HUD**，伴随同看（B站 / YouTube / PiliPlus / 浏览器），深度费曼结构化提取并直接反哺本地工程（如 Blender 3D / 编程项目），沉淀至单文件 **Obsidian 本地知识库** 与 **Google NotebookLM**。

---

## 核心特性

- 🏝 **原生刘海灵动岛 & Liquid Glass 液态玻璃**：
  - MacBook 硬件刘海屏收缩态纯黑无缝隐身，工作时双耳微光脉动；
  - 展开态支持 **三档液态玻璃色调调节**（Clear 最玻璃 / Regular 默认中间档 / Tinted 哑光毛玻璃）；
  - 双段式环境景深物理投影，严格单层玻璃，对比度 ≥ 4.5:1，彻底去 AI 味（de-slop）。
- 🖥 **全屏与外接显示器原生支持**：
  - 基于 AppKit `HUDHostingView.acceptsFirstMouse`，全屏视频/网页下**首击直接交互**，透明空白零拦截穿透；
  - 外接屏幕支持 **顶部居中、左侧避让、右侧安全区、自由拖拽记忆** 4 档定位；
  - 全局快捷键：**`⌘⌃N`** 随时展开/折叠 HUD，**`⌘⇧S`** 瞬时抓拍当前窗口画面。
- 🔄 **学习闭环：直接反哺本地项目（彻底解决学 Blender 总结太泛的痛点）**：
  - 费曼深拆：前置依赖 + 核心概念类比 + 避坑边界；
  - 实操参数与配方：提取具体参数与步骤，一键**「拷贝实操任务配方 (- [ ])」**；
  - 靶向项目回流：一键点击**「导出到项目优化清单」**，自动追加写入本地项目的 `TODO.md` 或 `learning-feedback.md`；
  - 主动回忆自测卡：卡片内建交互式折叠问答，点击查看答案，以测代练。
- ⚡️ **一句话极速上传与更新 GitHub**：
  - 在工作区终端运行 `./sync.sh` 或 `uv run python -m src.main push`，自动完成安全审查、打包 Commit 并一键直推；
  - 在对话中直接对 Agent 说一句 **“上传”** 或 **“同步仓库”** 即可全自动执行。

---

## 快速上手

### 1. 运行 NotchMind macOS 原生应用
编译与运行 SwiftUI 原生应用：
```bash
# 启动原生应用
cd NotchMind && swift run NotchMind
# 或直接打开打包好的安装镜像（位于 dist/）
open dist/NotchMind.dmg
```

### 2. 运行 Python 热点抓取与单文件知识库提炼
```bash
# 抓取全球 AI 热点并沉淀知识库与 NotebookLM
uv run python -m src.main run --top 3

# 仅测试抓取与记忆去重（不消耗 Token）
uv run python -m src.main run --dry-run
```

### 3. 一键同步 GitHub
```bash
# 一键安全检查、提交并推送到 GitHub
./sync.sh "feat: update my workspace"
```
