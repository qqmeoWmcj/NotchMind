from __future__ import annotations

import httpx

from src.models import RawItem

HF_DAILY_PAPERS_URL = "https://huggingface.co/api/daily_papers"


async def fetch_hf_daily_papers(limit: int = 8) -> list[RawItem]:
    async with httpx.AsyncClient(timeout=12.0) as client:
        resp = await client.get(HF_DAILY_PAPERS_URL)
        resp.raise_for_status()
        papers = resp.json()[:limit]

    items: list[RawItem] = []
    for entry in papers:
        paper = entry.get("paper", {})
        paper_id = paper.get("id", "")
        title = paper.get("title") or entry.get("title", "")
        summary = (paper.get("summary") or "").replace("\n", " ")[:240]
        upvotes = int(paper.get("upvotes", 0))
        items.append(
            RawItem(
                source="HuggingFace Papers",
                title=title,
                url=f"https://huggingface.co/papers/{paper_id}" if paper_id else "https://huggingface.co/papers",
                summary=f"Upvotes: {upvotes} | {summary}",
                score=upvotes,
                published_at=entry.get("publishedAt", ""),
            )
        )
    return items
