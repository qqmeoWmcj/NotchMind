from __future__ import annotations

import json
import re
import threading
from pathlib import Path
from typing import Any

from src.exporters.skill_render import _format_concept_lines, _format_skill_lines
from src.models import (
    DOMAIN_FILES,
    DOMAINS,
    LADDER_HEADINGS,
    LADDER_LEVELS,
    KnowledgeEntry,
    ProjectIdea,
    normalize_domain,
    now_timestamp,
)
from src.exporters.skill_vault import ensure_skill_directories, save_skill_card

CONSOLE_FILENAME = "00-控制台与速览.md"
PROJECTS_DIRNAME = "05-项目孵化池"
DEFAULT_PROJECT_NAME = "Blender一站式AI建模"
DEFAULT_PROJECT_SUMMARY = (
    "从 Blender 基础建模认知、AI 插件/MCP 工具联动到端到端一站式自动化三维创作闭环。"
)
ENTRIES_MARKER = "<!-- ENTRIES_START -->"
WORKBENCH_BASE_URL = "http://127.0.0.1:8765"

_VAULT_LOCK = threading.RLock()


def _safe_project_name(name: str) -> str:
    cleaned = re.sub(r'[\\/:*?"<>|\r\n]+', "-", name.strip())
    cleaned = cleaned.strip(" .-")[:48]
    if not cleaned:
        raise ValueError("Project name cannot be empty.")
    return cleaned


def _atomic_write_text(path: Path, content: str) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    tmp = path.with_name(f".{path.name}.tmp")
    try:
        tmp.write_text(content, encoding="utf-8")
        tmp.replace(path)
    except Exception:
        tmp.unlink(missing_ok=True)
        raise


def _read_json_list(path: Path) -> list[dict[str, Any]]:
    if not path.exists():
        return []
    try:
        data = json.loads(path.read_text(encoding="utf-8"))
        return data if isinstance(data, list) else []
    except json.JSONDecodeError:
        return []


def _write_json_list(path: Path, items: list[dict[str, Any]]) -> None:
    payload = json.dumps(items, ensure_ascii=False, indent=2) + "\n"
    _atomic_write_text(path, payload)


def _domain_template(domain: str) -> str:
    return (
        f"---\n"
        f"domain: {domain}\n"
        f"type: domain-log\n"
        f"---\n\n"
        f"# {domain}\n\n"
        f"{ENTRIES_MARKER}\n"
    )


def _project_template(name: str, idea_summary: str, created_at: str) -> str:
    summary_line = idea_summary.strip() or "待补充项目核心思路与验收目标。"
    return (
        f"---\n"
        f"type: project-incubator\n"
        f"project: {name}\n"
        f"created_at: {created_at}\n"
        f"---\n\n"
        f"# {name}\n\n"
        f"> 项目想法：{summary_line}\n\n"
        f"{LADDER_HEADINGS['L1基础教程']}\n\n"
        f"{LADDER_HEADINGS['L2工具与AI联动']}\n\n"
        f"{LADDER_HEADINGS['L3一站式自动化']}\n"
    )


def _escape_table_cell(text: str, limit: int = 80) -> str:
    flat = re.sub(r"\s+", " ", text or "").strip().replace("|", "\\|")
    if len(flat) > limit:
        return flat[: limit - 1] + "…"
    return flat


def _extract_project_summary(md_path: Path) -> str:
    if not md_path.exists():
        return ""
    for line in md_path.read_text(encoding="utf-8").splitlines():
        if line.startswith("> 项目想法："):
            return line.removeprefix("> 项目想法：").strip()
    return ""


def _reconcile_projects_locked(vault_root: Path, data_dir: Path) -> list[dict[str, Any]]:
    projects_dir = vault_root / PROJECTS_DIRNAME
    projects_dir.mkdir(parents=True, exist_ok=True)
    projects_json = data_dir / "projects.json"
    stored = _read_json_list(projects_json)
    by_name: dict[str, dict[str, Any]] = {
        str(p["name"]): dict(p) for p in stored if isinstance(p, dict) and p.get("name")
    }

    changed = False
    for md_file in sorted(projects_dir.glob("*.md")):
        name = md_file.stem
        rel_path = f"{PROJECTS_DIRNAME}/{md_file.name}"
        if name not in by_name:
            ts = now_timestamp()
            by_name[name] = ProjectIdea(
                name=name,
                idea_summary=_extract_project_summary(md_file),
                file_path=rel_path,
                created_at=ts,
                updated_at=ts,
            ).model_dump()
            changed = True
        elif by_name[name].get("file_path") != rel_path:
            by_name[name]["file_path"] = rel_path
            changed = True

    result = list(by_name.values())
    if changed or not projects_json.exists():
        _write_json_list(projects_json, result)
    return result


def _build_project_views(
    projects: list[dict[str, Any]], entries: list[dict[str, Any]]
) -> list[dict[str, Any]]:
    views: list[dict[str, Any]] = []
    for proj in projects:
        name = proj["name"]
        ladder: dict[str, list[dict[str, Any]]] = {lvl: [] for lvl in LADDER_LEVELS}
        count = 0
        for entry in entries:
            if entry.get("matched_project") == name:
                lvl = entry.get("ladder_level", LADDER_LEVELS[0])
                if lvl not in ladder:
                    lvl = LADDER_LEVELS[0]
                ladder[lvl].append(entry)
                count += 1
        views.append({**proj, "entry_count": count, "ladder": ladder})
    return views


def _render_console_locked(vault_root: Path, data_dir: Path) -> None:
    entries = _read_json_list(data_dir / "entries.json")
    projects = _build_project_views(_reconcile_projects_locked(vault_root, data_dir), entries)
    updated_at = now_timestamp()

    lines: list[str] = [
        "---",
        "type: console",
        f"updated_at: {updated_at}",
        "---",
        "",
        "# 控制台与速览",
        "",
        "## 快捷操作",
        f"- [打开工作台面板]({WORKBENCH_BASE_URL}/)",
        f"- [抓取今日热点]({WORKBENCH_BASE_URL}/api/trigger/sync)",
        f"- [切换剪贴板监测]({WORKBENCH_BASE_URL}/api/trigger/toggle-clipboard)",
        f"- [切换伴随同看]({WORKBENCH_BASE_URL}/api/trigger/toggle-companion)",
        "",
        "## 知识领域",
        " · ".join(f"[[{domain}]]" for domain in DOMAINS),
        "",
        "## 个人超级技能库 (Skill Hub)",
        "- [[01-精选技能库]]：独立技能卡片与即插即用 Prompt / 脚本",
        "- [[02-即插即用工作流]]：多步骤实操工作流",
        "- [[03-项目反哺任务池]]：项目具体落地待办清单",
        "",
        "## 项目孵化池",
    ]

    if projects:
        for proj in projects:
            summary = proj.get("idea_summary") or "暂无简介"
            lines.append(
                f"- [[{proj['name']}]]（已挂载 {proj['entry_count']} 条）— {summary}"
            )
    else:
        lines.append("- 暂无项目")

    lines.extend(["", "## 最新捕获速览", ""])
    if entries:
        lines.append("| 时间 | 领域 | 阶段 | 标题 | 一句话本质 | 关联项目 |")
        lines.append("|---|---|---|---|---|---|")
        for entry in entries[:30]:
            proj_cell = f"[[{entry['matched_project']}]]" if entry.get("matched_project") else "-"
            domain_cell = f"[[{entry['domain']}]]"
            title_cell = _escape_table_cell(entry.get("title", ""), limit=42)
            essence_cell = _escape_table_cell(entry.get("one_line_essence", ""), limit=64)
            lines.append(
                f"| {entry.get('created_at', '')} | {domain_cell} | {entry.get('ladder_level', '')} "
                f"| {title_cell} | {essence_cell} | {proj_cell} |"
            )
    else:
        lines.append("暂无记录。点击上方「抓取今日热点」或复制链接自动归档。")

    _atomic_write_text(vault_root / CONSOLE_FILENAME, "\n".join(lines) + "\n")


def _ensure_project_exists_locked(
    vault_root: Path, data_dir: Path, name: str, idea_summary: str
) -> dict[str, Any]:
    safe_name = _safe_project_name(name)
    projects_dir = vault_root / PROJECTS_DIRNAME
    projects_dir.mkdir(parents=True, exist_ok=True)
    md_path = projects_dir / f"{safe_name}.md"
    rel_path = f"{PROJECTS_DIRNAME}/{safe_name}.md"
    now = now_timestamp()

    projects = _reconcile_projects_locked(vault_root, data_dir)
    existing = next((p for p in projects if p["name"] == safe_name), None)

    if not md_path.exists():
        _atomic_write_text(md_path, _project_template(safe_name, idea_summary, now))

    if existing is None:
        record = ProjectIdea(
            name=safe_name,
            idea_summary=idea_summary.strip() or _extract_project_summary(md_path),
            file_path=rel_path,
            created_at=now,
            updated_at=now,
        ).model_dump()
        projects.append(record)
        _write_json_list(data_dir / "projects.json", projects)
        return record

    if idea_summary.strip() and not existing.get("idea_summary"):
        existing["idea_summary"] = idea_summary.strip()
        existing["updated_at"] = now
        _write_json_list(data_dir / "projects.json", projects)
    return existing


def ensure_vault_initialized(vault_root: Path, data_dir: Path) -> None:
    """Ensure the strict 5-file + 1-folder minimal Obsidian layout and JSON indices exist."""
    vault_root = Path(vault_root)
    data_dir = Path(data_dir)
    with _VAULT_LOCK:
        vault_root.mkdir(parents=True, exist_ok=True)
        data_dir.mkdir(parents=True, exist_ok=True)
        ensure_skill_directories(vault_root)

        for domain, filename in DOMAIN_FILES.items():
            target = vault_root / filename
            if not target.exists():
                _atomic_write_text(target, _domain_template(domain))

        projects_dir = vault_root / PROJECTS_DIRNAME
        projects_dir.mkdir(parents=True, exist_ok=True)
        if not list(projects_dir.glob("*.md")):
            _ensure_project_exists_locked(
                vault_root, data_dir, DEFAULT_PROJECT_NAME, DEFAULT_PROJECT_SUMMARY
            )
        else:
            _reconcile_projects_locked(vault_root, data_dir)

        entries_json = data_dir / "entries.json"
        if not entries_json.exists():
            _write_json_list(entries_json, [])

        console_path = vault_root / CONSOLE_FILENAME
        if not console_path.exists():
            _render_console_locked(vault_root, data_dir)


def _format_domain_entry(entry: KnowledgeEntry) -> str:
    meta_parts = [f"**来源**：{entry.source}", f"**阶段**：{entry.ladder_level}"]
    if entry.matched_project:
        meta_parts.append(f"**关联项目**：[[{entry.matched_project}]]")
    if entry.url:
        meta_parts.append(f"[原文链接]({entry.url})")
    insight_lines = "\n".join(
        f"> {line}" if line.strip() else ">"
        for line in entry.deep_insight.strip().splitlines()
    )
    extra_lines: list[str] = []
    extra_lines.extend(_format_skill_lines(entry))
    if entry.actionable_steps:
        extra_lines.append("- **实操步骤**：")
        extra_lines.extend(f"  {idx}. {step}" for idx, step in enumerate(entry.actionable_steps, 1))
    if entry.project_optimizations:
        extra_lines.append(f"- **项目优化（[[{entry.matched_project}]]）**：")
        extra_lines.extend(f"  - {opt}" for opt in entry.project_optimizations)
    if entry.blender_script.strip():
        extra_lines.append("- **Blender 脚本**：")
        extra_lines.append("  ```python")
        extra_lines.extend(f"  {line}" for line in entry.blender_script.strip().splitlines())
        extra_lines.append("  ```")
    extra_lines.extend(_format_concept_lines(entry))
    extra_block = ("\n" + "\n".join(extra_lines) + "\n") if extra_lines else "\n"
    return (
        f"<!-- entry-id:{entry.id} -->\n"
        f"### [{entry.created_at}] {entry.title}\n"
        f"- {' · '.join(meta_parts)}\n"
        f"- **一句话本质**：{entry.one_line_essence}\n"
        f"- **我可以怎么用**：{entry.how_to_apply}{extra_block}\n"
        f"> [!note]- 深度认知\n"
        f"{insight_lines}\n\n"
        f"---\n"
    )


def _prepend_to_domain_file_locked(vault_root: Path, entry: KnowledgeEntry) -> Path:
    domain_path = vault_root / DOMAIN_FILES[entry.domain]
    if not domain_path.exists():
        _atomic_write_text(domain_path, _domain_template(entry.domain))

    content = domain_path.read_text(encoding="utf-8")
    id_marker = f"<!-- entry-id:{entry.id} -->"
    if id_marker in content:
        return domain_path

    block = _format_domain_entry(entry)
    if ENTRIES_MARKER in content:
        head, tail = content.split(ENTRIES_MARKER, 1)
        new_content = f"{head}{ENTRIES_MARKER}\n\n{block}\n{tail.lstrip()}"
    else:
        new_content = f"{content.rstrip()}\n\n{ENTRIES_MARKER}\n\n{block}"
    _atomic_write_text(domain_path, new_content)
    return domain_path


def _append_to_project_file_locked(
    vault_root: Path, data_dir: Path, entry: KnowledgeEntry
) -> Path | None:
    if not entry.matched_project:
        return None
    safe_name = _safe_project_name(entry.matched_project)
    _ensure_project_exists_locked(vault_root, data_dir, safe_name, "")
    proj_path = vault_root / PROJECTS_DIRNAME / f"{safe_name}.md"
    content = proj_path.read_text(encoding="utf-8")

    id_marker = f"<!-- entry-id:{entry.id} -->"
    if id_marker in content:
        return proj_path

    item_lines = [
        id_marker,
        f"- **[{entry.created_at}] {entry.title}**（来源：{entry.source} · 领域：[[{entry.domain}]]）",
        f"  - 核心结论：{entry.one_line_essence}",
        f"  - 怎么用：{entry.how_to_apply}",
    ]
    if entry.actionable_steps:
        item_lines.append("  - 实操步骤：")
        item_lines.extend(f"    {idx}. {step}" for idx, step in enumerate(entry.actionable_steps, 1))
    if entry.project_optimizations and entry.matched_project:
        item_lines.append(f"  - 项目优化（[[{entry.matched_project}]]）：")
        item_lines.extend(f"    - {opt}" for opt in entry.project_optimizations)
    if entry.url:
        item_lines.append(f"  - 出处：{entry.url}")
    item_block = "\n".join(item_lines)

    heading = LADDER_HEADINGS[entry.ladder_level]
    lines = content.splitlines()
    heading_idx = next((i for i, line in enumerate(lines) if line.strip() == heading), None)

    if heading_idx is None:
        new_content = f"{content.rstrip()}\n\n{heading}\n\n{item_block}\n"
    else:
        next_heading_idx = next(
            (
                i
                for i in range(heading_idx + 1, len(lines))
                if lines[i].startswith("## ")
            ),
            len(lines),
        )
        section_body = lines[heading_idx + 1 : next_heading_idx]
        while section_body and not section_body[-1].strip():
            section_body.pop()
        updated_section = [*section_body, item_block]
        if next_heading_idx < len(lines):
            updated_section.append("")
        new_lines = [
            *lines[: heading_idx + 1],
            *([] if updated_section and not updated_section[0].strip() else [""]),
            *updated_section,
            *lines[next_heading_idx:],
        ]
        new_content = "\n".join(new_lines).rstrip() + "\n"

    _atomic_write_text(proj_path, new_content)

    projects = _read_json_list(data_dir / "projects.json")
    now = now_timestamp()
    for proj in projects:
        if proj.get("name") == safe_name:
            proj["updated_at"] = now
    _write_json_list(data_dir / "projects.json", projects)
    return proj_path


def save_knowledge_entry(
    vault_root: Path, data_dir: Path, entry: KnowledgeEntry | dict[str, Any]
) -> dict[str, Any]:
    """Save a KnowledgeEntry into its single domain file, optional project ladder, JSON index, and console."""
    vault_root = Path(vault_root)
    data_dir = Path(data_dir)
    model = entry if isinstance(entry, KnowledgeEntry) else KnowledgeEntry.model_validate(entry)

    with _VAULT_LOCK:
        ensure_vault_initialized(vault_root, data_dir)
        if model.matched_project:
            model = model.model_copy(
                update={"matched_project": _safe_project_name(model.matched_project)}
            )

        entries_path = data_dir / "entries.json"
        entries = _read_json_list(entries_path)
        for existing in entries:
            if existing.get("id") == model.id:
                return existing

        entry_dict = model.model_dump()
        _prepend_to_domain_file_locked(vault_root, model)
        _append_to_project_file_locked(vault_root, data_dir, model)
        save_skill_card(vault_root, model)
        entries.insert(0, entry_dict)
        _write_json_list(entries_path, entries)
        _render_console_locked(vault_root, data_dir)
        return entry_dict


def list_knowledge_entries(
    data_dir: Path, domain: str | None = None, project: str | None = None
) -> list[dict[str, Any]]:
    """Return structured knowledge entries newest-first, optionally filtered by domain and/or project."""
    entries = _read_json_list(Path(data_dir) / "entries.json")
    if domain:
        canonical = normalize_domain(domain)
        entries = [e for e in entries if e.get("domain") == canonical]
    if project:
        target = project.strip()
        entries = [e for e in entries if e.get("matched_project") == target]
    return entries


def create_project_idea(
    vault_root: Path, data_dir: Path, name: str, idea_summary: str
) -> dict[str, Any]:
    """Create a project incubator note under 05-项目孵化池/ with L1/L2/L3 sections and register it."""
    vault_root = Path(vault_root)
    data_dir = Path(data_dir)
    with _VAULT_LOCK:
        ensure_vault_initialized(vault_root, data_dir)
        record = _ensure_project_exists_locked(vault_root, data_dir, name, idea_summary)
        _render_console_locked(vault_root, data_dir)
        entries = _read_json_list(data_dir / "entries.json")
        return _build_project_views([record], entries)[0]


def list_projects(vault_root: Path, data_dir: Path) -> list[dict[str, Any]]:
    """Return all incubator projects along with their grouped L1/L2/L3 linked entries."""
    vault_root = Path(vault_root)
    data_dir = Path(data_dir)
    with _VAULT_LOCK:
        ensure_vault_initialized(vault_root, data_dir)
        projects = _reconcile_projects_locked(vault_root, data_dir)
        entries = _read_json_list(data_dir / "entries.json")
        return _build_project_views(projects, entries)
