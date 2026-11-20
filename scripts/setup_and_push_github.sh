#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# setup_and_push_github.sh — 一站式 GitHub 仓库连接与上传脚本
# 支持：
# 1. 直接传入仓库地址: ./scripts/setup_and_push_github.sh <REPO_URL>
# 2. 通过 GitHub CLI (gh) 自动建库并推送
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
cd "$PROJECT_ROOT"

echo "=================================================="
echo "🚀 NotchMind / AI Hotspot Creator — GitHub 一站式发布"
echo "=================================================="

# 1. 守住安全底线：确保 .env 绝不进入版本控制
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
    echo "❌ 严重警告：.env 文件已被暂存或提交！正在紧急移出版本控制..."
    git rm --cached .env
    git commit -m "fix: remove sensitive .env from tracking" || true
fi

# 2. 确保主分支名为 main
CURRENT_BRANCH="$(git branch --show-current 2>/dev/null || echo "main")"
if [ "$CURRENT_BRANCH" != "main" ]; then
    echo "📌 将当前分支重命名为 main..."
    git branch -M main
fi

# 3. 检查是否有未提交的代码
if ! git diff-index --quiet HEAD --; then
    echo "📦 检测到工作区有改动，正在自动打包提交..."
    git add .
    git commit -m "chore: save working changes before push to GitHub" || true
fi

REPO_URL="${1:-}"

# 如果命令行传入了 URL，直接关联并推送
if [ -n "$REPO_URL" ]; then
    echo "🔗 正在关联远程仓库: $REPO_URL"
    if git remote | grep -q "^origin$"; then
        git remote set-url origin "$REPO_URL"
    else
        git remote add origin "$REPO_URL"
    fi

    echo "⬆️ 正在推送到 GitHub main 分支..."
    git push -u origin main
    echo "✅ 推送成功！远程地址已配置为: $REPO_URL"
    exit 0
fi

# 检查当前是否已经存在 origin 远程
EXISTING_ORIGIN="$(git remote get-url origin 2>/dev/null || true)"
if [ -n "$EXISTING_ORIGIN" ]; then
    echo "🔍 检测到已配置远程仓库 origin: $EXISTING_ORIGIN"
    read -r -p "是否直接推送到该仓库？(Y/n): " CONFIRM_PUSH
    CONFIRM_PUSH="${CONFIRM_PUSH:-Y}"
    if [[ "$CONFIRM_PUSH" =~ ^[Yy]$ ]]; then
        echo "⬆️ 正在推送到 origin main..."
        git push -u origin main
        echo "✅ 推送成功！"
        exit 0
    fi
fi

# 未提供 URL 时，尝试通过 gh CLI 自动化建库或登录
GH_BIN="/opt/homebrew/bin/gh"
if [ ! -x "$GH_BIN" ]; then
    GH_BIN="$(which gh 2>/dev/null || true)"
fi

if [ -n "$GH_BIN" ] && [ -x "$GH_BIN" ]; then
    echo "✨ 检测到 GitHub CLI: $($GH_BIN --version | head -n 1)"
    if $GH_BIN auth status >/dev/null 2>&1; then
        echo "👤 已登录 GitHub 账号。"
        DEFAULT_NAME="$(basename "$PROJECT_ROOT")"
        read -r -p "请输入新建 GitHub 仓库名称（默认: $DEFAULT_NAME）: " REPO_NAME
        REPO_NAME="${REPO_NAME:-$DEFAULT_NAME}"

        echo "请选择仓库可见性："
        echo "  1) Public (公开)"
        echo "  2) Private (私有，推荐)"
        read -r -p "请输入选项 [1/2，默认 2]: " VISIBILITY_CHOICE
        VISIBILITY="--private"
        if [ "$VISIBILITY_CHOICE" = "1" ]; then
            VISIBILITY="--public"
        fi

        echo "🚀 正在通过 GitHub CLI 创建远程仓库 $REPO_NAME 并推送..."
        $GH_BIN repo create "$REPO_NAME" $VISIBILITY --source=. --remote=origin --push
        echo "🎉 恭喜！仓库创建并推送完毕！"
        $GH_BIN browse
        exit 0
    else
        echo "💡 您尚未在本地登录 GitHub。"
        echo "您可以通过以下两种方式完成一站式连接："
        echo ""
        echo "方式 1 (推荐)：执行 gh auth login 登录后再次运行本脚本："
        echo "   $GH_BIN auth login"
        echo ""
        echo "方式 2：在 https://github.com/new 手动新建一个空仓库，然后把地址贴给本脚本："
        echo "   ./scripts/setup_and_push_github.sh https://github.com/<你的用户名>/<仓库名>.git"
        echo ""
        read -r -p "请输入您的 GitHub 仓库完整 URL (或按 Enter 退出并在浏览器新建): " INPUT_URL
        if [ -n "$INPUT_URL" ]; then
            exec "$0" "$INPUT_URL"
        fi
    fi
else
    echo "⚠️ 未找到 gh CLI。请在 https://github.com/new 创建空仓库后，执行："
    echo "   ./scripts/setup_and_push_github.sh <你的仓库地址>"
fi
