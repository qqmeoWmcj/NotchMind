# AGENTS.md — AI 热点个人创作 Agent

面向个人创作者的本地 AI 热点抓取、深度认知提炼与多平台草稿生成工具，输出排列分明的 Obsidian 知识库与 Google NotebookLM 源文档。

## 关键文档路标
- 技术选型与约束：`docs/decisions-tech-stack.md`
- 上手与运行说明：`README.md`

## 开发与验收规则

| 规则 | 由什么拦住 |
|---|---|
| 单个代码文件不超过 20 KB（约 5,000 token） | `.git/hooks/pre-commit`（超标自动拒绝提交） |
| 交差前跑通真实行为测试与 `--dry-run` | `uv run pytest` + `uv run python -m src.main run --dry-run` |
| 密钥绝不硬编码进代码或提交到 Git | `.gitignore` 忽略 `.env` |

## Agent 工作守则
1. **文件大小**：提交被 pre-commit 钩子拒了，照报错按功能拆成多个文件再提交，不要绕过钩子。
2. **避免重复**：写新函数或新规则前，先搜项目里有没有现成的，同一条业务规则只留一个出处。
3. **测试底线**：只写守住真实行为的测试（真写 SQLite、真生成 Markdown 文件），不写顶掉核心逻辑的假 mock。
4. **模型配置**：所有模型名称与密钥统一从 `.env` 读取（`GEMINI_API_KEY`、`GEMINI_MODEL`），不要在代码里写死。
5. **子代理极简汇报**：主会话严禁大段倾倒子代理长文或表格。主 Agent 只在主对话输出极简一行卡片提示（如：`✅ 子代理 {agent_name} 已完成 {task}。详情可点击子代理对话查看。`），详细报告与执行日志全部归位于子代理独立对话中。
