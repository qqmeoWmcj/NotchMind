"""P1 schema tests: new high-order fields serialize losslessly and old entries stay compatible."""
from __future__ import annotations

import json
from pathlib import Path

from src.agent.engine import GeminiHotspotAgent
from src.agent.prompts import build_knowledge_prompt
from src.exporters import ensure_vault_initialized, list_knowledge_entries, save_knowledge_entry
from src.models import KnowledgeEntry

RICH_EXTRACTION = {
    "title": "Blender 几何节点阵列吸附实战",
    "domain": "03-AI创作与3D工具",
    "ladder_level": "L2工具与AI联动",
    "matched_project": "Blender一站式AI建模",
    "one_line_essence": "用分布+最近点吸附替代手工对位，阵列效率提升一个量级。",
    "how_to_apply": "在几何节点里建 Instance on Points，再接 Sample Nearest Surface 取目标位置。",
    "deep_insight": "吸附本质是最近点搜索，选对搜索半径比调迭代次数更重要。",
    "tags": ["Blender", "几何节点"],
    "heat_score": 9,
    "actionable_steps": [
        "新建 Spreadsheet 检查网格顶点分布",
        "Instance on Points 生成基础阵列",
        "Sample Nearest Surface 吸附到目标曲面",
    ],
    "project_optimizations": [
        "把现有逐点建模流程替换为节点化阵列，减少 80% 手工对位",
        "在自动出图前统一做一次法向重算，避免吸附后阴影穿帮",
    ],
    "blender_script": "import bpy\nbpy.ops.object.select_all(action='SELECT')\nbpy.ops.object.delete()",
    "concept_breakdown": [
        {
            "concept": "最近点搜索",
            "intuition": "在离散点集里找距离最小的那个，就是吸附的数学本质。",
            "analogy": "像在人群里找离你最近的那个人问路。",
        },
        {"concept": "实例化", "intuition": "一份几何数据多处引用，改一次全更新。", "analogy": "像同一张底片洗多张照片。"},
    ],
}


def test_knowledge_entry_new_fields_roundtrip_and_obsidian_render(tmp_path: Path) -> None:
    vault, data = tmp_path / "vault", tmp_path / "data"
    ensure_vault_initialized(vault, data)

    entry = KnowledgeEntry(
        title="Blender 几何节点阵列吸附实战",
        source="B站视频",
        url="https://www.bilibili.com/video/BV1p1newFields",
        domain="03-AI创作与3D工具",
        ladder_level="L2工具与AI联动",
        matched_project="Blender一站式AI建模",
        one_line_essence=RICH_EXTRACTION["one_line_essence"],
        how_to_apply=RICH_EXTRACTION["how_to_apply"],
        deep_insight=RICH_EXTRACTION["deep_insight"],
        actionable_steps=RICH_EXTRACTION["actionable_steps"],
        project_optimizations=RICH_EXTRACTION["project_optimizations"],
        blender_script=RICH_EXTRACTION["blender_script"],
        concept_breakdown=RICH_EXTRACTION["concept_breakdown"],
    )
    saved = save_knowledge_entry(vault, data, entry)

    # entries.json keeps every new field losslessly.
    stored = json.loads((data / "entries.json").read_text(encoding="utf-8"))[0]
    assert stored["actionable_steps"] == RICH_EXTRACTION["actionable_steps"]
    assert stored["project_optimizations"] == RICH_EXTRACTION["project_optimizations"]
    assert stored["blender_script"] == RICH_EXTRACTION["blender_script"]
    assert stored["concept_breakdown"] == RICH_EXTRACTION["concept_breakdown"]
    assert saved["id"] == stored["id"]

    # Domain file renders the new sections.
    domain_text = (vault / "03-AI创作与3D工具.md").read_text(encoding="utf-8")
    assert "**实操步骤**：" in domain_text
    assert "1. 新建 Spreadsheet 检查网格顶点分布" in domain_text
    assert "**项目优化（[[Blender一站式AI建模]]）**：" in domain_text
    assert "**Blender 脚本**：" in domain_text
    assert "```python" in domain_text and "bpy.ops.object.delete()" in domain_text
    assert "**概念拆解**：" in domain_text
    assert "类比：像在人群里找离你最近的那个人问路。" in domain_text

    # Project ladder file renders steps and optimizations too.
    proj_text = (vault / "05-项目孵化池" / "Blender一站式AI建模.md").read_text(encoding="utf-8")
    assert "实操步骤：" in proj_text
    assert "3. Sample Nearest Surface 吸附到目标曲面" in proj_text
    assert "项目优化（[[Blender一站式AI建模]]）：" in proj_text

    # list_knowledge_entries (JSON index path used by the workbench) keeps the fields.
    listed = list_knowledge_entries(data, project="Blender一站式AI建模")
    assert listed and listed[0]["actionable_steps"] == RICH_EXTRACTION["actionable_steps"]


def test_old_entries_without_new_fields_stay_compatible(tmp_path: Path) -> None:
    vault, data = tmp_path / "vault", tmp_path / "data"
    ensure_vault_initialized(vault, data)

    # Hand-write an old-shape entry JSON, exactly as pre-P1 data would look.
    old = {
        "id": "legacy0001",
        "title": "旧版条目",
        "source": "HackerNews",
        "url": "https://example.com/old",
        "domain": "01-LLM与新模型",
        "ladder_level": "L1基础教程",
        "matched_project": None,
        "one_line_essence": "旧字段齐全",
        "how_to_apply": "旧条目照常可用",
        "deep_insight": "向前兼容不受影响",
        "created_at": "2026-11-19 10:00",
        "tags": ["legacy"],
        "heat_score": 7,
    }
    (data / "entries.json").write_text(json.dumps([old], ensure_ascii=False), encoding="utf-8")

    listed = list_knowledge_entries(data)
    assert len(listed) == 1
    assert listed[0].get("actionable_steps", []) == []
    model = KnowledgeEntry.model_validate(listed[0])
    assert model.actionable_steps == [] and model.blender_script == ""
    assert model.concept_breakdown == [] and model.project_optimizations == []
    assert model.id == "legacy0001"

    # Saving the legacy-shaped dict again hits the existing-id short circuit:
    # the stored JSON stays byte-identical (no rewrite, no data loss), and readers
    # treat the missing keys as defaults.
    again = save_knowledge_entry(vault, data, listed[0])
    assert again["id"] == "legacy0001"
    entries = json.loads((data / "entries.json").read_text(encoding="utf-8"))
    assert len(entries) == 1
    assert "actionable_steps" not in entries[0], "existing-id short circuit must not rewrite old entries"
    validated = KnowledgeEntry.model_validate(entries[0])
    assert validated.actionable_steps == [] and validated.blender_script == ""


def test_engine_maps_extraction_to_entry_high_order_fields(tmp_path: Path) -> None:
    agent = GeminiHotspotAgent.__new__(GeminiHotspotAgent)

    class _StubResponse:
        text = json.dumps(RICH_EXTRACTION, ensure_ascii=False)

        class models:  # noqa: N801
            @staticmethod
            def generate_content(**kwargs):
                return _StubResponse()

    agent.client = _StubResponse()
    agent.model = "gemini-3.8-flash"

    entry = agent.analyze_content(
        source="B站视频",
        title="略",
        url="https://www.bilibili.com/video/BV1p1newFields",
        text="素材正文",
        project_names=["Blender一站式AI建模", "另一个项目"],
    )
    assert entry.actionable_steps == RICH_EXTRACTION["actionable_steps"]
    assert entry.project_optimizations == RICH_EXTRACTION["project_optimizations"]
    assert entry.blender_script == RICH_EXTRACTION["blender_script"]
    assert entry.concept_breakdown == RICH_EXTRACTION["concept_breakdown"]
    assert entry.matched_project == "Blender一站式AI建模"


def test_engine_drops_project_optimizations_when_no_project_matched() -> None:
    agent = GeminiHotspotAgent.__new__(GeminiHotspotAgent)
    payload = dict(RICH_EXTRACTION)
    payload["matched_project"] = None
    payload["project_optimizations"] = ["幻觉出的优化建议，必须丢弃"]

    class _StubResponse:
        text = json.dumps(payload, ensure_ascii=False)

        class models:  # noqa: N801
            @staticmethod
            def generate_content(**kwargs):
                return _StubResponse()

    agent.client = _StubResponse()
    agent.model = "gemini-3.8-flash"

    entry = agent.analyze_content(source="网页文章", title="t", url="https://example.com/x", text="素材")
    assert entry.matched_project is None
    assert entry.project_optimizations == [], "no matched project must force empty optimizations"

    # And the prompt advertises all four new fields so Gemini knows to emit them.
    prompt = build_knowledge_prompt(source="s", title="t", text="x", project_names=["某项目"])
    for key in ("actionable_steps", "project_optimizations", "blender_script", "concept_breakdown"):
        assert key in prompt
