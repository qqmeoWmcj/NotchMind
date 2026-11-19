from __future__ import annotations

from pathlib import Path
from typing import Any

from src.models import KnowledgeEntry


def export_notebooklm_source(
    output_dir: Path, run_date: str, entries: list[KnowledgeEntry | dict[str, Any]]
) -> Path:
    """Generate a single clean source document optimized for Google NotebookLM upload.

    Writes directly inside output_dir (recommended: data/notebooklm/) so vault/ stays minimal.
    """
    target_dir = Path(output_dir)
    target_dir.mkdir(parents=True, exist_ok=True)
    out_path = target_dir / f"{run_date}-NotebookLM源文档.md"

    normalized = [
        e if isinstance(e, KnowledgeEntry) else KnowledgeEntry.model_validate(e)
        for e in entries
    ]

    sections: list[str] = [
        f"# {run_date} AI 行业热点深度素材包（NotebookLM 专用源文档）",
        "",
        "## 使用建议（可直接复制到 NotebookLM 对话框或 Audio Overview 定制指令）",
        "- 提问 1：今天这几条知识条目背后，有没有一条共同的技术演进主线？",
        "- 提问 2：结合我当前推进的个人项目，哪一条最适合立刻落地到 L2 工具联动或 L3 自动化闭环？",
        "- 播客指令：请用两位资深 AI 工程师复盘的口吻，犀利拆解这些动态的可执行价值与潜在坑点，避免空洞套话。",
        "",
        "---",
    ]

    for idx, entry in enumerate(normalized, start=1):
        proj_line = f"- **关联项目**：{entry.matched_project}" if entry.matched_project else "- **关联项目**：无"
        sections.extend(
            [
                f"## 条目 {idx}：{entry.title}",
                f"- **领域**：{entry.domain}",
                f"- **演进阶段**：{entry.ladder_level}",
                proj_line,
                f"- **信息来源**：{entry.source}",
                f"- **原始链接**：{entry.url or '无'}",
                f"- **一句话本质**：{entry.one_line_essence}",
                "",
                "### 我可以怎么用",
                entry.how_to_apply,
                "",
                "### 深度认知",
                entry.deep_insight,
                "",
                "---",
            ]
        )

    out_path.write_text("\n".join(sections), encoding="utf-8")
    return out_path
