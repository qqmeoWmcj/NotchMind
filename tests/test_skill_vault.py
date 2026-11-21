from __future__ import annotations

from pathlib import Path

from src.exporters.obsidian import save_knowledge_entry
from src.exporters.skill_vault import (
    ACTIONS_DIRNAME,
    SKILLS_DIRNAME,
    WORKFLOWS_DIRNAME,
    ensure_skill_directories,
    render_skill_card_markdown,
)
from src.models import KnowledgeEntry


def test_skill_vault_directories_and_card_export(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    data = tmp_path / "data"

    ensure_skill_directories(vault)
    assert (vault / SKILLS_DIRNAME).is_dir()
    assert (vault / WORKFLOWS_DIRNAME).is_dir()
    assert (vault / ACTIONS_DIRNAME).is_dir()

    entry = KnowledgeEntry(
        title="Cursor 提示词与 Rules 生产力规范",
        source="X/Twitter",
        url="https://x.com/tech_lead/status/12345678",
        domain="02-AI学习与教程",
        ladder_level="L2工具与AI联动",
        matched_project="NotchMind",
        one_line_essence="通过 .cursorrules 将架构规范固化在 IDE 级别，无需每次对话重复背景。",
        how_to_apply="在项目根目录创建 .cursorrules 并贴入标准化代码审查规范。",
        deep_insight="个人 Agent 效率的瓶颈不是模型智商，而是上下文注入的精准度与确定性。",
        skill_name="Cursor高级Rules规范",
        pain_point="每次让 AI 审查代码都要重复粘贴一堆技术栈限制和约束",
        copy_ready_payloads=[
            {
                "type": "prompt",
                "label": "高级代码审查 Prompt",
                "content": "You are a senior tech lead. Inspect for memory leaks and race conditions.",
                "source_note": "来自推文原帖",
            }
        ],
        treasure_links=[
            {
                "title": "Cursor Directory",
                "url": "https://cursor.directory",
                "why": "收录了社区最完整的开源 .cursorrules 模板库",
            }
        ],
        gotchas=[
            "单个 .cursorrules 文件超过 2000 token 会被部分模型截断",
            "不支持跨层级嵌套目录读取，必须放置于根目录",
        ],
        actionable_steps=[
            "在根目录新建 .cursorrules 文件",
            "粘贴上述标准审查规则",
            "在对话中触发 @.cursorrules 进行验证",
        ],
        project_optimizations=[
            "为 NotchMind 项目配置专属 Swift 视图层级审查 rules",
            "在预提交钩子中增加规则有效性检查",
        ],
        source_type="x_post",
    )

    # Test standalone markdown renderer
    md = render_skill_card_markdown(entry)
    assert "# Cursor高级Rules规范" in md
    assert "解决痛点" in md
    assert "高级代码审查 Prompt" in md
    assert "https://cursor.directory" in md
    assert "避坑提醒" in md
    assert "反哺项目待办" in md

    # Test saving via main exporter
    save_knowledge_entry(vault, data, entry)

    card_file = vault / SKILLS_DIRNAME / "SK-Cursor高级Rules规范.md"
    assert card_file.exists()
    card_content = card_file.read_text(encoding="utf-8")
    assert "Cursor高级Rules规范" in card_content
    assert "https://cursor.directory" in card_content

    action_file = vault / ACTIONS_DIRNAME / "ACT-NotchMind.md"
    assert action_file.exists()
    action_content = action_file.read_text(encoding="utf-8")
    assert "为 NotchMind 项目配置专属 Swift 视图层级审查 rules" in action_content
