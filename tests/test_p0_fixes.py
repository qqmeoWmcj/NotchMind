from __future__ import annotations

import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from contextlib import contextmanager
from pathlib import Path
from typing import Any

from google.genai import errors as genai_errors

from src.models import KnowledgeEntry


def test_sync_watchdog_self_heals_stalled_running_state() -> None:
    from src.workbench.app import WorkbenchController

    ctrl = WorkbenchController(
        vault_root=Path("/tmp/hud-wd-vault"), data_dir=Path("/tmp/hud-wd-data"),
        env_path=Path("/tmp/hud-wd.env"), sync_watchdog_seconds=100.0,
    )
    with ctrl._lock:
        ctrl._sync_status = {
            "running": True, "message": "正在抓取今日热点...",
            "updated_at": "2026-11-20 12:00:00", "last_result": None, "started_at": time.time() - 10.0,
        }
    ctrl._reap_stalled_sync()
    assert ctrl._sync_status["running"] is True, "not yet over the watchdog window"

    with ctrl._lock:
        ctrl._sync_status["started_at"] = time.time() - 200.0
    ctrl._reap_stalled_sync()
    assert ctrl._sync_status["running"] is False
    assert "已自动复位" in ctrl._sync_status["message"]
    assert ctrl._sync_status["last_result"]["error"] == "watchdog_timeout"

    # A finished sync (started_at=None) is never reaped.
    with ctrl._lock:
        ctrl._sync_status = {"running": False, "message": "done", "updated_at": "", "last_result": None, "started_at": None}
    ctrl._reap_stalled_sync()
    assert ctrl._sync_status["running"] is False


def test_action_token_store_single_use_ttl_and_action_binding() -> None:
    from src.workbench.security import ActionTokenStore

    store = ActionTokenStore(ttl_seconds=60.0)
    token = store.issue("toggle-clipboard")
    assert store.consume(token, "toggle-clipboard") is True
    assert store.consume(token, "toggle-clipboard") is False, "tokens must be single-use"
    assert store.consume("", "toggle-clipboard") is False, "empty token never valid"

    other = store.issue("sync")
    assert store.consume(other, "toggle-clipboard") is False, "token is bound to its action"
    assert store.consume(other, "sync") is True, "unused token stays valid for its own action"

    expired = ActionTokenStore(ttl_seconds=1.0)
    stale = expired.issue("sync")
    expired._tokens[stale] = ("sync", time.monotonic() - 5.0)
    assert expired.consume(stale, "sync") is False, "expired token must be rejected"


def test_engine_retry_backoff_and_client_error_classification() -> None:
    from google.genai import errors as genai_errors

    from src.agent.engine import (
        GeminiHotspotAgent,
        compute_backoff_delay,
        is_retryable_error,
    )

    assert is_retryable_error(genai_errors.ServerError(503, {})) is True
    assert is_retryable_error(genai_errors.ClientError(429, {})) is True
    assert is_retryable_error(genai_errors.ClientError(400, {})) is False
    assert is_retryable_error(genai_errors.ClientError(403, {})) is False
    assert is_retryable_error(ValueError("unrelated")) is False

    # Full-jitter backoff is bounded and varies with seeded rngs.
    assert compute_backoff_delay(0, rng=lambda: 0.0) == 0.0
    ceil = compute_backoff_delay(0, rng=lambda: 1.0)
    assert ceil == 2.0, "attempt 0 ceiling is the 2s base"
    assert compute_backoff_delay(10, rng=lambda: 1.0) == 30.0, "capped at 30s"

    # 429 retries with backoff then succeeds; non-retryable 400 raises immediately.
    sleeps: list[float] = []

    class _FlakyClient:
        def __init__(self, codes: list[int]) -> None:
            self._codes = list(codes)

        @property
        def models(self) -> "_FlakyClient":
            return self

        def generate_content(self, **kwargs: Any) -> Any:
            if self._codes:
                code = self._codes.pop(0)
                if code == 429:
                    raise genai_errors.ClientError(429, {})
                raise genai_errors.ClientError(400, {})
            return type("Resp", (), {"text": '{"ok": true}'})()

    agent = GeminiHotspotAgent.__new__(GeminiHotspotAgent)
    agent.model = "gemini-3.8-flash"
    agent.client = _FlakyClient([429, 429])
    agent._sleep = sleeps.append
    agent._rng = lambda: 0.5
    out = agent._generate_with_retry("hi", dict, 0.2)
    assert out == '{"ok": true}' and len(sleeps) == 2 and all(0 <= s <= 30 for s in sleeps)

    agent2 = GeminiHotspotAgent.__new__(GeminiHotspotAgent)
    agent2.model = "gemini-3.8-flash"
    agent2.client = _FlakyClient([400])
    agent2._sleep = sleeps.append
    agent2._rng = lambda: 0.5
    try:
        agent2._generate_with_retry("hi", dict, 0.2)
        raise AssertionError("ClientError(400) must raise immediately")
    except genai_errors.ClientError as err:
        assert err.code == 400
    assert len(sleeps) == 2, "no sleep for a non-retryable error"


def test_clipboard_watcher_stop_is_instant_and_no_thread_leftover() -> None:
    from src.companion import ClipboardWatcher

    release = threading.Event()

    def _slow_capture(text: str, agent: Any, v_root: Path, d_dir: Path, **kwargs: Any) -> dict[str, Any]:
        release.wait(timeout=30.0)
        return {"ok": True, "kind": "plain_text", "title": text[:20], "entry": {"title": text[:20]}}

    watcher = ClipboardWatcher(
        vault_root=Path("/tmp/hud-cw-vault"), data_dir=Path("/tmp/hud-cw-data"),
        agent_factory=lambda: object(), capture_plain_text=True,
        clipboard_reader=lambda: "多模态分析关键帧联系表的工作流笔记",
        worker_timeout=2.0,
    )
    from src.companion import clipboard_watcher as cw_mod

    original = cw_mod.capture_input
    cw_mod.capture_input = _slow_capture
    try:
        status = watcher.start()
        assert status["running"] is True
        watcher.check_once()  # enqueues one slow analysis into the worker queue
        stop_status = watcher.stop()
        assert stop_status["running"] is False, "stop must not wait for the slow analysis"
        assert watcher._thread is None and watcher._worker_thread is None
    finally:
        cw_mod.capture_input = original
        release.set()


def test_bilibili_duplicate_bvid_skips_analysis_and_frame_hash_commits_after_save(
    tmp_path: Path,
) -> None:
    from src.companion.bilibili_piliplus import (
        LiveCompanionSession,
        analyze_bilibili_video,
        entry_bvid_exists,
    )
    from src.exporters.obsidian import save_knowledge_entry
    from src.models import KnowledgeEntry

    vault, data = tmp_path / "vault", tmp_path / "data"

    class _FailsIfCalled:
        def analyze_content(self, **kwargs: Any) -> Any:
            raise AssertionError("duplicate BVID must never reach the analysis agent")

    # First save the video for real, then re-analyze: must skip without calling Gemini.
    save_knowledge_entry(
        vault, data,
        KnowledgeEntry(
            title="B站视频 BV1xx411c7mD",
            source="B站视频",
            url="https://www.bilibili.com/video/BV1xx411c7mD",
            domain="02-AI学习与教程",
            ladder_level="L1基础教程",
            one_line_essence="e", how_to_apply="h", deep_insight="d",
        ),
    )
    assert entry_bvid_exists(data, "BV1xx411c7mD") is True
    assert entry_bvid_exists(data, "BV1notExist0") is False
    dup = analyze_bilibili_video("https://www.bilibili.com/video/BV1xx411c7mD", _FailsIfCalled(), vault, data)
    assert dup["ok"] is False and dup["skipped"] is True and dup["duplicate"] is True

    # Live-companion frame hash commits only after a successful save.
    session = LiveCompanionSession.__new__(LiveCompanionSession)
    session.vault_root, session.data_dir = vault, data
    session._lock = threading.Lock()
    session._stop_event = threading.Event()
    session._thread = None
    session.interval_seconds = 45.0
    session._capture_count = 0
    session._last_frame_hash = ""
    session._last_capture_at = None
    session._last_error = None
    session._active_window = {}
    session._recent_events = []

    class _ExplodesOnceThenSaves:
        def __init__(self) -> None:
            self.calls = 0

        def analyze_content(self, **kwargs: Any) -> KnowledgeEntry:
            self.calls += 1
            if self.calls == 1:
                raise RuntimeError("simulated analysis failure")
            return KnowledgeEntry(
                title="同看画面", source="伴随同看", url="",
                domain="02-AI学习与教程", ladder_level="L1基础教程",
                one_line_essence="e", how_to_apply="h", deep_insight="d",
            )

    agent = _ExplodesOnceThenSaves()
    session._agent_factory = lambda: agent
    with monkeypatched_bili("detect_active_video_window", lambda: {"app": "PiliPlus", "title": "t", "url": "", "bvid": None, "bounds": None, "is_piliplus": True}), \
         monkeypatched_bili("capture_silent_screenshot", lambda path, bounds=None: _write_frame(path, "frame-A")):
        try:
            session.capture_once()
        except RuntimeError:
            pass
        assert session._last_frame_hash == "", "failed analysis must not commit the frame hash"

    with monkeypatched_bili("detect_active_video_window", lambda: {"app": "PiliPlus", "title": "t", "url": "", "bvid": None, "bounds": None, "is_piliplus": True}), \
         monkeypatched_bili("capture_silent_screenshot", lambda path, bounds=None: _write_frame(path, "frame-A")):
        session.capture_once()
        assert session._last_frame_hash != "", "successful save must commit the frame hash"
        assert session._capture_count == 1


def _write_frame(path: Path, payload: str) -> bool:
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(payload.encode("utf-8"))
    return True


@contextmanager
def monkeypatched_bili(name: str, replacement: Any):
    import src.companion.bilibili_piliplus as mod

    original = getattr(mod, name)
    setattr(mod, name, replacement)
    try:
        yield
    finally:
        setattr(mod, name, original)


