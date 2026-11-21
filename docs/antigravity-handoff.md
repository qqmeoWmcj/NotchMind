# Antigravity 协作路标（AGENT-HUD 通道）

> 本文件写给在本项目中工作的所有 agent（Antigravity / Claude Code / Codex 等）。
> 通道依赖 [Agent HUD](https://github.com/jazzenchen/agent-hud-open) 的内置 MCP 服务，安装见 `scripts/setup_agent_hud.sh`。

## 通道约定

- **消息总线**：Agent HUD 内置 MCP（stdio）。工具：`list_sessions` / `send_message` / `get_message` / `start_session` / `list_models`。
- **命名**：不同客户端的工具名前缀不同（Claude Code：`mcp__agent-hud__send_message`；Codex：`mcp__agent_hud__send_message`；Antigravity 在 tool 描述里称为 agent-hud 的 send_message）。语义一致：传话、回复、新开会话。
- **发送语义**：默认 enqueue（对方空闲才送达，不打断进行中的一轮）；`delivery: "steer"` 仅在用户明确要求插入进行中的轮次时使用。`reply_to` 带原消息 ID 原路飞回。
- **链与回数**：每条消息属于一条 chain，默认上限 10 pass（设置 → Agents → Agent tools → Passes in a row）。超出会被拒收，需要用户介入。
- **验收信号**：纸飞机在 HUD 上从发信 agent 飞到收信 agent 再飞回 = 一来一回完成。回复通过 `send_message` + `reply_to` 发回，而不是普通文本输出。

## 分工约定（ai-hotspot-creator 项目）

- **Antigravity（Gemini 3.8 Flash · 前端 UI/UX 设计与产品把控）**：
  - 核心职责：NotchMind Swift UI（macOS 灵动岛 HUD 动效、窗口布局与微交互）、Review Board 可视化看板视觉与交互排版、Obsidian 知识库 Markdown 视觉规范（DESIGN.md / vault）、docs 演进决策案。
- **Claude（Fable / GLM-5.3 · 后端程序设计与数据管线）**：
  - 核心职责：Python 核心管线（`src/collectors/` 热点抓取、`src/agent/` 认知提炼、`src/workbench/` 调度器、`src/exporters/` 数据流转与持久化）、真实行为测试覆盖（`uv run pytest`）与真实抓网验收（`uv run python -m src.main run --dry-run`）。
- **协作节奏**：Antigravity 确定前端数据结构与交互需求，通过 Agent HUD 消息指派给 Claude；Claude 在本地项目根目录下完成 Python 后端实现并通过真实测试后，通过 `reply_to` 回执交付。
- **上下文共享**：同一项目文件夹，agent 自己去读代码，消息里只传结论不传整段会话。

## 工程规则（与 AGENTS.md 一致，对所有 agent 生效）

1. 单个代码文件 ≤ 20 KB；超标按功能拆文件，不绕过 pre-commit 钩子。
2. 写新函数前先搜项目里有没有现成的，同一条规则只留一个出处。
3. 测试守真实行为（真写 SQLite、真生成 Markdown），不写假 mock。
4. 密钥与模型名只从 `.env` 读（`GEMINI_API_KEY` / `GEMINI_MODEL`），绝不硬编码。
5. 交差前跑：`uv run pytest` + `uv run python -m src.main run --dry-run`。
6. 子代理极简汇报：主会话严禁大段复制子代理长篇分析与大表格。主 Agent 仅在主对话输出一行极简完成卡片（引导点击子会话抽屉查看详情），详细日志与证据沉淀在子代理视图中。

## 快速上手（新会话的第一条消息模板）

```
[来自 <客户端> · <会话标题>]
阶段完成：<一句话结论>
改动文件：<file1, file2...>
下一步：<谁做什么>
请确认或提出异议（send_message + reply_to）。
```

## 首飞验证（2026-11-20 管线体检结论）

两端接线已确认：Antigravity 的 `~/.gemini/config/mcp_config.json` 已挂 agent-hud（`/Applications/Agent HUD.app --mcp`），消息组工具（send_message / get_message / list_sessions / start_session）已在转发器列出（仅当「Let agents message each other」开启时才会列出）；语言服务器 2.33.0 在线；活跃主会话 `c4eac1f6-289f-4f00-b554-e149837deb85` 工作目录即本项目。

**方向 A（Claude Code → Antigravity）**：在项目目录开一个 `claude` 会话，粘贴：
> 用 agent-hud 的 send_message 发给 antigravity:c4eac1f6-289f-4f00-b554-e149837deb85：「【通道首飞】来自 Claude Code：请阅读 docs/antigravity-handoff.md 与 docs/review-2026-11-20.md，认领 NotchMind 侧 P0-5/6/8，然后用 send_message + reply_to 原路回复确认。」然后把返回的 message id 和 state 告诉我。

**方向 B（Antigravity → Claude Code）**：在 Antigravity 的 ai-hotspot-creator 会话里粘贴：
> 用 agent-hud 的 list_sessions 找一个空闲的 Claude Code 会话，用 send_message 发给它：「【通道首飞】来自 Antigravity：docs/antigravity-handoff.md 已读，分工确认。请用 send_message + reply_to 原路回执。」然后把 message id 和 state 给我看。

**判读**：send_message 返回 `queued` 即入队成功；HUD 上纸飞机起飞；`get_message` 依次变 `taken → started → done`；对方用 `reply_to` 回执后原路飞回 = 双向连通。若返回 `refused` 看原因（对方无空闲会话 / 乘次上限 / 开关未开）。

**首飞实录（2026-11-20 已发生）**：Antigravity 主会话 c4eac1f6 通过 send_message 向 Claude Code 会话 069e0e0f 成功投递两条首飞消息（m-de85b4f4f17e → started，m-c14609abaf57 → queued→started），方向 B（Antigravity → Claude Code）验证通过。实战暴露的边界，后续照做：

- **子代理不能发信**：send_message / start_session 权限收口在主会话，子 agent 调用直接 refused（「你是子 agent，结果请在自己这一轮里交回」）。主会话收子代理结论后，由主会话代发。
- **start_session 的文件夹白名单**：新会话只能开在「该客户端在这台电脑上用过的文件夹」或空（其任务文件夹）。Claude Code 没在 ai-hotspot-creator 目录开过会话时，先在该目录跑一次 claude，之后才能对其 start_session；应急方案是直投现有会话。**注意**：HUD `start_session` 拉起的 Claude 后台会话任务夹在 `~/.agenthud/sessions/claude/<request-id>/`，其 CWD 不在仓库——会话开工前必须自行 `cd /Users/jackma/ai-hotspot-creator`，并读取仓库根的 `CLAUDE.md`（消息处理协议与硬约束都在那里）。
- **消息未必要 reply_to**：接收方处理完消息后必须显式用 `send_message` + `reply_to` 回执，否则发信方的 get_message 永远停在 started，链路无法闭环。这条写进双方守则。

## 已知限制（来自 agent-messages.md）

- Antigravity：语言服务器在跑时 enqueue/steer/interrupt 都可用；服务器不在线时 `reachable: null`，消息排队等它上线。
- Claude Code：通过 Agent HUD 插件收消息，空闲时投递，slash 命令会被拒。
- 空闲的 hook 型客户端（Cursor/TRAE 等）要等用户手动发起一轮才收得到。
- 消息只传文字不传会话：把结论写清楚，对方自己去读代码。
