from pathlib import Path

from src.exporters import export_notebooklm_source, export_to_obsidian
from src.memory import TopicMemory
from src.models import AnalyzedTopic, ContentDrafts, RawItem


def _sample_topic() -> AnalyzedTopic:
    return AnalyzedTopic(
        short_slug="Agent长期记忆演进",
        title="为什么 2026 年 AI Agent 的决胜点变成了长期记忆",
        source="HackerNews",
        url="https://example.com/agent-memory",
        heat_score=9,
        one_line_essence="Agent 从单轮对话走向跨周自主执行，瓶颈不再是模型智商而是记忆检索。",
        why_now="主流框架本周密集发布了持久状态层，社区讨论度飙升。",
        deep_insight="真正拉开差距的不是塞进更多上下文，而是知道什么时候该忘掉噪声。",
        tags=["AIAgent", "长期记忆"],
        drafts=ContentDrafts(
            xiaohongshu_titles=["标题1", "标题2", "标题3"],
            xiaohongshu_cover_copy="Agent 卷到最后，其实是在卷记忆",
            xiaohongshu_body="正文内容 #AIAgent",
            video_hook_3s="很多人用 AI 越用越笨，其实不是模型退步了。",
            video_script="[画面：记忆漏斗图] 讲稿内容...",
            long_article_outline="## 一、背景\n## 二、核心机制",
        ),
    )


def test_sqlite_memory_persists_and_deduplicates(tmp_path: Path) -> None:
    db_path = tmp_path / "memory.db"
    memory = TopicMemory(db_path)

    item_a = RawItem(source="HN", title="Agent Memory", url="https://example.com/a", score=100)
    item_a_dup = RawItem(source="HN", title="Agent Memory", url="https://example.com/a", score=100)
    item_b = RawItem(source="GitHub", title="MCP Server", url="https://example.com/b", score=200)

    unseen_first = memory.filter_unseen([item_a, item_a_dup, item_b])
    assert len(unseen_first) == 2

    inserted = memory.mark_seen([item_a])
    assert inserted == 1

    # Re-open SQLite from disk to verify real persistence
    reloaded = TopicMemory(db_path)
    unseen_second = reloaded.filter_unseen([item_a, item_b])
    assert [i.url for i in unseen_second] == ["https://example.com/b"]


def test_obsidian_and_notebooklm_exports_create_structured_layout(tmp_path: Path) -> None:
    vault = tmp_path / "vault"
    run_date = "2026-11-19"
    topic = _sample_topic()

    paths = export_to_obsidian(vault, run_date, [topic])
    nlm_path = export_notebooklm_source(vault, run_date, [topic])

    assert paths["moc"].exists()
    assert paths["dashboard"].exists()
    assert nlm_path.exists()

    card = vault / "02-Hotspot-Cards" / run_date / "01-Agent长期记忆演进.md"
    xhs = vault / "03-Content-Drafts" / run_date / "01-Agent长期记忆演进-小红书图文.md"
    vid = vault / "03-Content-Drafts" / run_date / "01-Agent长期记忆演进-口播脚本.md"
    art = vault / "03-Content-Drafts" / run_date / "01-Agent长期记忆演进-深度长文.md"

    for f in (card, xhs, vid, art):
        assert f.exists(), f"Missing expected Obsidian file: {f}"

    moc_text = paths["moc"].read_text(encoding="utf-8")
    assert "[[01-Agent长期记忆演进]]" in moc_text
    assert "[[2026-11-19-NotebookLM源文档]]" in moc_text

    nlm_text = nlm_path.read_text(encoding="utf-8")
    assert "NotebookLM" in nlm_text
    assert topic.deep_insight in nlm_text


def test_model_alias_resolution() -> None:
    from src.agent.engine import resolve_model_name

    assert resolve_model_name("3.8f") == "gemini-3.8-flash"
    assert resolve_model_name("4h") == "gemini-4-hydrogen"
    assert resolve_model_name("4a") == "gemini-4-argon"
    assert resolve_model_name("custom-model") == "custom-model"
