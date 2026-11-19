from __future__ import annotations

import asyncio
import feedparser
import httpx

from src.models import RawItem

DEFAULT_RSS_FEEDS: list[tuple[str, str]] = [
    ("OpenAI Blog", "https://openai.com/news/rss.xml"),
    ("Google DeepMind", "https://deepmind.google/blog/rss.xml"),
    ("Simon Willison", "https://simonwillison.net/atom/everything/"),
]


async def _fetch_single_feed(
    client: httpx.AsyncClient, name: str, url: str, per_feed: int = 4
) -> list[RawItem]:
    try:
        resp = await client.get(url, follow_redirects=True)
        resp.raise_for_status()
        parsed = feedparser.parse(resp.text)
    except Exception:  # noqa: BLE001
        return []

    items: list[RawItem] = []
    for entry in parsed.entries[:per_feed]:
        title = getattr(entry, "title", "").strip()
        link = getattr(entry, "link", "").strip()
        summary = getattr(entry, "summary", "").replace("\n", " ")[:220]
        if not title or not link:
            continue
        items.append(
            RawItem(
                source=f"RSS:{name}",
                title=title,
                url=link,
                summary=summary,
                published_at=getattr(entry, "published", ""),
            )
        )
    return items


async def fetch_rss_ai(per_feed: int = 4) -> list[RawItem]:
    async with httpx.AsyncClient(timeout=12.0, headers={"User-Agent": "ai-hotspot-creator/0.1"}) as client:
        chunks = await asyncio.gather(
            *(_fetch_single_feed(client, name, url, per_feed) for name, url in DEFAULT_RSS_FEEDS)
        )
    merged: list[RawItem] = []
    for chunk in chunks:
        merged.extend(chunk)
    return merged
