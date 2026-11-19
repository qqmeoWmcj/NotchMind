from __future__ import annotations

from datetime import datetime, timedelta, timezone
import httpx

from src.models import RawItem

GITHUB_SEARCH_URL = "https://api.github.com/search/repositories"


async def fetch_github_ai(limit: int = 10) -> list[RawItem]:
    since = (datetime.now(timezone.utc) - timedelta(days=14)).strftime("%Y-%m-%d")
    params = {
        "q": f"(ai OR llm OR agent OR mcp) created:>{since}",
        "sort": "stars",
        "order": "desc",
        "per_page": limit,
    }
    headers = {
        "Accept": "application/vnd.github+json",
        "User-Agent": "ai-hotspot-creator/0.1",
    }
    async with httpx.AsyncClient(timeout=12.0, headers=headers) as client:
        resp = await client.get(GITHUB_SEARCH_URL, params=params)
        resp.raise_for_status()
        repos = resp.json().get("items", [])

    items: list[RawItem] = []
    for repo in repos:
        desc = repo.get("description") or ""
        stars = int(repo.get("stargazers_count", 0))
        items.append(
            RawItem(
                source="GitHub",
                title=f"{repo.get('full_name', '')}: {desc[:80]}".strip(": "),
                url=repo.get("html_url", ""),
                summary=f"Stars: {stars} | Language: {repo.get('language') or 'N/A'} | {desc}",
                score=stars,
                published_at=repo.get("created_at", ""),
            )
        )
    return items
