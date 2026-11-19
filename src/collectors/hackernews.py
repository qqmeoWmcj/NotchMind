from __future__ import annotations

import asyncio
import httpx

from src.collectors.base import is_ai_related
from src.models import RawItem

HN_TOP_URL = "https://hacker-news.firebaseio.com/v0/topstories.json"
HN_ITEM_URL = "https://hacker-news.firebaseio.com/v0/item/{item_id}.json"


async def fetch_hackernews_ai(limit: int = 12) -> list[RawItem]:
    async with httpx.AsyncClient(timeout=12.0) as client:
        resp = await client.get(HN_TOP_URL)
        resp.raise_for_status()
        top_ids = resp.json()[:45]

        async def _get_item(item_id: int) -> dict | None:
            try:
                r = await client.get(HN_ITEM_URL.format(item_id=item_id))
                return r.json() if r.status_code == 200 else None
            except Exception:  # noqa: BLE001
                return None

        raw_items = await asyncio.gather(*(_get_item(i) for i in top_ids))

    results: list[RawItem] = []
    for data in raw_items:
        if not data or data.get("type") != "story":
            continue
        title = data.get("title", "")
        if not is_ai_related(title):
            continue
        url = data.get("url") or f"https://news.ycombinator.com/item?id={data.get('id')}"
        results.append(
            RawItem(
                source="HackerNews",
                title=title,
                url=url,
                summary=f"HN Score: {data.get('score', 0)}, Comments: {data.get('descendants', 0)}",
                score=int(data.get("score", 0)),
            )
        )
        if len(results) >= limit:
            break
    return results
