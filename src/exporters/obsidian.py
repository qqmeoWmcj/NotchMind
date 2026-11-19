from __future__ import annotations

import re
from pathlib import Path

from src.models import AnalyzedTopic


def _safe_filename(text: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|\s]+', "-", text.strip())
    return cleaned.strip("-")[:28] or "未命名热点"


def _yaml_tags(tags: list[str]) -> str:
    clean = [t.strip().lstrip("#") for t in tags if t.strip()]
    if not clean:
        clean = ["AI热点"]
    return "\n".join(f"  - {t}" for t in clean)


def export_to_obsidian(
    vault_root: Path, run_date: str, topics: list[AnalyzedTopic]
) -> dict[str, Path]:
    """Write structured 5-folder Obsidian layout with YAML frontmatter, wikilinks, and MOC."""
    dashboard_dir = vault_root / "00-Dashboard"
    moc_dir = vault_root / "01-Daily-MOC"
    cards_dir = vault_root / "02-Hotspot-Cards" / run_date
    drafts_dir = vault_root / "03-Content-Drafts" / run_date
    for d in (dashboard_dir, moc_dir, cards_dir, drafts_dir):
        d.mkdir(parents=True, exist_ok=True)

    moc_rows: list[str] = []

    for idx, topic in enumerate(topics, start=1):
        prefix = f"{idx:02d}-{_safe_filename(topic.short_slug)}"
        card_name = prefix
        xhs_name = f"{prefix}-小红书图文"
        vid_name = f"{prefix}-口播脚本"
        art_name = f"{prefix}-深度长文"

        # 1. Hotspot Card
        card_md = (
            f"---\n"
            f"date: {run_date}\n"
            f"type: hotspot-card\n"
            f"source: \"{topic.source}\"\n"
            f"heat_score: {topic.heat_score}\n"
            f"status: 待创作\n"
            f"url: \"{topic.url}\"\n"
            f"tags:\n{_yaml_tags(topic.tags)}\n"
            f"---\n\n"
            f"# {topic.title}\n\n"
            f"> [!summary] 一句话本质\n"
            f"> {topic.one_line_essence}\n\n"
            f"## 为什么现在值得聊\n{topic.why_now}\n\n"
            f"## 深度行业认知\n{topic.deep_insight}\n\n"
            f"## 关联创作草稿\n"
            f"- 小红书图文：[[{xhs_name}]]\n"
            f"- 口播脚本：[[{vid_name}]]\n"
            f"- 深度长文：[[{art_name}]]\n\n"
            f"## 原始出处\n- [{topic.source}]({topic.url})\n"
        )
        (cards_dir / f"{card_name}.md").write_text(card_md, encoding="utf-8")

        # 2. Xiaohongshu Draft
        titles_md = "\n".join(f"{i}. {t}" for i, t in enumerate(topic.drafts.xiaohongshu_titles, 1))
        xhs_md = (
            f"---\ndate: {run_date}\ntype: draft-xiaohongshu\nparent: \"[[{card_name}]]\"\n---\n\n"
            f"# 小红书图文｜{topic.title}\n\n"
            f"## 备选标题\n{titles_md}\n\n"
            f"## 封面大字\n> {topic.drafts.xiaohongshu_cover_copy}\n\n"
            f"## 正文草稿\n{topic.drafts.xiaohongshu_body}\n"
        )
        (drafts_dir / f"{xhs_name}.md").write_text(xhs_md, encoding="utf-8")

        # 3. Video Script Draft
        vid_md = (
            f"---\ndate: {run_date}\ntype: draft-video\nparent: \"[[{card_name}]]\"\n---\n\n"
            f"# 口播脚本｜{topic.title}\n\n"
            f"## 黄金 3 秒钩子\n> {topic.drafts.video_hook_3s}\n\n"
            f"## 完整讲稿与画面提示\n{topic.drafts.video_script}\n"
        )
        (drafts_dir / f"{vid_name}.md").write_text(vid_md, encoding="utf-8")

        # 4. Long Article Outline
        art_md = (
            f"---\ndate: {run_date}\ntype: draft-article\nparent: \"[[{card_name}]]\"\n---\n\n"
            f"# 深度长文大纲｜{topic.title}\n\n"
            f"{topic.drafts.long_article_outline}\n"
        )
        (drafts_dir / f"{art_name}.md").write_text(art_md, encoding="utf-8")

        moc_rows.append(
            f"| {idx} | [[{card_name}]] | {topic.heat_score}/10 | {topic.source} "
            f"| [[{xhs_name}\\|小红书]] · [[{vid_name}\\|口播]] · [[{art_name}\\|长文]] |"
        )

    # 5. Daily MOC
    moc_filename = f"{run_date}-AI热点日报"
    moc_path = moc_dir / f"{moc_filename}.md"
    moc_md = (
        f"---\ndate: {run_date}\ntype: daily-moc\ncount: {len(topics)}\n---\n\n"
        f"# {run_date} AI 热点创作日报\n\n"
        f"## 今日精选总览\n\n"
        f"| # | 热点卡片 | 热度 | 来源 | 多平台草稿 |\n"
        f"|---|---|---|---|---|\n"
        + "\n".join(moc_rows)
        + f"\n\n## NotebookLM 深度素材包\n- [[{run_date}-NotebookLM源文档]]\n"
    )
    moc_path.write_text(moc_md, encoding="utf-8")

    # 6. Update Global Dashboard
    dashboard_path = dashboard_dir / "热点创作总览.md"
    entry_line = f"- [[{moc_filename}]]（精选 {len(topics)} 条）"
    if dashboard_path.exists():
        existing = dashboard_path.read_text(encoding="utf-8")
        if entry_line not in existing:
            dashboard_path.write_text(existing.rstrip() + "\n" + entry_line + "\n", encoding="utf-8")
    else:
        dashboard_path.write_text(
            f"# AI 热点创作总览（Dashboard）\n\n## 每日日报索引\n{entry_line}\n",
            encoding="utf-8",
        )

    return {"moc": moc_path, "dashboard": dashboard_path}
