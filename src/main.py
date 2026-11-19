from __future__ import annotations

import argparse
import asyncio
import os
from datetime import datetime
from pathlib import Path

from dotenv import load_dotenv
from rich.console import Console
from rich.table import Table

from src.agent import GeminiHotspotAgent
from src.collectors import collect_all_sources
from src.exporters import export_notebooklm_source, export_to_obsidian
from src.memory import TopicMemory
from src.models import AnalyzedTopic

PROJECT_ROOT = Path(__file__).resolve().parent.parent
console = Console()


def _resolve_vault_path() -> Path:
    custom = os.getenv("OBSIDIAN_VAULT_PATH", "").strip()
    if custom:
        return Path(custom).expanduser().resolve()
    return PROJECT_ROOT / "vault"


def _render_raw_table(items, limit: int = 12) -> None:
    table = Table(title=f"抓取到的未处理 AI 热点（展示前 {min(len(items), limit)} 条 / 共 {len(items)} 条）")
    table.add_column("#", justify="right", style="cyan")
    table.add_column("来源", style="magenta")
    table.add_column("热度", justify="right")
    table.add_column("标题", style="white")
    for idx, item in enumerate(items[:limit], start=1):
        table.add_row(str(idx), item.source, str(item.score), item.title[:72])
    console.print(table)


async def run_pipeline(top_k: int, dry_run: bool) -> None:
    load_dotenv(PROJECT_ROOT / ".env")
    run_date = datetime.now().strftime("%Y-%m-%d")
    vault_root = _resolve_vault_path()
    memory = TopicMemory(PROJECT_ROOT / "data" / "memory.db")

    console.print(f"[bold cyan]▶ 步骤 1/4：抓取公开 AI 热点源（{run_date}）[/bold cyan]")
    raw_items = await collect_all_sources(console=console)
    unseen = memory.filter_unseen(raw_items)
    console.print(f"  共抓取 {len(raw_items)} 条，经 SQLite 长期记忆去重后剩 [bold]{len(unseen)}[/bold] 条新热点。")

    if not unseen:
        console.print("[yellow]今天没有新的未处理热点，已退出。[/yellow]")
        return

    _render_raw_table(unseen)

    if dry_run:
        console.print("[green]✓ --dry-run 模式完成（未调用 Gemini API，未写入记忆库）。[/green]")
        return

    console.print(f"\n[bold cyan]▶ 步骤 2/4：调用 Gemini Agent 筛选 Top {top_k} 热点[/bold cyan]")
    agent = GeminiHotspotAgent()
    console.print(f"  使用模型：[bold]{agent.model}[/bold]")
    selected = agent.select_top_items(unseen, top_k=top_k)

    console.print(f"\n[bold cyan]▶ 步骤 3/4：深度认知提炼与三平台草稿生成[/bold cyan]")
    analyzed: list[AnalyzedTopic] = []
    for idx, item in enumerate(selected, start=1):
        console.print(f"  [{idx}/{len(selected)}] 正在拆解：{item.title[:65]}...")
        analyzed.append(agent.analyze_item(item))

    console.print(f"\n[bold cyan]▶ 步骤 4/4：写入 Obsidian 知识库与 NotebookLM 源文档[/bold cyan]")
    obs_paths = export_to_obsidian(vault_root, run_date, analyzed)
    nlm_path = export_notebooklm_source(vault_root, run_date, analyzed)
    memory.mark_seen(selected)

    console.print(f"  [green]✓[/green] Obsidian 每日索引：{obs_paths['moc']}")
    console.print(f"  [green]✓[/green] Obsidian 全局总览：{obs_paths['dashboard']}")
    console.print(f"  [green]✓[/green] NotebookLM 源文档：{nlm_path}")


def main() -> None:
    parser = argparse.ArgumentParser(description="AI 热点个人创作 Agent CLI")
    sub = parser.add_subparsers(dest="command", required=True)
    run_cmd = sub.add_parser("run", help="抓取热点并生成 Obsidian 笔记与 NotebookLM 源文档")
    run_cmd.add_argument("--top", type=int, default=int(os.getenv("TOP_K_TOPICS", "3")), help="精选热点数量")
    run_cmd.add_argument("--dry-run", action="store_true", help="仅测试抓取与去重，不调用大模型")

    args = parser.parse_args()
    if args.command == "run":
        asyncio.run(run_pipeline(top_k=args.top, dry_run=args.dry_run))


if __name__ == "__main__":
    main()
