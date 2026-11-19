from __future__ import annotations

import hashlib
import json
import os
import re
import subprocess
import tempfile
import threading
from pathlib import Path
from typing import Any

from src.companion.xhs_cleaner import (
    USER_AGENT,
    find_bin,
    get_project_names,
    now_iso,
    resolve_agent,
)
from src.exporters.obsidian import save_knowledge_entry

_BVID_RE = re.compile(r"(?<![0-9A-Za-z])(BV[0-9A-Za-z]{10})(?![0-9A-Za-z])")
_B23_RE = re.compile(r"https?://b23\.tv/[0-9A-Za-z]+")
_BILI_REFERER = "https://www.bilibili.com"
_BROWSER_APPS = ("Google Chrome", "Safari", "Arc", "Microsoft Edge", "Brave Browser")
_FFMPEG_BINS = ("/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg")

_WIN_DETECT_SCRIPT = """
on winMeta(pName)
    tell application "System Events"
        try
            tell process pName
                if (count of windows) > 0 then
                    set t to name of front window
                    set {px, py} to position of front window
                    set {sw, sh} to size of front window
                    return t & tab & (px as text) & "," & (py as text) & "," & (sw as text) & "," & (sh as text)
                end if
            end tell
        end try
    end tell
    return "" & tab & ""
end winMeta
tell application "System Events"
    set fApp to name of first application process whose frontmost is true
    set pRun to (exists (processes whose name is "PiliPlus"))
end tell
set fMeta to my winMeta(fApp)
set pMeta to "" & tab & ""
if pRun then set pMeta to my winMeta("PiliPlus")
return fApp & tab & fMeta & tab & (pRun as text) & tab & pMeta
"""


def _run_cmd(cmd: list[str], *, timeout: int = 15, text: bool = True) -> subprocess.CompletedProcess[Any] | None:
    try:
        return subprocess.run(cmd, stdin=subprocess.DEVNULL, capture_output=True, text=text, timeout=timeout, check=False)
    except (OSError, subprocess.SubprocessError):
        return None


def extract_bilibili_bvid(text: str) -> str | None:
    """Extract a Bilibili BVID (e.g. BV1xx411c7mD) from a URL or arbitrary text."""
    match = _BVID_RE.search(text or "")
    return match.group(1) if match else None


def resolve_bilibili_short_url(text: str, timeout: int = 10) -> str | None:
    """Resolve a b23.tv short link via curl redirect and extract the target BVID."""
    match = _B23_RE.search(text or "")
    if not match:
        return None
    curl = find_bin("curl", ("/usr/bin/curl",))
    proc = _run_cmd(
        [curl, "-sIL", "--max-time", str(timeout), "-A", USER_AGENT, "-o", os.devnull, "-w", "%{url_effective}", match.group(0)],
        timeout=timeout + 3,
    )
    return extract_bilibili_bvid(proc.stdout or "") if proc else None


def _curl_json(url: str, timeout: int = 15) -> dict[str, Any]:
    curl = find_bin("curl", ("/usr/bin/curl",))
    proc = _run_cmd(
        [curl, "-sL", "--max-time", str(timeout), "-A", USER_AGENT, "-H", f"Referer: {_BILI_REFERER}", url],
        timeout=timeout + 3,
    )
    if not proc or proc.returncode != 0 or not (proc.stdout or "").strip():
        return {}
    try:
        parsed = json.loads(proc.stdout)
        return parsed if isinstance(parsed, dict) else {}
    except json.JSONDecodeError:
        return {}


def select_non_mcdn_url(durl_entry: dict[str, Any]) -> str | None:
    """Prefer backup_url CDN nodes without 'mcdn' to avoid stalled downloads."""
    backups = durl_entry.get("backup_url") or durl_entry.get("backupUrl") or []
    candidates = [str(u) for u in backups if u] if isinstance(backups, list) else []
    if durl_entry.get("url"):
        candidates.append(str(durl_entry["url"]))
    for url in candidates:
        if "mcdn" not in url.lower():
            return url
    return candidates[0] if candidates else None


def fetch_bilibili_view(bvid: str, timeout: int = 15) -> dict[str, Any]:
    """Fetch public video metadata from Bilibili web-interface view API."""
    payload = _curl_json(f"https://api.bilibili.com/x/web-interface/view?bvid={bvid}", timeout=timeout)
    return payload["data"] if payload.get("code") == 0 and isinstance(payload.get("data"), dict) else {}


def fetch_bilibili_playurl(bvid: str, cid: int, timeout: int = 15) -> str | None:
    """Fetch HTML5 stream URL, preferring non-mcdn backup_url."""
    payload = _curl_json(
        f"https://api.bilibili.com/x/player/playurl?bvid={bvid}&cid={cid}&qn=64&fnval=1&platform=html5",
        timeout=timeout,
    )
    data = payload.get("data") if payload.get("code") == 0 else None
    durl = data.get("durl") if isinstance(data, dict) else None
    return select_non_mcdn_url(durl[0]) if isinstance(durl, list) and durl and isinstance(durl[0], dict) else None


def _fetch_subtitle_excerpt(view_data: dict[str, Any], max_chars: int = 4000) -> str:
    sub_list = (view_data.get("subtitle") or {}).get("list") or []
    for sub in sub_list if isinstance(sub_list, list) else []:
        sub_url = str((sub or {}).get("subtitle_url") or "").strip()
        if not sub_url:
            continue
        if sub_url.startswith("//"):
            sub_url = f"https:{sub_url}"
        body = _curl_json(sub_url, timeout=10).get("body")
        if isinstance(body, list):
            joined = "\n".join(str(x.get("content") or "").strip() for x in body if isinstance(x, dict) and x.get("content"))
            if joined:
                return joined[:max_chars]
    return ""


def _sample_paths(paths: list[Path], max_count: int = 6) -> list[Path]:
    if len(paths) <= max_count:
        return paths
    step = (len(paths) - 1) / (max_count - 1)
    return [paths[round(i * step)] for i in range(max_count)]


def _download_and_extract_media(
    stream_url: str, work_dir: Path, duration: int = 0
) -> tuple[Path | None, list[Path], str]:
    """Download via curl, extract 16kHz mono mp3 + 2x3 contact sheets (no drawtext), delete video.mp4."""
    curl = find_bin("curl", ("/usr/bin/curl",))
    ffmpeg = find_bin("ffmpeg", _FFMPEG_BINS)
    video_path, audio_path = work_dir / "video.mp4", work_dir / "audio.mp3"

    dl = _run_cmd(
        [curl, "-sL", "--max-time", "90", "-A", USER_AGENT, "-H", f"Referer: {_BILI_REFERER}", "-o", str(video_path), stream_url],
        timeout=95, text=False,
    )
    if not dl or dl.returncode != 0 or not video_path.exists() or video_path.stat().st_size < 16_384:
        video_path.unlink(missing_ok=True)
        return None, [], "视频流下载受限或文件过小，已降级为元数据/字幕分析"

    audio_ok, sheets = False, []
    try:
        ap = _run_cmd(
            [ffmpeg, "-y", "-i", str(video_path), "-vn", "-ac", "1", "-ar", "16000", "-b:a", "32k", str(audio_path)],
            timeout=120, text=False,
        )
        audio_ok = bool(ap and ap.returncode == 0 and audio_path.exists() and audio_path.stat().st_size > 1024)

        interval = 4 if duration <= 240 else max(4, min(30, duration // 36))
        _run_cmd(
            [ffmpeg, "-y", "-i", str(video_path), "-vf", f"fps=1/{interval},scale=960:-1,tile=2x3", "-q:v", "3", str(work_dir / "sheet_%02d.jpg")],
            timeout=120, text=False,
        )
        sheets = _sample_paths(sorted(work_dir.glob("sheet_*.jpg")), max_count=6)
    finally:
        video_path.unlink(missing_ok=True)

    if not audio_ok and not sheets:
        return None, [], "ffmpeg 提取失败，已降级为元数据/字幕分析"
    return (audio_path if audio_ok else None), sheets, ""


def analyze_bilibili_video(
    url_or_bvid: str, agent: Any, vault_root: Path | str, data_dir: Path | str
) -> dict[str, Any]:
    """Mode 1: Analyze a Bilibili video via audio + 2x3 contact sheets with graceful fallback."""
    vault_path, data_path = Path(vault_root), Path(data_dir)
    raw = (url_or_bvid or "").strip()
    bvid = extract_bilibili_bvid(raw) or resolve_bilibili_short_url(raw)
    if not bvid:
        return {"ok": False, "error": "未识别到有效的 B 站 BV 号", "input": raw}

    canonical_url = f"https://www.bilibili.com/video/{bvid}"
    view = fetch_bilibili_view(bvid)
    title = str(view.get("title") or f"B站视频 {bvid}").strip()
    desc = str(view.get("desc") or "").strip()
    owner = str((view.get("owner") or {}).get("name") or "未知UP主").strip()
    tname = str(view.get("tname") or "未知").strip()
    duration, cid = int(view.get("duration") or 0), int(view.get("cid") or 0)

    warning, audio_path, sheets = "", None, []
    with tempfile.TemporaryDirectory(prefix=f"bili_{bvid}_") as tmp:
        stream_url = fetch_bilibili_playurl(bvid, cid) if cid else None
        if stream_url:
            audio_path, sheets, warning = _download_and_extract_media(stream_url, Path(tmp), duration=duration)
        else:
            warning = "未获取到公开播放流，已降级为标题/简介/字幕分析"

        subtitle = "" if (audio_path or sheets) else _fetch_subtitle_excerpt(view)
        mode = "multimodal" if (audio_path or sheets) else "metadata_fallback"
        lines = [
            f"BVID：{bvid} | 标题：{title} | UP主：{owner} | 分区：{tname} | 时长：{duration}秒",
            f"简介：{desc[:1800] or '无'}",
        ]
        if subtitle:
            lines.append(f"字幕摘录：\n{subtitle}")
        lines.append("请结合音轨口播与2x3画面联系表（如有），提炼核心方法、Prompt/步骤、L1/L2/L3层级与「我可以怎么用」。")

        entry = agent.analyze_content(
            source="B站视频",
            title=title,
            url=canonical_url,
            text="\n".join(lines),
            audio_paths=[audio_path] if audio_path else None,
            image_paths=sheets or None,
            project_names=get_project_names(vault_path, data_path),
        )
        saved = save_knowledge_entry(vault_path, data_path, entry)
        return {
            "ok": True, "bvid": bvid, "mode": mode, "url": canonical_url,
            "title": saved.get("title", title), "audio_extracted": bool(audio_path),
            "sheet_count": len(sheets), "warning": warning, "entry": saved,
        }


def _parse_bounds(raw: str) -> tuple[int, int, int, int] | None:
    parts = [p.strip() for p in (raw or "").split(",")]
    if len(parts) != 4:
        return None
    try:
        x, y, w, h = (int(float(p)) for p in parts)
        return (x, y, w, h) if w >= 200 and h >= 150 else None
    except ValueError:
        return None


def _get_browser_url(app_name: str) -> str:
    if app_name not in _BROWSER_APPS:
        return ""
    osa = find_bin("osascript", ("/usr/bin/osascript",))
    script = (
        'tell application "Safari" to return URL of current tab of front window'
        if app_name == "Safari"
        else f'tell application "{app_name}" to return URL of active tab of front window'
    )
    proc = _run_cmd([osa, "-e", script], timeout=3)
    return (proc.stdout or "").strip() if proc and proc.returncode == 0 else ""


def detect_active_video_window() -> dict[str, Any]:
    """Silently detect PiliPlus or browser window via osascript (zero Terminal popup)."""
    result: dict[str, Any] = {
        "app": "", "title": "", "url": "", "bvid": None,
        "is_piliplus": False, "is_video_player": False, "bounds": None, "detected_at": now_iso(),
    }
    osa = find_bin("osascript", ("/usr/bin/osascript",))
    proc = _run_cmd([osa, "-e", _WIN_DETECT_SCRIPT], timeout=4)
    if not proc or proc.returncode != 0 or not (proc.stdout or "").strip():
        return result

    f_app, f_title, f_bounds, p_run, p_title, p_bounds = (proc.stdout.rstrip("\n").split("\t") + [""] * 6)[:6]
    is_pili = p_run.strip().lower() == "true"
    if f_app == "PiliPlus" or (is_pili and f_app not in _BROWSER_APPS):
        app, title, url = "PiliPlus", p_title or f_title, ""
        bounds = _parse_bounds(p_bounds) or _parse_bounds(f_bounds)
    else:
        app, title, bounds = f_app, f_title, _parse_bounds(f_bounds)
        url = _get_browser_url(f_app)

    result.update({
        "app": app, "title": title, "url": url,
        "bvid": extract_bilibili_bvid(f"{title} {url}"),
        "is_piliplus": app == "PiliPlus",
        "is_video_player": app == "PiliPlus" or app in _BROWSER_APPS,
        "bounds": bounds,
    })
    return result


def capture_silent_screenshot(output_path: Path, bounds: tuple[int, int, int, int] | None = None) -> bool:
    """Capture a silent macOS JPEG screenshot via screencapture -x."""
    sc = find_bin("screencapture", ("/usr/sbin/screencapture",))
    cmds: list[list[str]] = []
    if bounds:
        x, y, w, h = bounds
        cmds.append([sc, "-x", "-t", "jpg", "-R", f"{x},{y},{w},{h}", str(output_path)])
    cmds.append([sc, "-x", "-t", "jpg", str(output_path)])
    for cmd in cmds:
        proc = _run_cmd(cmd, timeout=8, text=False)
        if proc and proc.returncode == 0 and output_path.exists() and output_path.stat().st_size > 2048:
            return True
    return False


def _capture_optional_audio(output_path: Path, duration_sec: int = 8) -> Path | None:
    device = os.getenv("COMPANION_AUDIO_DEVICE", "").strip()
    if not device:
        return None
    ffmpeg = find_bin("ffmpeg", _FFMPEG_BINS)
    spec = device if device.startswith(":") else f":{device}"
    proc = _run_cmd(
        [ffmpeg, "-y", "-f", "avfoundation", "-i", spec, "-t", str(duration_sec), "-ac", "1", "-ar", "16000", "-b:a", "32k", str(output_path)],
        timeout=duration_sec + 8, text=False,
    )
    if proc and proc.returncode == 0 and output_path.exists() and output_path.stat().st_size > 1024:
        return output_path
    return None


class LiveCompanionSession:
    """Mode 2: Silent background PiliPlus/browser live-watch daemon (zero Terminal windows)."""

    def __init__(
        self, vault_root: Path | str, data_dir: Path | str,
        agent_factory: Any = None, interval_seconds: float = 45.0,
    ) -> None:
        self.vault_root, self.data_dir = Path(vault_root), Path(data_dir)
        self._agent_factory = agent_factory
        self.interval_seconds = max(5.0, float(interval_seconds))
        self._lock = threading.Lock()
        self._stop_event = threading.Event()
        self._thread: threading.Thread | None = None
        self._capture_count = 0
        self._last_frame_hash = ""
        self._last_capture_at: str | None = None
        self._last_error: str | None = None
        self._active_window: dict[str, Any] = {}
        self._recent_events: list[dict[str, Any]] = []

    @property
    def is_running(self) -> bool:
        with self._lock:
            return self._thread is not None and self._thread.is_alive()

    def _record_event(self, status: str, detail: str, title: str = "") -> None:
        with self._lock:
            self._recent_events.insert(0, {"time": now_iso(), "status": status, "title": title, "detail": detail})
            del self._recent_events[20:]

    def _status_locked(self) -> dict[str, Any]:
        return {
            "running": self._thread is not None and self._thread.is_alive(),
            "interval_seconds": self.interval_seconds,
            "capture_count": self._capture_count,
            "active_window": dict(self._active_window),
            "last_capture_at": self._last_capture_at,
            "last_error": self._last_error,
            "recent_events": list(self._recent_events),
        }

    def status(self) -> dict[str, Any]:
        with self._lock:
            return self._status_locked()

    def start(self) -> dict[str, Any]:
        with self._lock:
            if self._thread is not None and self._thread.is_alive():
                return self._status_locked()
            self._stop_event.clear()
            self._last_error = None
            self._thread = threading.Thread(target=self._run_loop, name="live-companion-session", daemon=True)
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

    def capture_once(self) -> dict[str, Any]:
        """Run one silent screenshot (+ optional audio) multimodal analysis cycle."""
        window = detect_active_video_window()
        with self._lock:
            self._active_window = window

        with tempfile.TemporaryDirectory(prefix="companion_live_") as tmp:
            work_dir = Path(tmp)
            shot_path = work_dir / "frame.jpg"
            if not capture_silent_screenshot(shot_path, window.get("bounds")):
                msg = "静默截屏失败（请检查 macOS 屏幕录制权限）"
                with self._lock:
                    self._last_error = msg
                self._record_event("error", msg, window.get("title", ""))
                return {"ok": False, "error": msg, "window": window}

            frame_hash = hashlib.sha256(shot_path.read_bytes()).hexdigest()
            with self._lock:
                if frame_hash == self._last_frame_hash:
                    return {"ok": True, "skipped": True, "reason": "画面无变化，已跳过重复分析"}
                self._last_frame_hash = frame_hash

            audio_path = _capture_optional_audio(work_dir / "clip.mp3")
            source = "PiliPlus伴随同看" if window.get("is_piliplus") else "伴随同看"
            bvid = window.get("bvid")
            url = window.get("url") or (f"https://www.bilibili.com/video/{bvid}" if bvid else "")
            title = window.get("title") or f"{window.get('app') or '桌面'}实时同看画面"
            prompt_text = (
                f"伴随同看应用：{window.get('app') or '未知'} | 窗口：{title} | 链接：{url or '无'}\n"
                "请结合截屏与音频片段（如有），提炼核心知识点、具体操作/Prompt、L1/L2/L3层级与「我可以怎么用」。"
            )
            entry = resolve_agent(self._agent_factory).analyze_content(
                source=source, title=title, url=url, text=prompt_text,
                audio_paths=[audio_path] if audio_path else None,
                image_paths=[shot_path],
                project_names=get_project_names(self.vault_root, self.data_dir),
            )
            saved = save_knowledge_entry(self.vault_root, self.data_dir, entry)

        with self._lock:
            self._capture_count += 1
            self._last_capture_at = now_iso()
            self._last_error = None
        self._record_event("captured", "已提炼并写入 Obsidian", str(saved.get("title") or title))
        return {"ok": True, "skipped": False, "window": window, "entry": saved}

    def _run_loop(self) -> None:
        if self._stop_event.wait(1.5):
            return
        while not self._stop_event.is_set():
            try:
                self.capture_once()
            except Exception as exc:  # noqa: BLE001
                msg = f"伴随同看异常：{exc}"
                with self._lock:
                    self._last_error = msg
                self._record_event("error", msg)
            if self._stop_event.wait(self.interval_seconds):
                break
