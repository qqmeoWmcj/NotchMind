"""Markdown rendering helpers for knowledge-entry extras (split from obsidian.py, 20KB rule)."""
from __future__ import annotations

from src.models import KnowledgeEntry


def _format_skill_lines(entry: KnowledgeEntry) -> list[str]:
    """Compact one-line skill header for inline domain entries.

    Full verbatim payloads / treasure links / gotchas render ONLY in the standalone
    skill card (src/exporters/skill_vault.py) — one source per rule (AGENTS.md #2).
    """
    skill = entry.skill_name.strip()
    if not skill:
        return []
    header = f"- **技能**：{skill}"
    pain = entry.pain_point.strip()
    if pain:
        header += f"（痛点：{pain}）"
    return [header]


def _format_concept_lines(entry: KnowledgeEntry) -> list[str]:
    lines = ["- **概念拆解**："]
    for item in entry.concept_breakdown[:3]:
        if not isinstance(item, dict):
            continue
        concept = str(item.get("concept") or "").strip()
        if not concept:
            continue
        intuition = str(item.get("intuition") or "").strip()
        analogy = str(item.get("analogy") or "").strip()
        line = f"  - {concept}"
        if intuition:
            line += f"：{intuition}"
        if analogy:
            line += f"（类比：{analogy}）"
        lines.append(line)
    return lines if len(lines) > 1 else []
