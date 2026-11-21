# CLAUDE.md — 本仓库的 Claude Code 工作守则

> 任何在此仓库工作的 Claude Code 会话（终端前台、HUD `start_session` 拉起的后台会话、其他 agent 转发进来的任务）都先读本文件。

## 角色定位（2026-11-20 双方确认）

- **Claude（本仓库后端负责方）**：Python 核心管线（collectors / agent / memory / exporters / workbench）、SQLite 持久化、工作台调度、测试与验收（`uv run pytest` + `uv run python -m src.main run --dry-run`）。
- **Antigravity（前端负责方）**：NotchMind Swift UI 灵动岛交互、Review Board 界面视觉、Obsidian 排版规范。
- 共同工单：`docs/review-2026-11-20.md`。

## Agent HUD 消息处理协议

本仓库接入了 [Agent HUD](https://github.com/jazzenchen/agent-hud-open) 的 agent 互发消息通道。收到带 `[Agent HUD · from <client> · <标题> · <id>]` 标签的输入时，按以下流程走：

1. **登记**：把消息 id、发件方、诉求一句话写入 `docs/agent-inbox.md` 台账（`Pending` 状态）。
2. **执行**：按 AGENTS.md 的工程规则干活（单文件 ≤20KB、不绕 pre-commit、密钥只从 .env）。只做消息里明确要求的事，不要扩大范围。
3. **验收**：改动后必须跑 `uv run pytest` 和 `uv run python -m src.main run --dry-run`，结果写进回执。
4. **回执**：用 `send_message` + `reply_to: <收到的消息 id>` 原路回执，格式见下。不回执 = 发信方 get_message 永远停在 started，链路不闭环。
5. **销账**：回执发出后把台账状态改为 `Replied`。

回执格式（一段话，别堆长文）：

```
【回执】(msg <id>) <一句话结果>。改动: <文件列表>。验收: pytest <N passed> / dry-run <通过|失败+原因>。下一步: <谁做什么>。
```

## 硬约束

- 子代理不能调 `send_message` / `start_session`（HUD 会直接 refused）；主会话收结论后代发。
- `start_session` 有文件夹白名单：只能开在该客户端在这台 Mac 用过的文件夹，或空（其任务文件夹）。要让 Claude 后台会话认得本仓库，先在本仓库目录跑过一次 `claude`。
- 消息是一轮一结的：写清楚结论再发一条完整的，不要挤牙膏连发三条。
- 桌面 Cowork 会话（云端沙盒）不在本协议内：它够不到 HUD socket，它的产出由本会话写入仓库文件，再由本地会话消费。
