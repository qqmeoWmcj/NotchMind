# GitHub 仓库连接与一键上传指南

本项目已经为您配置好了自动化建库与发布工具，遵循安全原则（`.env` 密钥绝不外泄、单文件限制严格把关）。

---

## 方式 1：使用 GitHub CLI（最省心、全自动）

本机已预先安装 **GitHub CLI (`gh`)**。只需两步即可完成建库与推送：

### 第一步：在终端完成一次性登录授权
打开终端运行：
```bash
gh auth login
```
- 选择 `GitHub.com`
- 选择 `HTTPS`
- 选择 `Y` 进行浏览器授权（Web browser 登录），终端会给出一次性激活码，并在浏览器中一键确认即可。

### 第二步：运行一站式建库推送脚本
```bash
./scripts/setup_and_push_github.sh
```
脚本会自动读取当前项目、询问仓库名与是否公开/私有，并在 GitHub 上直接建好仓库并把当前所有代码完整推送到 `main` 分支。

---

## 方式 2：手动关联现有/新创建的远程仓库

如果您已经在 GitHub 网页端（[https://github.com/new](https://github.com/new)）新建了一个空仓库（**注意不要勾选** "Add a README file" 或 ".gitignore"，直接建空仓库）：

直接在项目根目录运行一行命令即可完成绑定与推送：
```bash
./scripts/setup_and_push_github.sh https://github.com/<你的GitHub用户名>/<你的仓库名>.git
```
或者手动执行标准 Git 命令：
```bash
# 1. 关联远程仓库
git remote add origin https://github.com/<你的GitHub用户名>/<你的仓库名>.git

# 2. 确认主分支为 main 并推送
git branch -M main
git push -u origin main
```

---

## 方式 3：SSH 方式免密连接

如果您更偏好 SSH 方式推送：
```bash
# 1. 生成 ED25519 密钥（若已有可跳过）
ssh-keygen -t ed25519 -C "jackma6666@gmail.com"

# 2. 拷贝公钥并在 GitHub Settings -> SSH Keys 中添加
pbcopy < ~/.ssh/id_ed25519.pub

# 3. 推送
./scripts/setup_and_push_github.sh git@github.com:<你的GitHub用户名>/<你的仓库名>.git
```

---

## 安全守则与验证保证
- `.env`（包含 API Key）已加入 `.gitignore` 且经自动化安全校验，绝对不会被上传到 GitHub。
- 单文件全部经过 `pre-commit` 严格限制在 20 KB 以内。
- 本地 11 项 Swift 单元测试与 13 项 Python 行为测试全部 100% 跑通。
