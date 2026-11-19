# AI 热点个人创作 Agent（Hotspot-to-Obsidian）

自动抓取全球 AI 热点 → 本地 SQLite 长期记忆去重 → Gemini 深度认知提炼与三平台草稿生成 → 输出排列分明的 **Obsidian 本地知识库** 与 **Google NotebookLM 源文档**。

## 快速开始

1. 复制 `.env.example` 为 `.env`，填入你的 `GEMINI_API_KEY`（以及可选的 `OBSIDIAN_VAULT_PATH`）。
2. 在项目目录运行：
   - **双击运行（Mac）**：直接双击项目根目录的 `运行热点创作.command`。
   - **命令行运行**：
     ```bash
     uv run python -m src.main run --top 3
     ```
   - **仅测试抓取（不消耗 Token）**：
     ```bash
     uv run python -m src.main run --dry-run
     ```
3. 打开 Obsidian，选择本项目下的 `vault/` 文件夹（或你在 `.env` 中配置的自有仓库路径）即可浏览排列分明的日报、卡片和草稿；把 `04-NotebookLM-Exports/` 里的文件拖入 [Google NotebookLM](https://notebooklm.google.com/) 即可生成播客或深度问答。
