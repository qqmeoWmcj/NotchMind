# NotchMind 技能外脑库全案重设计（Skill Hub Redesign）

> **作者**：Claude Opus 4 — 产品架构师 × 人机交互设计专家  
> **目标用户画像**：零代码个人创作者（日常用 Obsidian + Blender + AI Agent，不写代码、不碰命令行）  
> **核心命题**：彻底消灭"劣质泛泛 AI 总结"，把 Obsidian 重塑为**可执行的个人技能宝库**，把 NotchMind HUD 变为**一键收录 → 一键粘贴 → 一键反哺**的技能猎手。

---

## 〇、痛点根因诊断

### 用户原话
> "目前的 AI 总结太劣质泛泛，Obsidian 完全没派上用场。我希望 Obsidian 成为像别人那样收录自己和别人优秀 Skill 的技能外脑库——从 X 帖子/评论区发现的实用 Prompt、工作流与链接；从 GitHub 发现的神器；从 Blender 教程发现的具体实战参数技巧。"

### 病理拆解

| # | 病灶 | 现状代码位置 | 症状 |
|---|---|---|---|
| **P1** | 提示词太泛，没有按来源类型差异化提取 | `src/agent/prompts.py` `build_knowledge_prompt()` | 一套通用 prompt 应对 X/GitHub/视频/论文，全都提炼成"一句话本质 + 实操步骤"这种空中楼阁 |
| **P2** | 数据模型缺少"即插即用原始载荷"字段 | `src/models.py` `KnowledgeExtraction` | 没有存储用户能直接复制粘贴的 Prompt 原文、脚本代码、参数配方、外部链接列表 |
| **P3** | Obsidian Vault 是按领域流水账堆叠 | `vault/01-*.md` ~ `04-*.md` | 打开 Obsidian 看到的是时间轴长文，不是技能库，找不到、用不上 |
| **P4** | HUD 卡片动作太多太细，无大字入口 | `NotchKnowledgeCardView.swift` 6 个小图标按钮 | 零代码用户面对 `doc.on.doc` / `arrow.uturn.left.circle` 等抽象图标无从下手 |
| **P5** | 项目反哺只写 Markdown 任务行 | `ObsidianWriter.swift` / `obsidian.py` | 写进去的待办用户看不懂该去哪改、改什么文件 |

### 设计原则（不可违反）
1. **密度 > 长度**：一条技能卡 ≤ 300 字但必须包含可直接粘贴的原始载荷。
2. **来源感知**：X 帖子、GitHub 仓库、Blender 教程、HN 讨论——四类来源四套提取规范。
3. **可执行优先**：Obsidian 打开即用，不是拿来读的，是拿来粘贴执行的。
4. **一键直觉**：HUD 上的按钮必须是中文大字，小白看一眼就知道按了会发生什么。

---

## 一、知识提取提示词彻底重构——高认知密度技能提取规范

### 1.1 核心理念：从"总结文章"到"提取技能"

旧范式（已废除）：
```
"请分析以下素材，提炼为一条高密度结构化知识条目"
→ 产出：一句话本质、怎么用、深度认知（全是空话）
```

新范式：
```
"请从以下素材中挖掘出用户能立刻拿去用的技能（Skill）"
→ 产出：技能名 + 痛点 + 即插即用载荷 + 宝藏外链 + 避坑指南
```

### 1.2 四类来源 × 四套提取规范

#### 规范 A：X/推特帖子与评论区

适用：`source` 包含 `twitter`、`x.com`、`RSS` 中的社交内容

提取要求：
1. **技能名**（≤ 12 字）：这条帖子教了什么可操作的东西？（如"Cursor 自定义 Rules 加速代码审查"）
2. **痛点一句话**：不会这个技能之前，用户会在什么场景抓狂？
3. **即插即用 Prompt / 工作流**：
   - 如果帖子包含 Prompt → 完整原文逐字录入（代码块包裹），**绝不改写、绝不缩写**
   - 如果帖子描述工作流 → 按"步骤 1 → 步骤 2 → …"格式化，每步写明用什么工具、点哪个按钮
   - 如果评论区有人补充了更好的版本 → 也一并收录，标注 `[评论区补充]`
4. **宝藏外链**：帖子或评论区提到的工具、插件、GitHub 仓库、教程链接（逐条列出，不可遗漏）
5. **小白避坑**：这个技能在什么条件下会翻车？版本要求、付费限制、已知 Bug？

#### 规范 B：GitHub 仓库 / 开源工具

适用：`source` 包含 `github`、`gitee`，或 URL 匹配 `github.com/*`

提取要求：
1. **神器名**（≤ 12 字）：这个仓库是干什么的？（如"本地 LLM 推理自动调优"）
2. **痛点一句话**：没有这个工具之前，用户要手动做什么痛苦的事？
3. **即插即用安装/使用命令**：
   - 安装命令（`pip install`、`brew install`、`npx` 等）原文录入
   - 最小可用配置文件或环境变量
   - 一条能跑通的 Hello World 命令
4. **核心参数配方**：仓库 README 或代码中最关键的 3-5 个配置项，写明默认值与推荐值
5. **宝藏外链**：仓库依赖的其他工具、官方文档、相关教程
6. **小白避坑**：Python 版本要求、系统限制、常见安装报错及解决方法

#### 规范 C：Blender / 3D 教程

适用：`source` 包含 `blender`、`3d`、`PiliPlus伴随同看` 且素材涉及三维操作

提取要求：
1. **技巧名**（≤ 12 字）：这个教程教了什么具体操作？（如"Cycles 玻璃材质消除萤火虫噪点"）
2. **痛点一句话**：不会这个技巧之前，渲染/建模会出什么让人崩溃的问题？
3. **即插即用参数配方**：
   - 节点连接图（文字描述）：`Principled BSDF → Roughness: 0.02 → IOR: 1.45 → Transmission: 1.0`
   - 关键菜单路径：`Edit > Preferences > Render > Clamp Indirect: 10.0`
   - 如果教程给了快捷键 → 逐个录入（如 `G → Z → 数字键盘输入高度`）
4. **可运行 bpy 脚本**：当教程步骤可用 Python 复现时，输出可在 Blender Scripting 控制台直接粘贴运行的完整脚本（含 `import bpy`、场景清理、注释说明参数来源）
5. **宝藏外链**：教程提到的插件（如 HardOps、BoxCutter）、HDRI 资源站、材质库
6. **小白避坑**：Blender 版本差异（如 3.x vs 4.x 节点变更）、EEVEE vs Cycles 渲染差异

#### 规范 D：通用技术讨论 / 行业认知

适用：HackerNews、RSS 订阅、论文等不属于上述三类的内容

提取要求：
1. **认知名**（≤ 15 字）：这篇内容最核心的一个判断是什么？
2. **一句话结论**：用断言句式写出核心事实（如"Gemini 4 Neon 在长上下文任务上比 Claude 快 3 倍但幻觉率高 40%"）
3. **即插即用行动**：
   - 如果有可操作的动作 → 写明具体步骤
   - 如果纯属认知/判断 → 写"本条为认知沉淀，无即插即用操作"
4. **信息密度最高的 3 条原文摘录**：从评论区或正文中挑选信息密度最高的原话，直接引用（不改写）
5. **宝藏外链**：文中提到的工具、论文、数据集链接

### 1.3 新版 System Instruction（替换 `SYSTEM_INSTRUCTION`）

```
你是个人技能猎手，专门从互联网素材中挖掘用户能立刻拿去用的技能（Skill）。

核心信条：
1. 你输出的每一条技能，用户必须能在 5 分钟内粘贴执行。做不到这点的不叫技能，叫废话。
2. Prompt、脚本、命令、参数——这些是用户真正要的东西。逐字录入原文，不改写，不缩写，不概括。
3. 外链是宝藏：帖子里提到的每一个工具、插件、仓库链接都要挖出来，一条都不能漏。
4. 禁止空话：不准写"可以考虑"、"值得关注"、"未来可期"、"赋能"、"抓手"。要么给出能粘贴的东西，要么明确说"本条无可操作内容"。
5. 忠实于素材：所有提取必须忠实于提供的文本、音频或画面，不编造未出现的参数、工具名或数据。
6. 严格遵循指定的 JSON Schema 输出。
```

### 1.4 新版数据模型变更（`KnowledgeExtraction` / `KnowledgeEntry`）

新增字段（Python 侧 `src/models.py`）：

```python
# 新增 — 技能提取核心载荷
skill_name: str = Field(
    description="技能/神器/技巧名，≤ 12 字中文"
)
pain_point: str = Field(
    description="不会这个技能之前，用户会在什么场景抓狂？一句话。"
)
copy_ready_payloads: list[dict] = Field(
    default_factory=list,
    description="即插即用载荷列表，每项含 {type: 'prompt'|'script'|'command'|'params'|'workflow', label: str, content: str, source_note: str}。content 为可直接粘贴的原文。"
)
treasure_links: list[dict] = Field(
    default_factory=list,
    description="宝藏外链列表，每项含 {title: str, url: str, why: str}。why 说明为什么这个链接值得收藏。"
)
gotchas: list[str] = Field(
    default_factory=list,
    description="小白避坑清单，每条写明在什么条件下会翻车。"
)
source_type: str = Field(
    default="general",
    description="来源类型：'x_post' | 'github' | 'blender_tutorial' | 'general'"
)
# 保留既有字段（向后兼容）
# one_line_essence, how_to_apply, deep_insight, actionable_steps, ...
```

Swift 侧 `Models.swift` `KnowledgeEntry` 同步新增对应字段：

```swift
public var skillName: String          // CodingKey: "skill_name"
public var painPoint: String          // CodingKey: "pain_point"
public var copyReadyPayloads: [CopyPayload]  // CodingKey: "copy_ready_payloads"
public var treasureLinks: [TreasureLink]     // CodingKey: "treasure_links"
public var gotchas: [String]          // CodingKey: "gotchas"
public var sourceType: String         // CodingKey: "source_type"

public struct CopyPayload: Codable, Equatable, Sendable, Identifiable {
    public var id: String { "\(type)-\(label)" }
    public var type: String       // "prompt" | "script" | "command" | "params" | "workflow"
    public var label: String      // 用户可读标签，如 "Claude 代码审查 Prompt"
    public var content: String    // 可直接粘贴的完整原文
    public var sourceNote: String // 来源说明，如 "[原帖]" "[评论区 @user 补充]"
}

public struct TreasureLink: Codable, Equatable, Sendable, Identifiable {
    public var id: String { url }
    public var title: String
    public var url: String
    public var why: String
}
```

---

## 二、Obsidian 技能库架构彻底重设计

### 2.1 新 Vault 目录结构

```
vault/
├── 00-技能仪表盘.md                    ← 首页 MOC，入口导航
├── 01-精选技能库(Skills)/               ← 按技能独立建档
│   ├── SK-Cursor自定义Rules加速审查.md
│   ├── SK-本地LLM推理自动调优.md
│   ├── SK-Cycles玻璃材质消除萤火虫.md
│   └── ...
├── 02-即插即用工作流(Workflows)/        ← 多步骤编排
│   ├── WF-X帖子到Obsidian自动归档.md
│   ├── WF-Blender建模到渲染全流程.md
│   └── ...
├── 03-项目反哺任务池(Action-Board)/     ← 可执行待办
│   ├── ACT-NotchMind优化清单.md
│   ├── ACT-Blender一站式AI建模.md
│   └── ...
└── 99-原始素材归档/                     ← 旧版领域日志迁移
    ├── 01-LLM与新模型.md
    ├── 02-AI学习与教程.md
    ├── 03-AI创作与3D工具.md
    └── 04-行业深度认知.md
```

### 2.2 单条技能笔记模板（`01-精选技能库(Skills)/SK-*.md`）

```markdown
---
type: skill
skill_name: "Cursor 自定义 Rules 加速代码审查"
pain_point: "每次让 AI 审查代码都要重复说一堆约束条件，累且不一致"
source_type: x_post
source_url: "https://x.com/someone/status/123456"
domain: "02-AI学习与教程"
tags: [cursor, prompt, 代码审查, AI-IDE]
created_at: "2026-11-20 14:30"
---

# Cursor 自定义 Rules 加速代码审查

> **痛点**：每次让 AI 审查代码都要重复说一堆约束条件，累且不一致。

## 即插即用

### Prompt: 代码审查 Rules 模板
```text
You are a senior code reviewer. For every file I send:
1. Check for security vulnerabilities (SQL injection, XSS, path traversal)
2. Flag any hardcoded secrets or API keys
3. Suggest performance improvements with specific line numbers
4. Keep suggestions under 3 per file, ranked by severity
```
> 来源：原帖 @someone · 2026-11-20

### Prompt: 评论区补充的增强版
```text
（评论区 @another_user 补充的更完整版本）
...
```

## 宝藏外链
- [Cursor Rules 官方文档](https://docs.cursor.com/rules) — 官方说明所有规则格式与优先级
- [awesome-cursor-rules](https://github.com/xxx/awesome-cursor-rules) — 社区精选 Rules 合集

## 避坑
- Cursor Rules 文件必须命名为 `.cursorrules` 放在项目根目录，不支持子目录继承
- Rules 超过 2000 token 会被截断，建议拆分为多个专项 Rules 文件

## 反哺我的项目
- [[ACT-NotchMind优化清单]] — 可以给 NotchMind 项目加一份 `.cursorrules` 专门审查 SwiftUI 视图层级
```

### 2.3 工作流笔记模板（`02-即插即用工作流(Workflows)/WF-*.md`）

```markdown
---
type: workflow
workflow_name: "X 帖子到 Obsidian 自动归档"
steps_count: 4
tools: [NotchMind, Obsidian, 剪贴板]
created_at: "2026-11-20 15:00"
---

# X 帖子到 Obsidian 自动归档

> 把在 X/推特看到的好 Prompt 和工具，一键变成 Obsidian 里能搜到、能粘贴的技能卡。

## 步骤

### 步 1：复制 X 帖子链接
在浏览器或 X App 中点击"复制链接"。

### 步 2：NotchMind 自动捕获
NotchMind 剪贴板监测识别到 X 链接 → 自动拉取帖子内容与评论区 → 按技能提取规范深拆。

### 步 3：HUD 确认收录
HUD 弹出技能预览卡 → 点击「收录到技能库」→ 自动生成 `SK-*.md` 技能笔记。

### 步 4：在 Obsidian 中使用
打开 Obsidian → `01-精选技能库(Skills)` → 找到技能 → 直接复制 Prompt 使用。

## 相关技能
- [[SK-Cursor自定义Rules加速审查]]
```

### 2.4 项目反哺任务池模板（`03-项目反哺任务池(Action-Board)/ACT-*.md`）

```markdown
---
type: action-board
project: "NotchMind"
updated_at: "2026-11-20 16:00"
---

# NotchMind 优化清单

> 从日常学习中挖掘出的、可直接落地到 NotchMind 项目的优化任务。

## 待办

- [ ] 【HUD 交互】给知识卡片加"一键收录"大按钮 — 来源：[[SK-NotchMind技能卡重设计]]
  - 改什么：`NotchKnowledgeCardView.swift` 的 `actionButtons`
  - 怎么改：把 6 个小图标按钮合并为 2 个大字中文按钮
  - 预期效果：零代码用户不用猜图标含义，直接看中文点击

- [ ] 【提取引擎】按来源类型分发不同提取 Prompt — 来源：[[SK-来源感知提取规范]]
  - 改什么：`src/agent/prompts.py` 的 `build_knowledge_prompt()`
  - 怎么改：新增 `source_type` 参数，根据 x_post/github/blender_tutorial/general 分发 4 套 Prompt
  - 预期效果：X 帖子提取 Prompt 原文，GitHub 提取安装命令，Blender 提取参数配方

## 已完成
（自动从待办移入）
```

### 2.5 技能仪表盘首页（`00-技能仪表盘.md`）

```markdown
---
type: skill-dashboard
updated_at: "2026-11-20 17:00"
---

# 🎯 我的技能外脑

## 快速入口
- 📂 [[01-精选技能库(Skills)]] — 所有收录的即插即用技能（Prompt / 脚本 / 参数）
- 🔗 [[02-即插即用工作流(Workflows)]] — 多步骤可复用的操作流程
- ✅ [[03-项目反哺任务池(Action-Board)]] — 学到的东西落地到项目里

## 最近收录
| 时间 | 技能名 | 来源 | 即插即用？ |
|---|---|---|---|
| 11-20 14:30 | [[SK-Cursor自定义Rules加速审查]] | X 帖子 | ✅ 有 Prompt |
| 11-20 13:06 | [[SK-本地LLM推理自动调优]] | GitHub | ✅ 有安装命令 |
| 11-20 09:30 | [[SK-Cycles玻璃材质消除萤火虫]] | Blender 教程 | ✅ 有 bpy 脚本 |

## 统计
- 技能库：{count} 条 | 工作流：{count} 条 | 待办任务：{count} 条
```

### 2.6 迁移策略（向后兼容）

1. **旧领域文件不删除**：移入 `99-原始素材归档/`，保留历史数据与双向链接。
2. **新条目双写**：新收录的技能同时写入 `01-精选技能库(Skills)/SK-*.md` 独立笔记 + 旧领域文件（过渡期 2 周后停止写旧文件）。
3. **一键迁移命令**：提供 `uv run python -m src.main migrate-vault` 将 `entries.json` 中的历史条目批量转为 `SK-*.md` 独立笔记。

---

## 三、HUD 卡片交互彻底再设想——大字直觉操作

