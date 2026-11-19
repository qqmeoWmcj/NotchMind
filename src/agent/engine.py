from __future__ import annotations

import os
from google import genai
from google.genai import types

from src.agent.prompts import (
    SYSTEM_INSTRUCTION,
    build_analysis_prompt,
    build_selection_prompt,
)
from src.models import AnalyzedTopic, RawItem, TopicSelection


class GeminiHotspotAgent:
    """Two-stage reliable Gemini agent: (1) select top hotspots, (2) analyze & draft."""

    def __init__(self, api_key: str | None = None, model: str | None = None) -> None:
        resolved_key = api_key or os.getenv("GEMINI_API_KEY", "").strip()
        if not resolved_key or resolved_key == "your_gemini_api_key_here":
            raise ValueError(
                "未配置有效的 GEMINI_API_KEY。请在项目根目录的 .env 文件中填入你的 Gemini API Key。"
            )
        self.model = (model or os.getenv("GEMINI_MODEL", "gemini-4-argon")).strip()
        self.client = genai.Client(api_key=resolved_key)

    def select_top_items(self, items: list[RawItem], top_k: int = 3) -> list[RawItem]:
        if len(items) <= top_k:
            return items
        lines = [
            f"[{idx}] ({item.source} | score={item.score}) {item.title} — {item.summary[:120]}"
            for idx, item in enumerate(items[:40])
        ]
        response = self.client.models.generate_content(
            model=self.model,
            contents=build_selection_prompt("\n".join(lines), top_k),
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_INSTRUCTION,
                response_mime_type="application/json",
                response_schema=TopicSelection,
                temperature=0.3,
            ),
        )
        selection = TopicSelection.model_validate_json(response.text)
        chosen: list[RawItem] = []
        seen: set[int] = set()
        for idx in selection.selected_indices:
            if 0 <= idx < len(items) and idx not in seen:
                seen.add(idx)
                chosen.append(items[idx])
        return chosen[:top_k] if chosen else items[:top_k]

    def analyze_item(self, item: RawItem) -> AnalyzedTopic:
        response = self.client.models.generate_content(
            model=self.model,
            contents=build_analysis_prompt(item.source, item.title, item.url, item.summary),
            config=types.GenerateContentConfig(
                system_instruction=SYSTEM_INSTRUCTION,
                response_mime_type="application/json",
                response_schema=AnalyzedTopic,
                temperature=0.6,
            ),
        )
        topic = AnalyzedTopic.model_validate_json(response.text)
        topic.source = item.source
        topic.url = item.url
        return topic
