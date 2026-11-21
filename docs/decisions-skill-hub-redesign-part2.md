# NotchMind 技能外脑库全案重设计（Part 2：HUD 交互与反哺执行）

> 接续 Part 1：参见 [decisions-skill-hub-redesign-part1.md](decisions-skill-hub-redesign-part1.md)

---

### 3.1 设计原则

**核心洞察**：零代码用户不认识 SF Symbol 图标。`doc.on.doc` 是什么？`arrow.uturn.left.circle` 是什么？他们不知道，也不愿意试。

**解法**：所有高频动作用中文大字按钮，低频动作藏进右键菜单。

### 3.2 新卡片布局

```
┌────────────────────────────────────────────────────┐
│ Cursor 自定义 Rules 加速代码审查           3 分钟前  │  ← 技能名（12pt medium）
│ 每次让AI审查代码都要重复说约束条件，累且不一致      │  ← 痛点（11pt regular, secondary）
│                                                    │
│ ┌──────────────────┐ ┌──────────────┐              │
│ │  ★ 收录到技能库  │ │ 拷贝 Prompt  │              │  ← 大字按钮区（悬停可见）
│ └──────────────────┘ └──────────────┘              │
└────────────────────────────────────────────────────┘
```

**展开态追加**：
```
│ ─────────────────────────────────────────────────── │
│ 即插即用 Prompt                                     │
│ ┌────────────────────────────────────────────────┐  │
│ │ You are a senior code reviewer. For every...   │  │  ← 代码块，可整块复制
│ │ 1. Check for security vulnerabilities...       │  │
│ └────────────────────────────────────────────────┘  │
│                                    [ 拷贝此段 ✓ ]   │  ← 点击拷贝到剪贴板
│                                                    │
│ 宝藏外链                                           │
│ • Cursor Rules 官方文档 → docs.cursor.com/rules    │  ← 可点击打开
│ • awesome-cursor-rules → github.com/xxx/...        │
│                                                    │
│ 避坑                                               │
│ ⚠ Rules 文件必须命名为 .cursorrules 放在项目根目录  │
│                                                    │
│ ┌──────────────────────────┐                       │
│ │  ➡ 应用到我的项目        │                       │  ← 反哺按钮
│ └──────────────────────────┘                       │
```

### 3.3 按钮体系重新分层

| 层级 | 触发方式 | 包含动作 | 设计理由 |
|---|---|---|---|
| **L0 核心动作** | 卡片悬停可见的大字按钮 | ★ 收录到技能库、拷贝 Prompt/脚本 | 用户 90% 的操作就这两个 |
| **L1 展开动作** | 点击卡片展开后可见 | 拷贝此段（每个载荷块旁）、应用到我的项目 | 需要先看内容再决定 |
| **L2 高级动作** | 右键菜单 | 在 Obsidian 打开、重新深拆、删除 | 低频但必要 |

### 3.4 大字按钮的动态文案

按钮文案根据 `source_type` 和载荷类型动态变化：

| `source_type` | 有 Prompt 载荷 | 有脚本载荷 | 有命令载荷 | 兜底 |
|---|---|---|---|---|
| `x_post` | 拷贝 Prompt | 拷贝脚本 | 拷贝命令 | 拷贝精华 |
| `github` | — | 拷贝安装命令 | 拷贝命令 | 拷贝精华 |
| `blender_tutorial` | — | 拷贝 bpy 脚本 | — | 拷贝参数 |
| `general` | — | — | — | 拷贝精华 |

### 3.5 SwiftUI 大字按钮实现参考

```swift
// 核心大字按钮组件
struct SkillActionButton: View {
    let title: String          // 如 "拷贝 Prompt"
    let symbol: String         // SF Symbol 名
    let isHighlighted: Bool    // 是否为主按钮（★ 收录到技能库）
    let action: () -> Void

    @Environment(\.notchPalette) private var palette

    var body: some View {
        Button(action: action) {
            HStack(spacing: 5) {
                if isHighlighted {
                    Image(systemName: symbol)
                        .font(.system(size: 11, weight: .medium))
                }
                Text(title)
                    .font(.system(size: 12, weight: .medium))
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 6)
            .background(
                RoundedRectangle(cornerRadius: 6, style: .continuous)
                    .fill(isHighlighted ? palette.primary.opacity(0.15) : palette.fill)
            )
            .foregroundStyle(isHighlighted ? palette.primary : palette.secondary)
        }
        .buttonStyle(NotchPressStyle(scale: 0.96))
    }
}
```

### 3.6 "收录到技能库"的完整交互流

```
用户悬停卡片
  → 大字按钮区淡入（NotchSpring.micro）
  → 用户点击「★ 收录到技能库」
  → 按钮文案变为「✓ 已收录」（.symbolEffect(.bounce)）
  → 后台自动：
    1. 在 vault/01-精选技能库(Skills)/ 生成 SK-{skill_name}.md
    2. 将 copy_ready_payloads 写入技能笔记的"即插即用"区
    3. 将 treasure_links 写入"宝藏外链"区
    4. 将 gotchas 写入"避坑"区
    5. 如果 matched_project 非空 → 自动在对应 ACT-*.md 追加待办
    6. 更新 00-技能仪表盘.md 的"最近收录"表格
  → 1.5s 后按钮恢复原态
```

### 3.7 "拷贝 Prompt/脚本"的交互流

```
用户悬停卡片
  → 大字按钮「拷贝 Prompt」可见
  → 用户点击
  → 系统从 copy_ready_payloads 中找到第一个 type="prompt" 的载荷
  → 将 content 完整写入系统剪贴板（NSPasteboard）
  → 按钮文案变为「✓ 已拷贝」（bounce 动效）
  → Toast 提示："已拷贝到剪贴板 — 直接粘贴到 Cursor / ChatGPT 使用"（3s 自动消失）
```

如果有多个载荷（如原帖 Prompt + 评论区增强版）：
```
  → 点击按钮弹出 mini 选择面板（内联，非弹窗）：
    ┌──────────────────────────┐
    │ 原帖 Prompt              │  ← 点击拷贝
    │ 评论区增强版 Prompt        │  ← 点击拷贝
    │ 安装命令                  │  ← 点击拷贝
    └──────────────────────────┘
```

### 3.8 "应用到我的项目"的交互流

```
用户展开卡片 → 滚到底部
  → 看到「➡ 应用到我的项目」按钮
  → 点击
  → 如果 matched_project 已匹配：
    → 直接在 ACT-{project}.md 追加带文件路径和改法的待办条目
    → 按钮变为「✓ 已添加到 {project} 任务池」
  → 如果 matched_project 为空：
    → 展示项目选择列表（从 03-项目反哺任务池/ 读取现有项目）
    → 用户选择后追加
```

---

## 四、`build_knowledge_prompt()` 完整重写参考

```python
def build_knowledge_prompt(
    *,
    source: str,
    source_type: str,  # "x_post" | "github" | "blender_tutorial" | "general"
    title: str = "",
    url: str = "",
    text: str = "",
    project_names: list[str] | None = None,
    has_media: bool = False,
) -> str:
    # 来源类型感知的提取指令
    type_instructions = {
        "x_post": X_POST_EXTRACTION_SPEC,
        "github": GITHUB_EXTRACTION_SPEC,
        "blender_tutorial": BLENDER_EXTRACTION_SPEC,
        "general": GENERAL_EXTRACTION_SPEC,
    }
    spec = type_instructions.get(source_type, GENERAL_EXTRACTION_SPEC)

    projects_hint = _build_projects_hint(project_names)
    media_hint = (
        "\n注意：随附了音频或画面截图，请优先结合听到的关键步骤与看到的界面参数进行提炼。"
        if has_media else ""
    )
    body = text.strip()[:12000] if text else "（无补充正文）"

    return (
        f"请从以下素材中挖掘出用户能立刻拿去用的技能（Skill）。\n\n"
        f"- 来源：{source}\n"
        f"- 来源类型：{source_type}\n"
        f"- 原始标题：{title or '未提供'}\n"
        f"- 链接：{url or '无'}\n"
        f"- 正文/摘要：\n{body}\n"
        f"{media_hint}\n\n"
        f"### 本来源类型的提取规范\n{spec}\n\n"
        f"### 通用要求\n"
        f"1. skill_name：≤ 12 字中文技能名。\n"
        f"2. pain_point：不会这个技能之前用户会在什么场景抓狂？一句话。\n"
        f"3. copy_ready_payloads：即插即用载荷列表，每项含 type/label/content/source_note。"
        f"content 必须是用户可以直接粘贴执行的完整原文（Prompt/脚本/命令/参数），"
        f"绝不改写、绝不缩写。素材中没有可提取的即插即用内容时返回空数组。\n"
        f"4. treasure_links：宝藏外链列表，每项含 title/url/why。"
        f"素材中提到的每一个工具、插件、仓库、文档链接都要挖出来。\n"
        f"5. gotchas：小白避坑清单，写明在什么条件下会翻车。\n"
        f"6. {projects_hint}\n"
    )
```

---

## 五、来源类型自动识别逻辑

新增 `detect_source_type()` 函数（建议放入 `src/models.py`）：

```python
def detect_source_type(source: str, url: str, text: str = "") -> str:
    """根据来源字符串和 URL 自动判定来源类型。"""
    source_lower = source.lower()
    url_lower = url.lower()
    combined = f"{source_lower} {url_lower} {text[:500].lower()}"

    # X / 推特
    if any(k in url_lower for k in ("x.com/", "twitter.com/")):
        return "x_post"
    if any(k in source_lower for k in ("twitter", "x.com", "推特")):
        return "x_post"

    # GitHub
    if "github.com/" in url_lower or "gitee.com/" in url_lower:
        return "github"
    if "github" in source_lower:
        return "github"

    # Blender / 3D 教程
    blender_keywords = ["blender", "bpy", "建模", "材质", "几何节点", "geometry node",
                        "eevee", "cycles", "渲染", "雕刻", "拓扑"]
    if any(k in combined for k in blender_keywords):
        return "blender_tutorial"

    return "general"
```

---

## 六、端到端流程图

```
┌─────────────────────────────────────────────────────────┐
│                      输入来源                           │
│  X 帖子链接 │ GitHub 仓库 │ PiliPlus 伴学 │ RSS/HN     │
└───────┬──────────┬───────────┬──────────┬───────────────┘
        │          │           │          │
        ▼          ▼           ▼          ▼
┌─────────────────────────────────────────────────────────┐
│          detect_source_type()  来源类型识别              │
│    → x_post / github / blender_tutorial / general       │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│          build_knowledge_prompt()  分发对应提取规范      │
│    → 规范 A / B / C / D                                 │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌─────────────────────────────────────────────────────────┐
│          Gemini API → KnowledgeExtraction               │
│    结果含：skill_name, pain_point,                      │
│    copy_ready_payloads, treasure_links, gotchas          │
└──────────────────────┬──────────────────────────────────┘
                       │
                       ▼
┌──────────────────────┴──────────────────────────────────┐
│                   HUD 卡片呈现                           │
│  标题 = skill_name │ 副标题 = pain_point                │
│  大字按钮：★ 收录到技能库 │ 拷贝 {最佳载荷类型}         │
└──────┬───────────────────┬──────────────────────────────┘
       │                   │
  用户点击              用户点击
「收录到技能库」       「拷贝 Prompt」
       │                   │
       ▼                   ▼
┌──────────────┐    ┌──────────────┐
│ 生成 SK-*.md │    │ 写入剪贴板   │
│ 更新仪表盘   │    │ Toast 确认   │
│ 追加 ACT 待办│    └──────────────┘
└──────────────┘
```

---

## 七、落地优先级与实施路径

### P0：必须立刻改（本轮迭代）

| 任务 | 改动文件 | 预估复杂度 |
|---|---|---|
| 新增 `source_type` 自动识别 | `src/models.py` | 低 |
| 新增 `detect_source_type()` | `src/models.py` | 低 |
| 重写 `SYSTEM_INSTRUCTION` | `src/agent/prompts.py` | 中 |
| 重写 `build_knowledge_prompt()` 支持 4 套规范 | `src/agent/prompts.py` | 中 |
| `KnowledgeExtraction` 新增 5 个字段 | `src/models.py` | 低 |
| `KnowledgeEntry` Python 侧同步新增字段 | `src/models.py` | 低 |
| `KnowledgeEntry` Swift 侧新增 `CopyPayload` / `TreasureLink` | `Models.swift` | 中 |
| HUD 卡片大字按钮替换图标按钮 | `NotchKnowledgeCardView.swift` | 高 |

### P1：Obsidian Vault 重构（下一轮迭代）

| 任务 | 改动文件 |
|---|---|
| 新增 `01-精选技能库(Skills)/` 目录与 SK 模板 | `src/exporters/obsidian.py` |
| 新增 `02-即插即用工作流(Workflows)/` 目录 | `src/exporters/obsidian.py` |
| 重构 `03-项目反哺任务池(Action-Board)/` | `src/exporters/obsidian.py` |
| 技能仪表盘首页生成 | `src/exporters/obsidian.py` |
| 旧文件迁移到 `99-原始素材归档/` | `src/main.py` 新增 `migrate-vault` 命令 |

### P2：增强体验（后续迭代）

| 任务 | 说明 |
|---|---|
| 多载荷选择面板 | 卡片内联展示多个可拷贝载荷 |
| 技能搜索 | HUD CommandBar 支持按技能名/标签搜索 |
| 技能去重 | 同一个 Prompt 被多条帖子提到时合并 |
| NotebookLM 源文档适配 | 技能库格式导出为 NotebookLM 友好的长文档 |

---

## 八、验收标准

1. **提取质量**：随机抽取 10 条 X 帖子、5 个 GitHub 仓库、3 个 Blender 教程作为测试集，每条提取结果必须包含至少 1 个 `copy_ready_payload`，且 `content` 字段为可直接粘贴的原文（非改写摘要）。
2. **Obsidian 可用性**：双击打开 Obsidian Vault → `01-精选技能库(Skills)/` → 任意技能笔记 → "即插即用"区的代码块可一键复制。
3. **HUD 直觉性**：邀请零代码用户测试，要求在不看说明的情况下 10 秒内找到"拷贝 Prompt"按钮并成功复制。
4. **向后兼容**：旧 `entries.json` 中的历史条目仍可正常展示，新字段缺失时回退到旧版展示逻辑。
5. **文件大小**：所有修改后的代码文件 ≤ 20 KB。
6. **测试通过**：`uv run pytest` 全绿 + `swift test` 全绿 + `--dry-run` 100%。
