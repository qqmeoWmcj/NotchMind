#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")"
echo "🚀 开始运行 AI 热点个人创作 Agent..."
"$HOME/.local/bin/uv" run python -m src.main run
echo ""
echo "✅ 运行完成！你可以打开 Obsidian 查看最新生成的笔记与 NotebookLM 源文档。"
read -n 1 -s -r -p "按任意键关闭窗口..."
echo ""
