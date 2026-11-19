from __future__ import annotations

import hashlib
from datetime import datetime
from typing import Literal

from pydantic import BaseModel, Field, field_validator, model_validator

DOMAIN_FILES: dict[str, str] = {
    "01-LLM与新模型": "01-LLM与新模型.md",
    "02-AI学习与教程": "02-AI学习与教程.md",
    "03-AI创作与3D工具": "03-AI创作与3D工具.md",
    "04-行业深度认知": "04-行业深度认知.md",
}

DOMAINS: tuple[str, ...] = tuple(DOMAIN_FILES.keys())

DomainType = Literal[
    "01-LLM与新模型",
    "02-AI学习与教程",
    "03-AI创作与3D工具",
    "04-行业深度认知",
]

LADDER_LEVELS: tuple[str, ...] = (
    "L1基础教程",
    "L2工具与AI联动",
    "L3一站式自动化",
)

LadderLevelType = Literal[
    "L1基础教程",
    "L2工具与AI联动",
    "L3一站式自动化",
]

LADDER_HEADINGS: dict[str, str] = {
    "L1基础教程": "## L1 基础教程与认知",
    "L2工具与AI联动": "## L2 工具与AI联动",
    "L3一站式自动化": "## L3 一站式自动化闭环",
}

_DOMAIN_ALIASES: dict[str, DomainType] = {
    "01": "01-LLM与新模型",
    "01-llm与新模型": "01-LLM与新模型",
    "llm与新模型": "01-LLM与新模型",
    "02": "02-AI学习与教程",
    "02-ai学习与教程": "02-AI学习与教程",
    "ai学习与教程": "02-AI学习与教程",
    "03": "03-AI创作与3D工具",
    "03-ai创作与3d工具": "03-AI创作与3D工具",
    "ai创作与3d工具": "03-AI创作与3D工具",
    "04": "04-行业深度认知",
    "04-行业深度认知": "04-行业深度认知",
    "行业深度认知": "04-行业深度认知",
}


def now_timestamp() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M")


def normalize_domain(value: str) -> DomainType:
    cleaned = str(value).strip()
    if cleaned in DOMAIN_FILES:
        return cleaned  # type: ignore[return-value]
    key = cleaned.lower().replace(" ", "")
    if key in _DOMAIN_ALIASES:
        return _DOMAIN_ALIASES[key]
    raise ValueError(f"Unsupported domain: {value!r}. Must be one of {DOMAINS}.")


def normalize_ladder_level(value: str) -> LadderLevelType:
    cleaned = str(value).strip().replace(" ", "")
    upper = cleaned.upper()
    if cleaned in LADDER_HEADINGS:
        return cleaned  # type: ignore[return-value]
    if upper.startswith("L1"):
        return "L1基础教程"
    if upper.startswith("L2"):
        return "L2工具与AI联动"
    if upper.startswith("L3"):
        return "L3一站式自动化"
    raise ValueError(f"Unsupported ladder_level: {value!r}. Must be one of {LADDER_LEVELS}.")


def _clean_optional_project(value: str | None) -> str | None:
    if value is None:
        return None
    cleaned = value.strip()
    if not cleaned or cleaned.lower() in {"none", "null", "n/a", "无", "不匹配", "无匹配"}:
        return None
    return cleaned


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


class KnowledgeExtraction(BaseModel):
    """Structured classification and insight output returned by Gemini."""

    title: str = Field(description="Refined, concrete Chinese headline (no clickbait).")
    domain: DomainType = Field(
        description="Exactly one of: 01-LLM与新模型, 02-AI学习与教程, 03-AI创作与3D工具, 04-行业深度认知."
    )
    ladder_level: LadderLevelType = Field(
        description="Exactly one of: L1基础教程, L2工具与AI联动, L3一站式自动化."
    )
    matched_project: str | None = Field(
        default=None,
        description="Optional matching project name from 05-项目孵化池/, or null if none fits.",
    )
    one_line_essence: str = Field(description="One-sentence core essence of what happened or what is taught.")
    how_to_apply: str = Field(description="Concrete, actionable guidance answering '我可以怎么用'.")
    deep_insight: str = Field(description="Sharp, high-signal insight or anti-consensus judgment (no AI fluff).")
    tags: list[str] = Field(default_factory=list, description="2 to 5 concise Chinese/English topic tags.")
    heat_score: int = Field(default=8, ge=1, le=10, description="Value & signal score from 1 to 10.")

    @field_validator("domain", mode="before")
    @classmethod
    def _validate_domain(cls, value: str) -> DomainType:
        return normalize_domain(value)

    @field_validator("ladder_level", mode="before")
    @classmethod
    def _validate_ladder(cls, value: str) -> LadderLevelType:
        return normalize_ladder_level(value)

    @field_validator("matched_project", mode="before")
    @classmethod
    def _validate_project(cls, value: str | None) -> str | None:
        return _clean_optional_project(value)


class KnowledgeEntry(BaseModel):
    """Unified knowledge entry persisted to Obsidian single-domain files and JSON index."""

    id: str = ""
    title: str
    source: str
    url: str = ""
    domain: DomainType
    ladder_level: LadderLevelType = "L1基础教程"
    matched_project: str | None = None
    one_line_essence: str
    how_to_apply: str
    deep_insight: str
    created_at: str = Field(default_factory=now_timestamp)
    tags: list[str] = Field(default_factory=list)
    heat_score: int = Field(default=8, ge=1, le=10)

    @field_validator("domain", mode="before")
    @classmethod
    def _validate_domain(cls, value: str) -> DomainType:
        return normalize_domain(value)

    @field_validator("ladder_level", mode="before")
    @classmethod
    def _validate_ladder(cls, value: str) -> LadderLevelType:
        return normalize_ladder_level(value)

    @field_validator("matched_project", mode="before")
    @classmethod
    def _validate_project(cls, value: str | None) -> str | None:
        return _clean_optional_project(value)

    @model_validator(mode="after")
    def _ensure_id(self) -> KnowledgeEntry:
        if not self.id:
            if self.url.strip():
                raw = f"{self.url.strip().lower()}|{self.title.strip().lower()}"
            else:
                raw = f"{self.source.strip().lower()}|{self.title.strip().lower()}|{self.one_line_essence.strip().lower()}"
            self.id = hashlib.sha256(raw.encode("utf-8")).hexdigest()[:16]
        return self


class ProjectIdea(BaseModel):
    """Project incubator record under 05-项目孵化池/."""

    name: str
    idea_summary: str
    file_path: str
    created_at: str = Field(default_factory=now_timestamp)
    updated_at: str = Field(default_factory=now_timestamp)
