from __future__ import annotations

import html
import json
import re
import shutil
import subprocess
from datetime import datetime, timezone
from pathlib import Path
from typing import Any

from src.exporters.obsidian import list_projects, save_knowledge_entry

XHS_AD_KEYWORDS: tuple[str, ...] = (
    "私信领",
    "扣1",
    "训练营",
    "卖课",
    "加V",
    "加微",
    "限时免费领",
    "评论区领",
    "无偿分享",
)
MIN_COLLECT_LIKE_RATIO = 0.5
USER_AGENT = (
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) "
    "AppleWebKit/537.36 (KHTML, like Gecko) Chrome/131.0.0.0 Safari/537.36"
)

_XHS_URL_RE = re.compile(r"https?://(?:www\.)?(?:xiaohongshu\.com|xhslink\.com)/[^\s\"'<>]+")


def find_bin(name: str, fallbacks: tuple[str, ...] = ()) -> str:
    """Locate a macOS CLI binary even under minimal GUI .app PATH."""
    found = shutil.which(name)
    if found:
        return found
    for candidate in fallbacks:
        if Path(candidate).exists():
            return candidate
    return name


def now_iso() -> str:
    return datetime.now(timezone.utc).astimezone().isoformat(timespec="seconds")


def get_project_names(vault_root: Path, data_dir: Path) -> list[str]:
    try:
        return [
            str(p["name"])
            for p in list_projects(vault_root, data_dir)
            if isinstance(p, dict) and p.get("name")
        ]
    except Exception:  # noqa: BLE001
        return []


def resolve_agent(agent_or_factory: Any) -> Any:
    if agent_or_factory is None:
        from src.agent.engine import GeminiHotspotAgent

        return GeminiHotspotAgent()
    return agent_or_factory() if callable(agent_or_factory) else agent_or_factory


def extract_xhs_url(text: str) -> str | None:
    """Extract the first Xiaohongshu or xhslink URL from arbitrary text."""
    match = _XHS_URL_RE.search(text or "")
    return match.group(0).rstrip(".,;:!?)】》」』，。！？）") if match else None


def _parse_cn_count(raw: Any) -> int:
    if isinstance(raw, (int, float)):
        return max(0, int(raw))
    text = str(raw or "").strip().lower().replace(",", "").replace("+", "")
    if not text:
        return 0
    try:
        if text.endswith(("万", "w")):
            return max(0, int(float(text[:-1]) * 10_000))
        if text.endswith(("千", "k")):
            return max(0, int(float(text[:-1]) * 1_000))
        return max(0, int(float(text)))
    except ValueError:
        return 0


def evaluate_xhs_quality(
    title: str,
    text: str,
    likes: int = 0,
    collects: int = 0,
) -> tuple[bool, str]:
    """3-tier anti-ad filter: blacklist + collects/likes >= 0.5 (Tier 3 runs in Gemini)."""
    combined = f"{(title or '').strip()}\n{(text or '').strip()}".strip()
    if not combined:
        return False, "内容为空，已跳过"

    lowered = combined.lower()
    compact = re.sub(r"\s+", "", lowered)
    for keyword in XHS_AD_KEYWORDS:
        kw = keyword.lower()
        if kw in lowered or kw in compact:
            return False, f"命中广告/引流黑名单关键词：{keyword}"

    like_count = _parse_cn_count(likes)
    collect_count = _parse_cn_count(collects)
    if like_count > 0:
        ratio = collect_count / like_count
        if ratio < MIN_COLLECT_LIKE_RATIO:
            return False, f"收藏/点赞比过低 ({collect_count}/{like_count}={ratio:.0%} < 50%)"
        return True, f"通过初筛（收藏/点赞比 {ratio:.0%} >= 50%，无引流词）"

    return True, "通过关键词初筛（无公开点赞数据，交由 Gemini 干货校验）"


def _extract_meta(page_html: str, name: str) -> str:
    esc = re.escape(name)
    for pat in (
        rf'<meta[^>]+(?:property|name)=["\']{esc}["\'][^>]+content=["\']([^"\']*)["\']',
        rf'<meta[^>]+content=["\']([^"\']*)["\'][^>]+(?:property|name)=["\']{esc}["\']',
    ):
        match = re.search(pat, page_html, flags=re.IGNORECASE)
        if match:
            return html.unescape(match.group(1)).strip()
    return ""


def _parse_initial_state(page_html: str) -> dict[str, Any]:
    match = re.search(r"window\.__INITIAL_STATE__\s*=\s*(\{.*?\})\s*</script>", page_html, flags=re.DOTALL)
    if not match:
        return {}
    try:
        data = json.loads(match.group(1).replace(":undefined", ":null"))
    except json.JSONDecodeError:
        return {}
    note_map = data.get("note", {}).get("noteDetailMap", {})
    if not isinstance(note_map, dict):
        return {}
    for item in note_map.values():
        note = item.get("note") if isinstance(item, dict) else None
        if isinstance(note, dict):
            interact = note.get("interactInfo") or {}
            return {
                "title": str(note.get("title") or "").strip(),
                "text": str(note.get("desc") or "").strip(),
                "likes": _parse_cn_count(interact.get("likedCount")),
                "collects": _parse_cn_count(interact.get("collectedCount")),
            }
    return {}


def fetch_xhs_metadata(url: str, timeout: int = 12) -> dict[str, Any]:
    """Safely fetch public Xiaohongshu metadata via curl (never bypasses login/CAPTCHA)."""
    result: dict[str, Any] = {"url": url, "title": "", "text": "", "likes": 0, "collects": 0, "warning": ""}
    curl = find_bin("curl", ("/usr/bin/curl",))
    try:
        proc = subprocess.run(
            [curl, "-sL", "--max-time", str(timeout), "-A", USER_AGENT, "-H", "Accept-Language: zh-CN,zh;q=0.9", url],
            stdin=subprocess.DEVNULL, capture_output=True, text=True, timeout=timeout + 3, check=False,
        )
    except (OSError, subprocess.SubprocessError) as exc:
        result["warning"] = f"抓取小红书页面失败：{exc}"
        return result

    page_html = proc.stdout or ""
    if proc.returncode != 0 or not page_html.strip():
        result["warning"] = "小红书页面返回为空"
        return result
    if any(gate in page_html for gate in ("安全验证", "验证码", "captcha", "请登录后查看")):
        result["warning"] = "小红书页面需要登录或验证，未抓取正文（可直接粘贴正文分析）"
        return result

    state = _parse_initial_state(page_html)
    title = state.get("title") or _extract_meta(page_html, "og:title")
    if not title:
        m = re.search(r"<title[^>]*>(.*?)</title>", page_html, flags=re.IGNORECASE | re.DOTALL)
        title = html.unescape(m.group(1)).strip() if m else ""
    title = re.sub(r"\s*[-–—|]\s*小红书\s*$", "", title).strip()
    desc = state.get("text") or _extract_meta(page_html, "description") or _extract_meta(page_html, "og:description")
    result.update({"title": title, "text": desc, "likes": state.get("likes", 0), "collects": state.get("collects", 0)})
    return result


def process_xhs_url(
    url: str,
    agent: Any,
    vault_root: Path | str,
    data_dir: Path | str,
    *,
    title: str = "",
    text: str = "",
    likes: int = 0,
    collects: int = 0,
) -> dict[str, Any]:
    """Fetch XHS metadata safely, run 3-tier anti-ad filter, analyze with Gemini, and save."""
    vault_path, data_path = Path(vault_root), Path(data_dir)
    raw = (url or "").strip()
    clean_url = extract_xhs_url(raw) or (raw if raw.startswith(("http://", "https://")) else "")

    note_title = (title or "").strip()
    note_text = (text or "").strip()
    if not note_text and raw and raw != clean_url:
        cleaned = re.sub(r"复制本条信息.*?小红书.*$", "", raw.replace(clean_url, " "))
        note_text = re.sub(r"\s+", " ", cleaned).strip()

    like_count, collect_count = _parse_cn_count(likes), _parse_cn_count(collects)
    warning = ""
    if clean_url and (not note_text or not note_title):
        meta = fetch_xhs_metadata(clean_url)
        warning = meta.get("warning", "")
        note_title = note_title or meta.get("title", "")
        note_text = note_text or meta.get("text", "")
        like_count = like_count or int(meta.get("likes", 0))
        collect_count = collect_count or int(meta.get("collects", 0))

    if not note_title and not note_text:
        return {"ok": False, "filtered": False, "reason": warning or "未能获取小红书公开内容，请粘贴正文重试", "url": clean_url, "title": ""}

    passed, reason = evaluate_xhs_quality(note_title, note_text, like_count, collect_count)
    if not passed:
        return {"ok": False, "filtered": True, "reason": reason, "url": clean_url, "title": note_title}

    metrics = f"点赞={like_count}, 收藏={collect_count}, 比例={collect_count / like_count:.0%}" if like_count > 0 else "点赞/收藏未公开"
    analysis_text = (
        f"【小红书干货提炼】互动：{metrics}\n标题：{note_title or '未命名笔记'}\n"
        f"正文：\n{note_text[:5000]}\n请剔除水话，只提炼可复用的工具、步骤或 Prompt，并写明「我可以怎么用」。"
    )
    entry = agent.analyze_content(
        source="小红书",
        title=note_title or "小红书笔记",
        url=clean_url,
        text=analysis_text,
        project_names=get_project_names(vault_path, data_path),
    )
    saved = save_knowledge_entry(vault_path, data_path, entry)
    return {"ok": True, "filtered": False, "reason": reason, "warning": warning, "url": clean_url, "title": saved.get("title", note_title), "entry": saved}


def process_xhs_payload(payload: dict[str, Any], agent: Any, vault_root: Path | str, data_dir: Path | str) -> dict[str, Any]:
    """Process a structured favorite/pasted Xiaohongshu note payload."""
    return process_xhs_url(
        url=str(payload.get("url") or ""),
        agent=agent,
        vault_root=vault_root,
        data_dir=data_dir,
        title=str(payload.get("title") or ""),
        text=str(payload.get("text") or payload.get("desc") or payload.get("content") or ""),
        likes=_parse_cn_count(payload.get("likes") or payload.get("liked_count") or 0),
        collects=_parse_cn_count(payload.get("collects") or payload.get("collected_count") or 0),
    )
