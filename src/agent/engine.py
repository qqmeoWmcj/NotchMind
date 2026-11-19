from __future__ import annotations

import os
import time
from google import genai
from google.genai import errors, types

from src.agent.prompts import (
    SYSTEM_INSTRUCTION,
    build_analysis_prompt,
    build_selection_prompt,
)
from src.models import AnalyzedTopic, RawItem, TopicSelection


MODEL_ALIASES: dict[str, str] = {
    "3.8f": "gemini-3.8-flash",
    "4h": "gemini-4-hydrogen",
    "4a": "gemini-4-argon",
}


def resolve_model_name(name: str) -> str:
    key = name.strip().lower()
    return MODEL_ALIASES.get(key, name.strip())


class GeminiHotspotAgent:
    """Two-stage reliable Gemini agent: (1) select top hotspots, (2) analyze & draft."""

    def __init__(self, api_key: str | None = None, model: str | None = None) -> None:
        resolved_key = api_key or os.getenv("GEMINI_API_KEY", "").strip()
        if not resolved_key or resolved_key == "your_gemini_api_key_here":
            raise ValueError(
                "未配置有效的 GEMINI_API_KEY。请在项目根目录的 .env 文件中填入你的 Gemini API Key。"
            )
        raw_model = model or os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
        self.model = resolve_model_name(raw_model)
        self.client = genai.Client(api_key=resolved_key)

    def _generate_with_retry(self, contents: str, schema: type, temperature: float) -> str:
        last_err: Exception | None = None
        for attempt in range(3):
            try:
                response = self.client.models.generate_content(
                    model=self.model,
                    contents=contents,
                    config=types.GenerateContentConfig(
                        system_instruction=SYSTEM_INSTRUCTION,
                        response_mime_type="application/json",
                        response_schema=schema,
                        temperature=temperature,
                    ),
                )
                return response.text
            except errors.ServerError as exc:
                last_err = exc
                if attempt < 2:
                    time.sleep(2 * (attempt + 1))
        assert last_err is not None
        raise last_err

    def select_top_items(self, items: list[RawItem], top_k: int = 3) -> list[RawItem]:
        if len(items) <= top_k:
            return items
        lines = [
            f"[{idx}] ({item.source} | score={item.score}) {item.title} — {item.summary[:120]}"
            for idx, item in enumerate(items[:40])
        ]
        raw_json = self._generate_with_retry(
            contents=build_selection_prompt("\n".join(lines), top_k),
            schema=TopicSelection,
            temperature=0.3,
        )
        selection = TopicSelection.model_validate_json(raw_json)
        chosen: list[RawItem] = []
        seen: set[int] = set()
        for idx in selection.selected_indices:
            if 0 <= idx < len(items) and idx not in seen:
                seen.add(idx)
                chosen.append(items[idx])
        return chosen[:top_k] if chosen else items[:top_k]

    def analyze_item(self, item: RawItem) -> AnalyzedTopic:
        raw_json = self._generate_with_retry(
            contents=build_analysis_prompt(item.source, item.title, item.url, item.summary),
            schema=AnalyzedTopic,
            temperature=0.6,
        )
        topic = AnalyzedTopic.model_validate_json(raw_json)
        topic.source = item.source
        topic.url = item.url
        return topic
