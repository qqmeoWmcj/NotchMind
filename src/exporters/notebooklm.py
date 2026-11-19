from __future__ import annotations

from pathlib import Path

from src.models import AnalyzedTopic


def export_notebooklm_source(
    vault_root: Path, run_date: str, topics: list[AnalyzedTopic]
) -> Path:
    """Generate a single clean source document optimized for Google NotebookLM upload."""
    export_dir = vault_root / "04-NotebookLM-Exports"
    export_dir.mkdir(parents=True, exist_ok=True)
    out_path = export_dir / f"{run_date}-NotebookLM源文档.md"

    sections: list[str] = [
        f"# {run_date} AI 行业热点深度素材包（NotebookLM 专用源文档）",
        "",
        "## 使用建议（可直接复制到 NotebookLM 对话框或 Audio Overview 定制指令）",
        "- 提问 1：今天这几个 AI 热点背后，有没有一条共同的技术演进主线？",
        "- 提问 2：如果我要拍一条 3 分钟高认知口播视频，应该用哪一个热点当主线、哪一个当反例？",
        "- 播客指令：请用两位资深 AI 产品经理聊天的口吻，犀利拆解这些热点对个人创作者的真实机会，避免泛泛而谈。",
        "",
        "---",
    ]

    for idx, t in enumerate(topics, start=1):
        sections.extend(
            [
                f"## 热点 {idx}：{t.title}（热度 {t.heat_score}/10）",
                f"- **信息来源**：{t.source}",
                f"- **原始链接**：{t.url}",
                f"- **一句话本质**：{t.one_line_essence}",
                "",
                "### 为什么现在爆发",
                t.why_now,
                "",
                "### 深度行业认知",
                t.deep_insight,
                "",
                "### 延伸创作切入点（长文大纲）",
                t.drafts.long_article_outline,
                "",
                "---",
            ]
        )

    out_path.write_text("\n".join(sections), encoding="utf-8")
    return out_path
