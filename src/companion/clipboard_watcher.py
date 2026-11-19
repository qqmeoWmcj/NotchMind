from __future__ import annotations

import hashlib
import re
import subprocess
import threading
from html.parser import HTMLParser
from pathlib import Path
from typing import Any, Callable
from urllib.parse import urlparse

from src.collectors.base import is_ai_related
from src.companion.bilibili_piliplus import analyze_bilibili_video, extract_bilibili_bvid
from src.companion.xhs_cleaner import (
    USER_AGENT,
    extract_xhs_url,
    find_bin,
    get_project_names,
    now_iso,
    process_xhs_url,
    resolve_agent,
)
from src.exporters.obsidian import save_knowledge_entry

_URL_RE = re.compile(r"https?://[^\s\"'<>]+")
_B23_RE = re.compile(r"https?://b23\.tv/[0-9A-Za-z]+")
_LOCAL_HOSTS = {"127.0.0.1", "localhost", "::1", "0.0.0.0"}
_AI_TECH_DOMAINS = (
    "github.com", "huggingface.co", "arxiv.org", "openai.com", "anthropic.com",
    "deepmind.google", "ai.google.dev", "blog.google", "news.ycombinator.com",
    "qbitai.com", "jiqizhixin.com", "aibase.com", "36kr.com", "juejin.cn",
    "zhihu.com", "mp.weixin.qq.com", "substack.com", "medium.com",
)
_CN_AI_KEYWORDS = (
    "大模型", "人工智能", "智能体", "提示词", "工作流", "生图", "视频生成",
    "开源模型", "comfyui", "blender", "notebooklm", "obsidian", "多模态", "知识库",
)


def hash_clipboard_text(text: str) -> str:
    """Return a stable SHA256 digest for clipboard deduplication."""
    return hashlib.sha256((text or "").strip().encode("utf-8")).hexdigest()


def is_ai_topic_text(text: str) -> bool:
    """Check English + Chinese AI/tooling/3D workflow keywords."""
    if not text:
        return False
    if is_ai_related(text):
        return True
    lower = text.lower()
    return any(kw in lower for kw in _CN_AI_KEYWORDS)


def _is_ai_tech_url(url: str) -> bool:
    host = (urlparse(url).hostname or "").lower()
    if any(host == d or host.endswith(f".{d}") for d in _AI_TECH_DOMAINS):
        return True
    return is_ai_topic_text(url)


def classify_clipboard_content(text: str) -> dict[str, Any]:
    """Classify clipboard or user-submitted text into bilibili/xiaohongshu/web_url/plain_text."""
    cleaned = (text or "").strip()
    if not cleaned:
        return {"kind": "empty", "url": "", "bvid": "", "text": "", "is_ai_url": False}

    xhs_url = extract_xhs_url(cleaned)
    if xhs_url:
        return {"kind": "xiaohongshu", "url": xhs_url, "bvid": "", "text": cleaned, "is_ai_url": True}

    bvid = extract_bilibili_bvid(cleaned)
    b23_match = _B23_RE.search(cleaned)
    url_match = _URL_RE.search(cleaned)
    first_url = url_match.group(0).rstrip(".,;:!?)】》」』，。！？）") if url_match else ""

    if bvid or b23_match or "bilibili.com/" in first_url.lower():
        if "bilibili.com" in first_url.lower() or "b23.tv" in first_url.lower():
            bili_url = first_url
        elif b23_match:
            bili_url = b23_match.group(0)
        else:
            bili_url = f"https://www.bilibili.com/video/{bvid}"
        return {"kind": "bilibili", "url": bili_url, "bvid": bvid or "", "text": cleaned, "is_ai_url": True}

    if first_url:
        host = (urlparse(first_url).hostname or "").lower()
        if host in _LOCAL_HOSTS:
            return {"kind": "ignored", "url": first_url, "bvid": "", "text": cleaned, "is_ai_url": False}
        return {"kind": "web_url", "url": first_url, "bvid": "", "text": cleaned, "is_ai_url": _is_ai_tech_url(first_url)}

    return {"kind": "plain_text", "url": "", "bvid": "", "text": cleaned, "is_ai_url": is_ai_topic_text(cleaned)}


class _ReadableHTMLParser(HTMLParser):
    _SKIP_TAGS = {"script", "style", "noscript", "svg", "iframe"}

    def __init__(self) -> None:
        super().__init__()
        self._skip_depth = 0
        self._in_title = False
        self.title_parts: list[str] = []
        self.text_parts: list[str] = []

    def handle_starttag(self, tag: str, attrs: list[tuple[str, str | None]]) -> None:
        low = tag.lower()
        if low in self._SKIP_TAGS:
            self._skip_depth += 1
        elif low == "title":
            self._in_title = True

    def handle_endtag(self, tag: str) -> None:
        low = tag.lower()
        if low in self._SKIP_TAGS and self._skip_depth > 0:
            self._skip_depth -= 1
        elif low == "title":
            self._in_title = False

    def handle_data(self, data: str) -> None:
        if self._skip_depth > 0:
            return
        chunk = data.strip()
        if not chunk:
            return
        (self.title_parts if self._in_title else self.text_parts).append(chunk)


def fetch_web_article(url: str, timeout: int = 12, max_chars: int = 6000) -> tuple[str, str]:
    """Fetch a public web article silently via curl and extract readable title + body."""
    curl = find_bin("curl", ("/usr/bin/curl",))
    try:
        proc = subprocess.run(
            [curl, "-sL", "--max-time", str(timeout), "-A", USER_AGENT, url],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout + 3, check=False,
        )
    except (OSError, subprocess.SubprocessError):
        return "", ""
    if proc.returncode != 0 or not proc.stdout.strip():
        return "", ""

    parser = _ReadableHTMLParser()
    try:
        parser.feed(proc.stdout[:250_000])
    except Exception:  # noqa: BLE001
        return "", ""
    title = re.sub(r"\s+", " ", " ".join(parser.title_parts)).strip()
    body = re.sub(r"\s+", " ", " ".join(parser.text_parts)).strip()
    return title[:160], body[:max_chars]


def capture_input(
    text: str,
    agent: Any,
    vault_root: Path | str,
    data_dir: Path | str,
    *,
    allow_plain_text: bool = True,
    require_ai_for_web: bool = False,
    source_label: str = "手动提交",
) -> dict[str, Any]:
    """Unified capture router for Bilibili, Xiaohongshu, AI web articles, and pasted notes."""
    vault_path, data_path = Path(vault_root), Path(data_dir)
    info = classify_clipboard_content(text)
    kind = info["kind"]

    if kind in ("empty", "ignored"):
        return {"ok": False, "skipped": True, "kind": kind, "reason": "空内容或本地地址已忽略"}

    if kind == "bilibili":
        res = analyze_bilibili_video(info["bvid"] or info["url"], agent, vault_path, data_path)
        res.setdefault("kind", "bilibili")
        return res

    if kind == "xiaohongshu":
        extra = re.sub(r"复制本条信息.*?小红书.*$", "", info["text"].replace(info["url"], "")).strip()
        res = process_xhs_url(info["url"], agent, vault_path, data_path, text=extra if len(extra) >= 8 else "")
        res.setdefault("kind", "xiaohongshu")
        return res

    if kind == "web_url":
        url = info["url"]
        page_title, page_body = fetch_web_article(url)
        if require_ai_for_web and not (info["is_ai_url"] or is_ai_topic_text(f"{page_title}\n{page_body[:1500]}")):
            return {"ok": False, "skipped": True, "kind": "web_url", "url": url, "reason": "非 AI/创作技术文章链接，已静默忽略"}
        entry = agent.analyze_content(
            source="网页文章",
            title=page_title or url,
            url=url,
            text=f"网页标题：{page_title}\n来源链接：{url}\n正文摘录：\n{page_body or info['text']}",
            project_names=get_project_names(vault_path, data_path),
        )
        saved = save_knowledge_entry(vault_path, data_path, entry)
        return {"ok": True, "skipped": False, "kind": "web_url", "url": url, "title": saved.get("title", page_title or url), "entry": saved}

    if not allow_plain_text:
        return {"ok": False, "skipped": True, "kind": "plain_text", "reason": "纯文本自动捕获未开启"}

    first_line = info["text"].splitlines()[0].strip()[:48] or "剪贴板笔记"
    entry = agent.analyze_content(
        source=source_label,
        title=first_line,
        url="",
        text=info["text"][:6000],
        project_names=get_project_names(vault_path, data_path),
    )
    saved = save_knowledge_entry(vault_path, data_path, entry)
    return {"ok": True, "skipped": False, "kind": "plain_text", "title": saved.get("title", first_line), "entry": saved}


def read_macos_clipboard(timeout: float = 2.0) -> str:
    """Silently read macOS clipboard text via pbpaste (zero Terminal windows)."""
    pbpaste = find_bin("pbpaste", ("/usr/bin/pbpaste",))
    try:
        proc = subprocess.run(
            [pbpaste], stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout, check=False
        )
        return proc.stdout if proc.returncode == 0 else ""
    except (OSError, subprocess.SubprocessError):
        return ""


class ClipboardWatcher:
    """Silent background macOS clipboard watcher with SHA256 deduplication."""

    def __init__(
        self,
        vault_root: Path | str,
        data_dir: Path | str,
        agent_factory: Any = None,
        poll_interval: float = 2.0,
        capture_plain_text: bool = False,
        clipboard_reader: Callable[[], str] | None = None,
    ) -> None:
        self.vault_root = Path(vault_root)
        self.data_dir = Path(data_dir)
        self._agent_factory = agent_factory
        self.poll_interval = max(0.5, float(poll_interval))
        self._capture_plain_text = bool(capture_plain_text)
        self._clipboard_reader = clipboard_reader or read_macos_clipboard
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._seen_hashes: set[str] = set()
        self._processed_count = 0
        self._recent_events: list[dict[str, Any]] = []

    @property
    def is_running(self) -> bool:
        with self._lock:
            return self._thread is not None and self._thread.is_alive()

    @property
    def recent_events(self) -> list[dict[str, Any]]:
        with self._lock:
            return list(self._recent_events)

    def _record_event(self, event: dict[str, Any]) -> None:
        with self._lock:
            self._recent_events.insert(0, event)
            del self._recent_events[30:]

    def _status_locked(self) -> dict[str, Any]:
        return {
            "running": self._thread is not None and self._thread.is_alive(),
            "poll_interval": self.poll_interval,
            "capture_plain_text": self._capture_plain_text,
            "processed_count": self._processed_count,
            "last_event": self._recent_events[0] if self._recent_events else None,
            "recent_events": list(self._recent_events),
        }

    def status(self) -> dict[str, Any]:
        with self._lock:
            return self._status_locked()

    def set_capture_plain_text(self, enabled: bool) -> dict[str, Any]:
        with self._lock:
            self._capture_plain_text = bool(enabled)
            return self._status_locked()

    def start(self) -> dict[str, Any]:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return self._status_locked()
            initial = self._clipboard_reader()
            if initial and initial.strip():
                self._seen_hashes.add(hash_clipboard_text(initial))
            self._stop_event.clear()
            self._thread = threading.Thread(target=self._poll_loop, name="clipboard-watcher", daemon=True)
            self._thread.start()
            return self._status_locked()

    def stop(self) -> dict[str, Any]:
        self._stop_event.set()
        with self._lock:
            thread = self._thread
        if thread is not None and thread.is_alive():
            thread.join(timeout=2.0)
        with self._lock:
            if self._thread is thread and not thread.is_alive():
                self._thread = None
            return self._status_locked()

    def process_text(
        self,
        text: str,
        *,
        allow_plain_text: bool | None = None,
        source_label: str = "剪贴板",
        dedup: bool = True,
    ) -> dict[str, Any]:
        """Deduplicate by SHA256 and silently process copied link or text."""
        cleaned = (text or "").strip()
        if not cleaned:
            return {"ok": False, "skipped": True, "reason": "空内容"}

        digest = hash_clipboard_text(cleaned)
        with self._lock:
            if dedup and digest in self._seen_hashes:
                return {"ok": False, "skipped": True, "duplicate": True, "hash": digest}
            self._seen_hashes.add(digest)
            plain_allowed = self._capture_plain_text if allow_plain_text is None else allow_plain_text

        info = classify_clipboard_content(cleaned)
        if info["kind"] in ("empty", "ignored") or (info["kind"] == "plain_text" and not plain_allowed):
            return {"ok": False, "skipped": True, "kind": info["kind"]}

        try:
            result = capture_input(
                cleaned,
                resolve_agent(self._agent_factory),
                self.vault_root,
                self.data_dir,
                allow_plain_text=plain_allowed,
                require_ai_for_web=(source_label == "剪贴板"),
                source_label=source_label,
            )
        except Exception as exc:  # noqa: BLE001
            result = {"ok": False, "kind": info["kind"], "error": str(exc)}

        if result.get("ok"):
            with self._lock:
                self._processed_count += 1
        if not result.get("skipped") or result.get("filtered"):
            self._record_event({
                "time": now_iso(),
                "hash": digest[:12],
                "kind": result.get("kind", info["kind"]),
                "ok": bool(result.get("ok")),
                "filtered": bool(result.get("filtered")),
                "skipped": bool(result.get("skipped")),
                "title": str(result.get("title") or info.get("url") or cleaned[:40]),
                "detail": str(result.get("reason") or result.get("error") or ("已写入 Obsidian" if result.get("ok") else "")),
            })
        return result

    def check_once(self) -> dict[str, Any] | None:
        """Poll clipboard once and process if new content was copied."""
        text = self._clipboard_reader()
        if not text or not text.strip():
            return None
        digest = hash_clipboard_text(text)
        with self._lock:
            if digest in self._seen_hashes:
                return None
        return self.process_text(text, source_label="剪贴板", dedup=True)

    def _poll_loop(self) -> None:
        while not self._stop_event.is_set():
            try:
                self.check_once()
            except Exception as exc:  # noqa: BLE001
                self._record_event({
                    "time": now_iso(), "hash": "", "kind": "error", "ok": False,
                    "filtered": False, "skipped": False, "title": "剪贴板监测异常", "detail": str(exc),
                })
            if self._stop_event.wait(self.poll_interval):
                break
