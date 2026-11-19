from __future__ import annotations

import hashlib
from pydantic import BaseModel, Field


class RawItem(BaseModel):
    """Normalized hotspot item fetched from any public source."""

    source: str
    title: str
    url: str
    summary: str = ""
    score: int = 0
    published_at: str = ""

    @property
    def fingerprint(self) -> str:
        raw = f"{self.url.strip().lower()}|{self.title.strip().lower()}"
        return hashlib.sha256(raw.encode("utf-8")).hexdigest()[:24]


class TopicSelection(BaseModel):
    """Stage-1 selection output from Gemini."""

    selected_indices: list[int] = Field(
        description="0-based indices of the top high-value AI hotspot items."
    )
    reasons: list[str] = Field(
        description="One-sentence reason for each selected item."
    )


class ContentDrafts(BaseModel):
    """Multi-platform content drafts generated for a single hotspot."""

    xiaohongshu_titles: list[str] = Field(description="3 catchy, non-clickbait Xiaohongshu title options.")
    xiaohongshu_cover_copy: str = Field(description="Short bold cover text for Xiaohongshu image.")
    xiaohongshu_body: str = Field(description="Structured Xiaohongshu post body with clear sections and hashtags.")
    video_hook_3s: str = Field(description="Opening 3-second hook for short video / talking head.")
    video_script: str = Field(description="Structured spoken script with [画面/PPT提示] cues.")
    long_article_outline: str = Field(description="Deep-dive article outline for WeChat/Zhihu with core arguments.")


class AnalyzedTopic(BaseModel):
    """Stage-2 deep analysis and multi-platform drafts for one hotspot."""

    short_slug: str = Field(description="Concise Chinese/English filename-safe short title (<=18 chars, no slashes).")
    title: str = Field(description="Refined Chinese headline.")
    source: str
    url: str
    heat_score: int = Field(ge=1, le=10, description="Creation value & heat score from 1 to 10.")
    one_line_essence: str = Field(description="One-sentence essence of what actually happened.")
    why_now: str = Field(description="Why this matters right now in the AI industry.")
    deep_insight: str = Field(description="Anti-consensus or high-signal industry insight (no generic AI fluff).")
    tags: list[str] = Field(default_factory=list)
    drafts: ContentDrafts
