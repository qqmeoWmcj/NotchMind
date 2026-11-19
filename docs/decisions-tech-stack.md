# 技术选型决策记录（Tech Stack Decisions）

- **日期**：2026-11-19
- **项目**：AI 热点个人创作 Agent（Hotspot-to-Obsidian）
- **最终选定**：**方案 A — 纯 Python 本地脚本 + Mac 双击启动**

## 核心约束
1. **使用场景**：个人向 AI 热点内容创作（1 人使用），无需登录、云端同步或多人协作。
2. **输出载体**：本地 Obsidian Vault（排列分明的 5 级目录 + YAML Frontmatter + 双向链接 + 每日 MOC）+ Google NotebookLM 专属汇总源文档。
3. **网络环境**：可直连 Google Gemini API、GitHub、Hugging Face、Hacker News。
4. **维护偏好**：不习惯手动操作命令行，由 AI Agent 协助配置与维护，日常希望零后台服务、一键/双击运行。

## 选定技术栈
- **语言与包管理**：Python 3.11 + `uv`（极速虚拟环境与依赖管理）。
- **大模型 SDK**：Google 官方 `google-genai`，通过 `.env` 配置 `GEMINI_API_KEY` 与 `GEMINI_MODEL`（默认 `gemini-4-argon`，支持按需切换 `gemini-3.8-flash` 或内测模型 ID）。
- **热点抓取**：`httpx`（异步/超时容错请求）+ `feedparser`（RSS 解析），全部使用免费公开接口（HN Firebase API、GitHub Search API、Hugging Face Daily Papers JSON、精选 AI RSS）。
- **本地长期记忆**：Python 内置 `sqlite3`（单文件 `data/memory.db`，按话题指纹去重，零运维）。
- **测试框架**：`pytest`（只测真实用户可感知行为，不写假 mock）。

## 为什么不选其他方案
- **方案 B（本地 Web 工作台）**：需要维护前后端两个服务与端口，增加日常启动与排错成本；核心逻辑与方案 A 完全解耦，未来需要界面时可无痛套壳。
- **方案 C（GitHub Actions 云端同步）**：链路长，本地改笔记易与云端自动推送产生 Git 冲突。
