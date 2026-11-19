from __future__ import annotations

import asyncio
from typing import Awaitable, Callable

from rich.console import Console

from src.models import RawItem

CollectorFn = Callable[[], Awaitable[list[RawItem]]]

AI_KEYWORDS = (
    "ai", "llm", "agent", "gpt", "claude", "gemini", "deepseek", "qwen",
    "openai", "anthropic", "model", "rag", "mcp", "diffusion", "inference",
    "transformer", "reasoning", "multimodal", "vibe", "cursor", "copilot",
)


def is_ai_related(text: str) -> bool:
    lower = text.lower()
    return any(kw in lower for kw in AI_KEYWORDS)


async def collect_all_sources(console: Console | None = None) -> list[RawItem]:
    """Run all public hotspot collectors concurrently with per-source fault isolation."""
    from src.collectors.github_trending import fetch_github_ai
    from src.collectors.hackernews import fetch_hackernews_ai
    from src.collectors.hf_papers import fetch_hf_daily_papers
    from src.collectors.rss_feeds import fetch_rss_ai

    sources: list[tuple[str, CollectorFn]] = [
        ("HackerNews", fetch_hackernews_ai),
        ("GitHub", fetch_github_ai),
        ("HuggingFace Papers", fetch_hf_daily_papers),
        ("RSS Feeds", fetch_rss_ai),
    ]

    async def _run_one(name: str, fn: CollectorFn) -> list[RawItem]:
        try:
            items = await fn()
            if console:
                console.print(f"  [green]✓[/green] {name}: 获取 {len(items)} 条")
            return items
        except Exception as exc:  # noqa: BLE001
            if console:
                console.print(f"  [yellow]![/yellow] {name}: 抓取失败（已跳过）— {exc}")
            return []

    results = await asyncio.gather(*(_run_one(n, f) for n, f in sources))
    merged: list[RawItem] = []
    for chunk in results:
        merged.extend(chunk)
    return merged
