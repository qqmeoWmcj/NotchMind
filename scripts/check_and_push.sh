#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR/.."

echo "🔍 检查 GitHub 连通性..."
if ssh -T -o ConnectTimeout=4 -o StrictHostKeyChecking=accept-new git@github.com 2>&1 | grep -q "You've successfully authenticated"; then
    echo "✅ SSH 认证成功！"
    echo "⬆️ 正在推送到 git@github.com:qqmeoWmcj/ai-hotspot-creator.git..."
    git push -u origin main
    echo "🎉 恭喜！代码已成功上传到 GitHub！"
    exit 0
fi

echo "⚠️ SSH 认证尚未通过。请确认是否已将公钥添加到 GitHub Settings -> SSH Keys。"
exit 1
