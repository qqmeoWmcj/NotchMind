"""Skill-hub pipeline tests: extraction fields survive engine mapping, skill card + action board land on disk."""
from __future__ import annotations

import json
from pathlib import Path

from src.agent.engine import GeminiHotspotAgent
from src.exporters import ensure_vault_initialized, save_knowledge_entry
from src.models import KnowledgeEntry

SKILL_EXTRACTION = {
    "title": "Cursor 高级 Rules 配置法",
    "domain": "02-AI学习与教程",
    "ladder_level": "L2工具与AI联动",
    "matched_project": "AI短视频工作流",
    "one_line_essence": "把项目约束写进 .cursor/rules，Agent 不再每轮重新猜上下文。",
    "how_to_apply": "在项目根建 .cursor/rules/alive.md，把验收标准写成可勾选清单。",
    "deep_insight": "Rules 是给 Agent 的持久记忆，比每条消息里塞背景便宜一个数量级。",
    "tags": ["Cursor", "Agent"],
    "heat_score": 9,
    "actionable_steps": ["新建 .cursor/rules 目录", "把验收清单写入 alive.md"],
    "project_optimizations": ["短视频脚本草稿生成前强制先读 Rules 验收清单"],
    "blender_script": "",
    "concept_breakdown": [],
    "skill_name": "Cursor Rules持久约束",
    "pain_point": "每次新会话都要重新交代一遍项目背景",
    "copy_ready_payloads": [
        {
            "type": "prompt",
            "label": "Rules 模板",
            "content": "你是本项目 Agent。任何回复前先对照本清单自检：\n1. 输出可一键复制\n2. 无空话",
            "source_note": "来自 X @example 帖子原文",
        },
        {"type": "command", "label": "空载荷", "content": "  ", "source_note": ""},
    ],
    "treasure_links": [
        {"title": "Cursor 官方 Rules 文档", "url": "https://docs.cursor.com/context/rules", "why": "权威字段说明"},
        {"title": "无效链接", "url": "javascript:alert(1)", "why": "必须被清洗掉"},
    ],
    "gotchas": ["Rules 文件超过 200 行 Agent 会忽略尾部"],
    "source_type": "x_post",
}


def _stub_agent_with(payload: dict) -> GeminiHotspotAgent:
    agent = GeminiHotspotAgent.__new__(GeminiHotspotAgent)

    class _Resp:
        text = json.dumps(payload, ensure_ascii=False)

        class models:  # noqa: N801
            @staticmethod
            def generate_content(**kwargs):
                return _Resp()

    agent.client = _Resp()
    agent.model = "gemini-3.8-flash"
    return agent


def test_skill_fields_flow_extraction_to_entry_and_skill_card(tmp_path: Path) -> None:
    vault, data = tmp_path / "vault", tmp_path / "data"
    ensure_vault_initialized(vault, data)

    agent = _stub_agent_with(SKILL_EXTRACTION)
    entry = agent.analyze_content(
        source="X 帖子",
        title="t",
        url="https://x.com/example/status/1",
        text="素材正文",
        project_names=["AI短视频工作流"],
    )

    # Engine mapping must not silently drop the five skill fields (the P2 gap this test guards).
    assert entry.skill_name == "Cursor Rules持久约束"
    assert entry.pain_point == "每次新会话都要重新交代一遍项目背景"
    assert entry.source_type == "x_post"
    assert len(entry.copy_ready_payloads) == 1, "empty-content payload must be dropped"
    assert "自检" in entry.copy_ready_payloads[0]["content"]
    assert len(entry.treasure_links) == 1, "non-http link must be dropped"
    assert entry.treasure_links[0]["url"] == "https://docs.cursor.com/context/rules"
    assert entry.gotchas == ["Rules 文件超过 200 行 Agent 会忽略尾部"]

    saved = save_knowledge_entry(vault, data, entry)

    # entries.json keeps every skill field losslessly.
    stored = json.loads((data / "entries.json").read_text(encoding="utf-8"))[0]
    assert stored["skill_name"] == entry.skill_name
    assert stored["copy_ready_payloads"] == entry.copy_ready_payloads
    assert stored["treasure_links"] == entry.treasure_links

    # Standalone skill card renders verbatim payload + treasure + gotcha sections.
    card = vault / "01-精选技能库" / "SK-Cursor Rules持久约束.md"
    assert card.exists(), f"skill card missing: {sorted(p.name for p in (vault / '01-精选技能库').iterdir())}"
    card_text = card.read_text(encoding="utf-8")
    assert "解决痛点" in card_text and entry.pain_point in card_text
    assert "```markdown" in card_text or "```text" in card_text
    assert "自检" in card_text, "verbatim payload content must land in the card"
    assert "docs.cursor.com" in card_text
    assert "javascript:alert" not in card_text, "cleaned link must not leak into the card"
    assert entry.gotchas[0] in card_text

    # Project optimizations sync into the action board as checkable todos.
    board = vault / "03-项目反哺任务池" / "ACT-AI短视频工作流.md"
    assert board.exists()
    board_text = board.read_text(encoding="utf-8")
    assert "- [ ] 短视频脚本草稿生成前强制先读 Rules 验收清单" in board_text
    assert f"<!-- entry_id:{saved['id']} -->" in board_text

    # Inline domain entry stays compact: one skill line, no duplicated payload blocks.
    domain_text = (vault / "02-AI学习与教程.md").read_text(encoding="utf-8")
    assert "**技能**：Cursor Rules持久约束" in domain_text
    assert domain_text.count("自检") == 0, "verbatim payload renders only in the skill card (AGENTS.md #2)"


def test_legacy_entry_without_skill_fields_writes_no_skill_card(tmp_path: Path) -> None:
    vault, data = tmp_path / "vault", tmp_path / "data"
    ensure_vault_initialized(vault, data)

    legacy = KnowledgeEntry(
        title="旧版纯认知条目",
        source="HackerNews",
        url="https://example.com/legacy",
        domain="04-行业深度认知",
        ladder_level="L1基础教程",
        one_line_essence="e",
        how_to_apply="h",
        deep_insight="d",
    )
    save_knowledge_entry(vault, data, legacy)

    skills_dir = vault / "01-精选技能库"
    assert not list(skills_dir.glob("*.md")), "legacy entries must not create skill cards"
    domain_text = (vault / "04-行业深度认知.md").read_text(encoding="utf-8")
    assert "**技能**" not in domain_text, "no skill line for skill-less legacy entries"
