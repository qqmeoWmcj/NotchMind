#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# setup_agent_hud.sh — 安装并启用 Agent HUD（agent 互发消息通道）
# 项目: https://github.com/jazzenchen/agent-hud-open
#
# 用途：
#   1. 通过 Homebrew cask 安装 Agent HUD（Mac 灵动岛 HUD + 内置 MCP 服务）
#   2. 引导完成「让 agents 彼此对话」的开关配置
#   3. 校验 Antigravity / Claude Code 可被 Agent HUD 发现
#
# 说明：
#   - Agent HUD 的 MCP 服务内置于 App，无需 clone 源码；从源码构建仅用于参与开发。
#   - 支持 macOS 14+。Windows/Linux 走 npx @agenthud/install（预览）。
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=================================================="
echo "🛰️  Agent HUD 安装与 agent 互发消息通道配置"
echo "=================================================="

# ---------- 0. 前置检查 ----------
if [[ "$(uname)" != "Darwin" ]]; then
    echo "❌ 本脚本仅支持 macOS。Windows/Linux 请运行: npx @agenthud/install"
    exit 1
fi

if ! command -v brew >/dev/null 2>&1; then
    echo "❌ 未找到 Homebrew。请先安装: https://brew.sh"
    exit 1
fi

# ---------- 1. 安装（已在 /Applications 里则 --adopt 收编） ----------
if [[ -d "/Applications/Agent HUD.app" ]]; then
    echo "📦 检测到 /Applications/Agent HUD.app，用 --adopt 收编进 Homebrew 管理…"
    brew install --cask --adopt jazzenchen/tap/agent-hud
else
    echo "📦 通过 Homebrew 安装 Agent HUD…"
    brew install --cask jazzenchen/tap/agent-hud
fi

# ---------- 2. 启动 ----------
echo "🚀 启动 Agent HUD…"
open -a "Agent HUD"

# ---------- 3. 发现检查 ----------
echo ""
echo "✅ 安装完成。接下来请在 Agent HUD 里手动完成两步（图形界面操作，脚本无法代劳）："
echo ""
echo "   ① 设置 → Agents（智能体）"
echo "      - 确认 Claude Code 与 Antigravity 出现在列表中并已登录"
echo "      - 在「Agent tools」下打开『Let agents message each other』(让 agents 彼此对话)"
echo ""
echo "   ② 保持各客户端登录并打开过一次（Agent HUD 从各 agent 本地记录自动发现会话）："
echo "      - Claude Code:  需要 Agent HUD 的 Claude Code 插件（设置 → Agents → Claude Code 页安装），"
echo "                    会话空闲时收消息；'Send messages' 开关默认开"
echo "      - Antigravity:  保持其本地 language server 运行（桌面版打开即可），"
echo "                    enqueue 空闲投递 / steer 插入当前轮 / interrupt 取消级联"
echo ""
echo "   ③ 验证互发：在任一 Claude Code 会话里让 Claude 调"
echo "      mcp__agent-hud__list_sessions，应能看到 Antigravity 的会话；"
echo "      再用 send_message 发一条测试消息，纸飞机飞回即通道打通。"
echo ""
echo "📄 协作路标见: docs/antigravity-handoff.md"

# ---------- 4. MCP 对接说明（可选，写给 Claude Code 用户） ----------
if [[ -f "$HOME/.claude/settings.json" ]]; then
    echo ""
    echo "💡 提示：Agent HUD 的 MCP 服务对 Claude Code 是通过其插件自动挂载的，"
    echo "   无需手动编辑 ~/.claude/settings.json。若你之前手动加过 agent-hud 的"
    echo "   stdio 配置且出现问题，删除即可回归插件默认。"
fi
