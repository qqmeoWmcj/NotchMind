#!/usr/bin/env bash
set -euo pipefail

# ==============================================================================
# sync.sh — 一句话极速上传与更新 GitHub 仓库
# 用法:
#   ./sync.sh                     # 自动分析变更并一键提交推送
#   ./sync.sh "feat: 你的更新描述"  # 自定义提交说明并一键推送
# ==============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$SCRIPT_DIR"

echo "⚡️ 正在准备一键同步仓库..."

# 1. 守住安全底线：绝不提交 .env
if git ls-files --error-unmatch .env >/dev/null 2>&1; then
    echo "❌ 警告：.env 被 Git 追踪，正在移出..."
    git rm --cached .env
    git commit -m "fix: remove .env from tracking" || true
fi

# 2. 检查是否有未提交的代码
if ! git diff-index --quiet HEAD -- || [ -n "$(git status --porcelain)" ]; then
    git add .
    COMMIT_MSG="${1:-}"
    if [ -z "$COMMIT_MSG" ]; then
        CHANGED_COUNT=$(git diff --cached --name-only | wc -l | tr -d ' ')
        COMMIT_MSG="chore: update workspace files (${CHANGED_COUNT} files modified, $(date +'%Y-%m-%d %H:%M'))"
    fi
    echo "📝 提交改动: $COMMIT_MSG"
    git commit -m "$COMMIT_MSG"
else
    echo "✓ 工作区无新改动，检查远端推送状态..."
fi

# 3. 检查远程仓库配置
CURRENT_REMOTE="$(git remote get-url origin 2>/dev/null || true)"
if [ -z "$CURRENT_REMOTE" ]; then
    echo ""
    echo "⚠️ 尚未绑定 GitHub 远程仓库！"
    echo "请提供您的 GitHub 仓库地址（例如 https://github.com/用户名/仓库名.git 或 git@github.com:用户名/仓库名.git）："
    read -r -p "仓库 URL: " INPUT_URL
    if [ -n "$INPUT_URL" ]; then
        git remote add origin "$INPUT_URL"
        CURRENT_REMOTE="$INPUT_URL"
        echo "🔗 已绑定远程仓库: $CURRENT_REMOTE"
    else
        echo "❌ 未提供仓库地址，无法推送。请重新运行并在提示时输入。"
        exit 1
    fi
fi

# 4. 推送到 main 分支
git branch -M main
echo "⬆️ 正在推送到 GitHub ($CURRENT_REMOTE)..."
if git push -u origin main; then
    echo "🎉 仓库更新成功！"
else
    echo "❌ 推送遇到问题。若是权限原因，请确认 SSH 密钥已添加到 GitHub 或使用 HTTPS 访问令牌。"
    exit 1
fi
