from __future__ import annotations

import re
from pathlib import Path
from typing import Any

from src.models import KnowledgeEntry

SKILLS_DIRNAME = "01-精选技能库"
WORKFLOWS_DIRNAME = "02-即插即用工作流"
ACTIONS_DIRNAME = "03-项目反哺任务池"


def _safe_filename(name: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|\r\n]+', "-", name.strip())
    cleaned = cleaned.strip(" .-")[:48]
    return cleaned or "未命名技能"


def _code_fence_for_type(payload_type: str) -> str:
    low = payload_type.lower()
    if "python" in low or "bpy" in low or "script" in low:
        return "python"
    if "bash" in low or "sh" in low or "command" in low:
        return "bash"
    if "json" in low:
        return "json"
    if "yaml" in low or "yml" in low:
        return "yaml"
    return "markdown"


def ensure_skill_directories(vault_root: Path) -> None:
    """Ensure the 3-tier skill hub directory structure exists."""
    for dirname in (SKILLS_DIRNAME, WORKFLOWS_DIRNAME, ACTIONS_DIRNAME):
        (vault_root / dirname).mkdir(parents=True, exist_ok=True)


def render_skill_card_markdown(entry: KnowledgeEntry) -> str:
    """Render an intuitive, copy-ready skill card Markdown note for Obsidian."""
    display_name = (entry.skill_name or entry.title).strip()
    pain = (entry.pain_point or entry.one_line_essence).strip()

    lines = [
        "---",
        f"id: \"{entry.id}\"",
        f"title: \"{entry.title}\"",
        f"skill_name: \"{display_name}\"",
        f"domain: \"{entry.domain}\"",
        f"source_type: \"{entry.source_type}\"",
        f"source: \"{entry.source}\"",
        f"created_at: \"{entry.created_at}\"",
        "type: \"skill-card\"",
        "---",
        "",
        f"# {display_name}",
        "",
        f"> 💡 **解决痛点**：{pain}",
        "",
        f"- **出处来源**：{entry.source} " + (f"· [原文链接]({entry.url})" if entry.url else ""),
        f"- **领域分类**：[[{entry.domain}]] · **成熟度**：`{entry.ladder_level}`",
        "",
        "## 📋 即插即用载荷（点击代码块右上角直接拷贝）",
        "",
    ]

    # 1. Copy-ready payloads
    if entry.copy_ready_payloads:
        for idx, p in enumerate(entry.copy_ready_payloads, 1):
            ptype = str(p.get("type") or "prompt")
            label = str(p.get("label") or f"载荷 {idx}")
            content = str(p.get("content") or "").strip()
            note = str(p.get("source_note") or "").strip()
            fence = _code_fence_for_type(ptype)
            lines.append(f"### {idx}. {label} (`{ptype}`)")
            if note:
                lines.append(f"> 说明：{note}\n")
            lines.append(f"```{fence}\n{content}\n```\n")
    elif entry.blender_script.strip():
        lines.append("### Blender Python (bpy) 实操脚本")
        lines.append(f"```python\n{entry.blender_script.strip()}\n```\n")
    else:
        lines.append(f"```markdown\n{entry.how_to_apply}\n```\n")

    # 2. Treasure links
    if entry.treasure_links:
        lines.append("## 🔗 宝藏工具与外链（从推文/评论区精选）\n")
        for link in entry.treasure_links:
            ltitle = str(link.get("title") or "推荐资源").strip()
            lurl = str(link.get("url") or "").strip()
            lwhy = str(link.get("why") or "").strip()
            lines.append(f"- [{ltitle}]({lurl})" + (f" — {lwhy}" if lwhy else ""))
        lines.append("")

    # 3. Gotchas
    if entry.gotchas:
        lines.append("## ⚠️ 避坑提醒（小白必看）\n")
        for g in entry.gotchas:
            lines.append(f"- ⚠️ {g}")
        lines.append("")

    # 4. Actionable steps
    if entry.actionable_steps:
        lines.append("## 🛠️ 实操执行步骤\n")
        for idx, step in enumerate(entry.actionable_steps, 1):
            lines.append(f"{idx}. {step}")
        lines.append("")

    # 5. Project optimizations
    if entry.project_optimizations:
        lines.append(f"## 🎯 反哺项目待办（[[{entry.matched_project or '通用待办'}]]）\n")
        for opt in entry.project_optimizations:
            lines.append(f"- [ ] {opt}")
        lines.append("")

    lines.append("---\n*由 NotchMind AI 技能猎手自动提炼生成*\n")
    return "\n".join(lines)


def is_skill_card_worthy(entry: KnowledgeEntry) -> bool:
    """True only when the entry actually carries plug-and-play skill content.

    Guards the skill hub from being flooded by plain cognition/news entries —
    a card needs at least one verbatim payload, a runnable bpy script, or
    an explicitly named skill with treasure links.
    """
    if any(isinstance(p, dict) and str(p.get("content") or "").strip() for p in entry.copy_ready_payloads):
        return True
    if entry.blender_script.strip():
        return True
    return bool(entry.skill_name.strip()) and bool(entry.treasure_links)


def save_skill_card(vault_root: Path, entry: KnowledgeEntry) -> Path:
    """Save an isolated skill card under 01-精选技能库/ (skill-worthy entries only)."""
    if not is_skill_card_worthy(entry):
        return vault_root / SKILLS_DIRNAME  # caller treats as no-op path
    ensure_skill_directories(vault_root)
    skills_dir = vault_root / SKILLS_DIRNAME
    filename = f"SK-{_safe_filename(entry.skill_name or entry.title)}.md"
    card_path = skills_dir / filename
    content = render_skill_card_markdown(entry)
    card_path.write_text(content, encoding="utf-8")

    # If project optimization exists, also sync to 03-项目反哺任务池
    if entry.project_optimizations:
        sync_project_action_board(vault_root, entry)

    return card_path


def sync_project_action_board(vault_root: Path, entry: KnowledgeEntry) -> None:
    """Append actionable tasks to 03-项目反哺任务池/."""
    ensure_skill_directories(vault_root)
    actions_dir = vault_root / ACTIONS_DIRNAME
    proj_name = entry.matched_project or "通用技能待办池"
    filename = f"ACT-{_safe_filename(proj_name)}.md"
    board_path = actions_dir / filename

    marker = f"<!-- entry_id:{entry.id} -->"
    if board_path.exists():
        existing = board_path.read_text(encoding="utf-8")
        if marker in existing:
            return
    else:
        existing = (
            f"---\n"
            f"type: action-board\n"
            f"project: \"{proj_name}\"\n"
            f"---\n\n"
            f"# 🎯 {proj_name} · 落地待办清单\n\n"
        )

    task_lines = [
        marker,
        f"### 来自技能：[[SK-{_safe_filename(entry.skill_name or entry.title)}]]",
        f"- 解决痛点：{entry.pain_point or entry.one_line_essence}",
    ]
    for opt in entry.project_optimizations:
        task_lines.append(f"- [ ] {opt}")
    task_lines.append("")

    new_content = existing.rstrip() + "\n\n" + "\n".join(task_lines) + "\n"
    board_path.write_text(new_content, encoding="utf-8")
