from __future__ import annotations

import argparse
import asyncio
import os
from datetime import datetime
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

from src.agent import GeminiHotspotAgent, switch_default_model
from src.collectors import collect_all_sources
from src.exporters import (
    ensure_vault_initialized,
    export_notebooklm_source,
    list_projects,
    save_knowledge_entry,
)
from src.memory import TopicMemory
from src.models import KnowledgeEntry

PROJECT_ROOT = Path(__file__).resolve().parent.parent
console = Console()


def resolve_vault_path() -> Path:
    custom = os.getenv("OBSIDIAN_VAULT_PATH", "").strip()
    if custom:
        return Path(custom).expanduser().resolve()
    return PROJECT_ROOT / "vault"


def resolve_data_dir() -> Path:
    return PROJECT_ROOT / "data"


def _render_raw_table(items, limit: int = 12) -> None:
    table = Table(title=f"抓取到的未处理 AI 热点（展示前 {min(len(items), limit)} 条 / 共 {len(items)} 条）")
    table.add_column("#", justify="right", style="cyan")
    table.add_column("来源", style="magenta")
    table.add_column("热度", justify="right")
    table.add_column("标题", style="white")
    for idx, item in enumerate(items[:limit], start=1):
        table.add_row(str(idx), item.source, str(item.score), item.title[:72])
    console.print(table)


async def run_pipeline(
    top_k: int = 3,
    dry_run: bool = False,
    model: str | None = None,
    vault_root: Path | None = None,
    data_dir: Path | None = None,
    quiet: bool = False,
) -> dict[str, Any]:
    load_dotenv(PROJECT_ROOT / ".env", override=False)
    run_date = datetime.now().strftime("%Y-%m-%d")
    resolved_vault = Path(vault_root) if vault_root else resolve_vault_path()
    resolved_data = Path(data_dir) if data_dir else resolve_data_dir()
    ensure_vault_initialized(resolved_vault, resolved_data)
    memory = TopicMemory(resolved_data / "memory.db")

    if not quiet:
        console.print(f"[bold cyan]▶ 步骤 1/4：抓取公开 AI 热点源（{run_date}）[/bold cyan]")
    raw_items = await collect_all_sources(console=None if quiet else console)
    unseen = memory.filter_unseen(raw_items)
    if not quiet:
        console.print(
            f"  共抓取 {len(raw_items)} 条，经 SQLite 长期记忆去重后剩 [bold]{len(unseen)}[/bold] 条新热点。"
        )

    if not unseen:
        if not quiet:
            console.print("[yellow]今天没有新的未处理热点，已退出。[/yellow]")
        return {"status": "empty", "fetched": len(raw_items), "unseen": 0, "saved": 0, "entries": []}

    if not quiet:
        _render_raw_table(unseen)

    if dry_run:
        if not quiet:
            console.print("[green]✓ --dry-run 模式完成（未调用 Gemini API，未写入记忆库）。[/green]")
        return {
            "status": "dry_run",
            "fetched": len(raw_items),
            "unseen": len(unseen),
            "saved": 0,
            "entries": [],
        }

    if not quiet:
        console.print(f"\n[bold cyan]▶ 步骤 2/4：调用 Gemini Agent 筛选 Top {top_k} 热点[/bold cyan]")
    agent = GeminiHotspotAgent(model=model)
    if not quiet:
        console.print(f"  使用模型：[bold]{agent.model}[/bold]")
    selected = agent.select_top_items(unseen, top_k=top_k)

    project_names = [p["name"] for p in list_projects(resolved_vault, resolved_data)]
    if not quiet:
        console.print("\n[bold cyan]▶ 步骤 3/4：四领域归类、实操提炼与项目阶梯匹配[/bold cyan]")
    analyzed: list[KnowledgeEntry] = []
    succeeded_items = []
    for idx, item in enumerate(selected, start=1):
        if not quiet:
            console.print(f"  [{idx}/{len(selected)}] 正在拆解：{item.title[:65]}...")
        try:
            analyzed.append(agent.analyze_item(item, project_names=project_names))
            succeeded_items.append(item)
        except Exception as exc:  # noqa: BLE001
            if not quiet:
                console.print(f"  [yellow]![/yellow] 该条拆解失败（已跳过，不影响其余条目）— {exc}")

    if not analyzed:
        if not quiet:
            console.print("[red]✗ 本次所有热点均未能成功拆解，请稍后重试。[/red]")
        return {
            "status": "failed",
            "fetched": len(raw_items),
            "unseen": len(unseen),
            "saved": 0,
            "entries": [],
            "model": agent.model,
        }

    if not quiet:
        console.print("\n[bold cyan]▶ 步骤 4/4：写入单文件 Obsidian 知识库与 NotebookLM 源文档[/bold cyan]")
    saved_entries = [
        save_knowledge_entry(resolved_vault, resolved_data, entry) for entry in analyzed
    ]
    nlm_path = export_notebooklm_source(resolved_data / "notebooklm", run_date, analyzed)
    memory.mark_seen(succeeded_items)

    if not quiet:
        console.print(f"  [green]✓[/green] 已归档 {len(saved_entries)} 条到 {resolved_vault}")
        console.print(f"  [green]✓[/green] 控制台速览：{resolved_vault / '00-控制台与速览.md'}")
        console.print(f"  [green]✓[/green] NotebookLM 源文档：{nlm_path}")

    return {
        "status": "ok",
        "fetched": len(raw_items),
        "unseen": len(unseen),
        "saved": len(saved_entries),
        "entries": saved_entries,
        "notebooklm_path": str(nlm_path),
        "model": agent.model,
    }


def sync_hotspots_once(
    top_k: int = 3,
    dry_run: bool = False,
    model: str | None = None,
    vault_root: Path | None = None,
    data_dir: Path | None = None,
) -> dict[str, Any]:
    """Synchronous entry point for background services and the workbench HTTP server."""
    return asyncio.run(
        run_pipeline(
            top_k=top_k,
            dry_run=dry_run,
            model=model,
            vault_root=vault_root,
            data_dir=data_dir,
            quiet=True,
        )
    )


def main() -> None:
    parser = argparse.ArgumentParser(description="AI 热点个人创作 Agent CLI")
    sub = parser.add_subparsers(dest="command", required=True)
    run_cmd = sub.add_parser("run", help="抓取热点并写入单文件 Obsidian 知识库与 NotebookLM 源文档")
    run_cmd.add_argument("--top", type=int, default=int(os.getenv("TOP_K_TOPICS", "3")), help="精选热点数量")
    run_cmd.add_argument("--model", type=str, default=None, help="临时指定模型或别名（如 3.8f / 4h / 4a）")
    run_cmd.add_argument("--dry-run", action="store_true", help="仅测试抓取与去重，不调用大模型")

    switch_cmd = sub.add_parser("switch", help="切换默认 Gemini 模型（支持 3.8f / 4h / 4a）")
    switch_cmd.add_argument("model", type=str, help="模型别名或完整名称，例如 3.8f 或 4h")

    args = parser.parse_args()
    if args.command == "run":
        asyncio.run(run_pipeline(top_k=args.top, dry_run=args.dry_run, model=args.model))
    elif args.command == "switch":
        resolved = switch_default_model(args.model)
        console.print(f"[green]✓[/green] 默认模型已切换为：[bold]{resolved}[/bold]（已写入 .env）")


if __name__ == "__main__":
    main()
