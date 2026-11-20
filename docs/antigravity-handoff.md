# Antigravity 协作路标（AGENT-HUD 通道）

> 本文件写给在本项目中工作的所有 agent（Antigravity / Claude Code / Codex 等）。
> 通道依赖 [Agent HUD](https://github.com/jazzenchen/agent-hud-open) 的内置 MCP 服务，安装见 `scripts/setup_agent_hud.sh`。

## 通道约定

- **消息总线**：Agent HUD 内置 MCP（stdio）。工具：`list_sessions` / `send_message` / `get_message` / `start_session` / `list_models`。
- **命名**：不同客户端的工具名前缀不同（Claude Code：`mcp__agent-hud__send_message`；Codex：`mcp__agent_hud__send_message`；Antigravity 在 tool 描述里称为 agent-hud 的 send_message）。语义一致：传话、回复、新开会话。
- **发送语义**：默认 enqueue（对方空闲才送达，不打断进行中的一轮）；`delivery: "steer"` 仅在用户明确要求插入进行中的轮次时使用。`reply_to` 带原消息 ID 原路飞回。
- **链与回数**：每条消息属于一条 chain，默认上限 10 pass（设置 → Agents → Agent tools → Passes in a row）。超出会被拒收，需要用户介入。
- **验收信号**：纸飞机在 HUD 上从发信 agent 飞到收信 agent 再飞回 = 一来一回完成。回复通过 `send_message` + `reply_to` 发回，而不是普通文本输出。

## 分工提案（ai-hotspot-creator 项目）

- **Antigravity（主推进）**：NotchMind Swift UI（macOS 端灵动岛 HUD）、docs 演进决策案维护。
- **Claude（本仓库代笔）**：Python 管线（collectors / agent / workbench / exporters）、测试与 `--dry-run` 验收。
- **协作节奏**：一方完成一个阶段，用 `send_message` 通知对方「什么文件改了、为什么、下一步谁做什么」；接收方用 `reply_to` 回执确认或提出异议。
- **上下文共享**：同一项目文件夹，agent 自己去读代码，消息里只传结论不传整段会话。

## 工程规则（与 AGENTS.md 一致，对所有 agent 生效）

1. 单个代码文件 ≤ 20 KB；超标按功能拆文件，不绕过 pre-commit 钩子。
2. 写新函数前先搜项目里有没有现成的，同一条规则只留一个出处。
3. 测试守真实行为（真写 SQLite、真生成 Markdown），不写假 mock。
4. 密钥与模型名只从 `.env` 读（`GEMINI_API_KEY` / `GEMINI_MODEL`），绝不硬编码。
5. 交差前跑：`uv run pytest` + `uv run python -m src.main run --dry-run`。

## 快速上手（新会话的第一条消息模板）

```
[来自 <客户端> · <会话标题>]
阶段完成：<一句话结论>
改动文件：<file1, file2...>
下一步：<谁做什么>
请确认或提出异议（send_message + reply_to）。
```

## 已知限制（来自 agent-messages.md）

- Antigravity：语言服务器在跑时 enqueue/steer/interrupt 都可用；服务器不在线时 `reachable: null`，消息排队等它上线。
- Claude Code：通过 Agent HUD 插件收消息，空闲时投递，slash 命令会被拒。
- 空闲的 hook 型客户端（Cursor/TRAE 等）要等用户手动发起一轮才收得到。
- 消息只传文字不传会话：把结论写清楚，对方自己去读代码。
