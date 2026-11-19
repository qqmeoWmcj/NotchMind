from __future__ import annotations

import mimetypes
import os
import time
from pathlib import Path
from typing import Any

from dotenv import load_dotenv
from google import genai
from google.genai import errors, types

from src.agent.prompts import (
    SYSTEM_INSTRUCTION,
    build_knowledge_prompt,
    build_selection_prompt,
)
from src.models import KnowledgeEntry, KnowledgeExtraction, RawItem, TopicSelection

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent

MODEL_ALIASES: dict[str, str] = {
    "3.8f": "gemini-3.8-flash",
    "4h": "gemini-4-hydrogen",
    "4a": "gemini-4-argon",
}

_REVERSE_ALIASES: dict[str, str] = {v: k for k, v in MODEL_ALIASES.items()}

_MIME_FALLBACKS: dict[str, str] = {
    ".mp3": "audio/mpeg",
    ".wav": "audio/wav",
    ".m4a": "audio/mp4",
    ".aac": "audio/aac",
    ".ogg": "audio/ogg",
    ".flac": "audio/flac",
    ".jpg": "image/jpeg",
    ".jpeg": "image/jpeg",
    ".png": "image/png",
    ".webp": "image/webp",
}

_INLINE_MEDIA_LIMIT_BYTES = 15 * 1024 * 1024


def resolve_model_name(name: str) -> str:
    key = name.strip().lower()
    return MODEL_ALIASES.get(key, name.strip())


def get_model_alias(model_name: str) -> str:
    resolved = resolve_model_name(model_name)
    return _REVERSE_ALIASES.get(resolved, resolved)


def _read_env_value(env_path: Path, key: str) -> str | None:
    if not env_path.exists():
        return None
    for line in env_path.read_text(encoding="utf-8").splitlines():
        stripped = line.strip()
        if stripped.startswith(f"{key}="):
            return stripped.split("=", 1)[1].strip().strip('"').strip("'")
    return None


def get_current_model(env_path: Path | None = None) -> tuple[str, str]:
    target = env_path or (PROJECT_ROOT / ".env")
    raw = _read_env_value(target, "GEMINI_MODEL") or os.getenv("GEMINI_MODEL", "gemini-3.8-flash")
    resolved = resolve_model_name(raw)
    return resolved, get_model_alias(resolved)


def switch_default_model(alias_or_name: str, env_path: Path | None = None) -> str:
    resolved = resolve_model_name(alias_or_name)
    target = env_path or (PROJECT_ROOT / ".env")
    lines = target.read_text(encoding="utf-8").splitlines() if target.exists() else []
    updated = False
    new_lines: list[str] = []
    for line in lines:
        if line.startswith("GEMINI_MODEL="):
            new_lines.append(f"GEMINI_MODEL={resolved}")
            updated = True
        else:
            new_lines.append(line)
    if not updated:
        new_lines.append(f"GEMINI_MODEL={resolved}")
    target.parent.mkdir(parents=True, exist_ok=True)
    target.write_text("\n".join(new_lines) + "\n", encoding="utf-8")
    os.environ["GEMINI_MODEL"] = resolved
    return resolved


def _guess_mime(path: Path, default: str) -> str:
    suffix = path.suffix.lower()
    if suffix in _MIME_FALLBACKS:
        return _MIME_FALLBACKS[suffix]
    guessed, _ = mimetypes.guess_type(str(path))
    return guessed or default


def _match_known_project(candidate: str | None, project_names: list[str] | None) -> str | None:
    if not candidate or not project_names:
        return None
    cleaned = candidate.strip()
    for name in project_names:
        if cleaned == name.strip() or cleaned.lower() == name.strip().lower():
            return name
    return None


class GeminiHotspotAgent:
    """Reliable Gemini agent supporting model aliases, 503 retries, and multimodal analysis."""

    def __init__(self, api_key: str | None = None, model: str | None = None) -> None:
        if not os.getenv("GEMINI_API_KEY"):
            load_dotenv(PROJECT_ROOT / ".env", override=False)
        resolved_key = (api_key or os.getenv("GEMINI_API_KEY", "")).strip()
        if not resolved_key or resolved_key == "your_gemini_api_key_here":
            raise ValueError(
                "未配置有效的 GEMINI_API_KEY。请在项目根目录的 .env 文件中填入你的 Gemini API Key。"
            )
        if model:
            self.model = resolve_model_name(model)
        else:
            self.model, _ = get_current_model()
        self.client = genai.Client(api_key=resolved_key)

    def _generate_with_retry(self, contents: Any, schema: type, temperature: float) -> str:
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

    def _build_media_parts(
        self,
        audio_paths: list[Path | str] | None,
        image_paths: list[Path | str] | None,
    ) -> tuple[list[Any], list[Any]]:
        parts: list[Any] = []
        uploaded: list[Any] = []
        media_specs: list[tuple[Path, str]] = []
        for raw_p in audio_paths or []:
            media_specs.append((Path(raw_p), "audio/mpeg"))
        for raw_p in image_paths or []:
            media_specs.append((Path(raw_p), "image/jpeg"))

        for path, default_mime in media_specs:
            if not path.exists() or not path.is_file():
                continue
            size = path.stat().st_size
            if size == 0:
                continue
            mime = _guess_mime(path, default_mime)
            if size <= _INLINE_MEDIA_LIMIT_BYTES:
                parts.append(types.Part.from_bytes(data=path.read_bytes(), mime_type=mime))
            else:
                handle = self.client.files.upload(file=str(path))
                uploaded.append(handle)
                parts.append(handle)
        return parts, uploaded

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

    def analyze_content(
        self,
        *,
        source: str,
        title: str = "",
        url: str = "",
        text: str = "",
        audio_paths: list[Path | str] | None = None,
        image_paths: list[Path | str] | None = None,
        project_names: list[str] | None = None,
    ) -> KnowledgeEntry:
        media_parts, uploaded = self._build_media_parts(audio_paths, image_paths)
        prompt = build_knowledge_prompt(
            source=source,
            title=title,
            url=url,
            text=text,
            project_names=project_names,
            has_media=bool(media_parts),
        )
        contents: Any = [*media_parts, prompt] if media_parts else prompt
        try:
            raw_json = self._generate_with_retry(
                contents=contents,
                schema=KnowledgeExtraction,
                temperature=0.4,
            )
        finally:
            for handle in uploaded:
                try:
                    self.client.files.delete(name=handle.name)
                except Exception:  # noqa: BLE001
                    pass

        extracted = KnowledgeExtraction.model_validate_json(raw_json)
        matched = _match_known_project(extracted.matched_project, project_names)
        return KnowledgeEntry(
            title=extracted.title.strip() or title.strip() or "未命名知识条目",
            source=source,
            url=url,
            domain=extracted.domain,
            ladder_level=extracted.ladder_level,
            matched_project=matched,
            one_line_essence=extracted.one_line_essence.strip(),
            how_to_apply=extracted.how_to_apply.strip(),
            deep_insight=extracted.deep_insight.strip(),
            tags=extracted.tags,
            heat_score=extracted.heat_score,
        )

    def analyze_item(
        self, item: RawItem, project_names: list[str] | None = None
    ) -> KnowledgeEntry:
        return self.analyze_content(
            source=item.source,
            title=item.title,
            url=item.url,
            text=item.summary,
            project_names=project_names,
        )
