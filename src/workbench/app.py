from __future__ import annotations

import os
import threading
import time
from datetime import datetime
from pathlib import Path
from typing import Any, Callable

from dotenv import load_dotenv

from src.agent.engine import (
    GeminiHotspotAgent,
    get_current_model,
    get_model_alias,
    switch_default_model,
)
from src.companion import ClipboardWatcher, LiveCompanionSession, capture_input
from src.exporters.obsidian import (
    create_project_idea,
    ensure_vault_initialized,
    list_knowledge_entries,
    list_projects,
)
from src.main import resolve_data_dir, resolve_vault_path, sync_hotspots_once

PROJECT_ROOT = Path(__file__).resolve().parent.parent.parent
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765

# Single source of truth for Obsidian-facing actions: GET renders a confirmation
# page for these, POST /api/action/{action} executes them.
_ACTION_DESCRIPTIONS: dict[str, tuple[str, str]] = {
    "sync": ("抓取今日热点", "将抓取多个来源并写入知识库，通常需要 1 至 2 分钟。"),
    "sync-hotspots": ("抓取今日热点", "将抓取多个来源并写入知识库，通常需要 1 至 2 分钟。"),
    "toggle-clipboard": ("切换剪贴板监测", "开启或关闭后台剪贴板监听。"),
    "toggle-companion": ("切换伴随同看", "开启或关闭 PiliPlus / 浏览器伴随同看。"),
}


def _now_str() -> str:
    return datetime.now().strftime("%Y-%m-%d %H:%M:%S")


class WorkbenchController:
    """Thread-safe controller coordinating vault state, sync, and companion services."""

    def __init__(
        self,
        vault_root: Path | None = None,
        data_dir: Path | None = None,
        env_path: Path | None = None,
        agent_factory: Callable[[], Any] | None = None,
        sync_runner: Callable[..., dict[str, Any]] | None = None,
        capture_runner: Callable[..., dict[str, Any]] | None = None,
        clipboard_watcher: Any | None = None,
        live_companion: Any | None = None,
        sync_watchdog_seconds: float = 180.0,
    ) -> None:
        self.env_path = Path(env_path).resolve() if env_path else (PROJECT_ROOT / ".env")
        if self.env_path.exists():
            load_dotenv(self.env_path, override=False)

        self.vault_root = Path(vault_root).resolve() if vault_root else resolve_vault_path()
        self.data_dir = Path(data_dir).resolve() if data_dir else resolve_data_dir()
        ensure_vault_initialized(self.vault_root, self.data_dir)

        self._agent_factory = agent_factory or self._default_agent_factory
        self._sync_runner = sync_runner or sync_hotspots_once
        self._capture_runner = capture_runner or capture_input
        self._lock = threading.Lock()

        self.clipboard_watcher = clipboard_watcher or ClipboardWatcher(
            vault_root=self.vault_root, data_dir=self.data_dir, agent_factory=self._agent_factory
        )
        self.live_companion = live_companion or LiveCompanionSession(
            vault_root=self.vault_root, data_dir=self.data_dir, agent_factory=self._agent_factory
        )

        self._sync_status: dict[str, Any] = {"running": False, "message": "就绪", "updated_at": "", "last_result": None}
        self._capture_status: dict[str, Any] = {"running": False, "message": "", "updated_at": "", "last_result": None}
        self._sync_watchdog_seconds = max(1.0, float(sync_watchdog_seconds))

    def _default_agent_factory(self) -> GeminiHotspotAgent:
        resolved, _ = get_current_model(env_path=self.env_path)
        return GeminiHotspotAgent(model=resolved)

    def _reap_stalled_sync(self) -> None:
        """Self-heal a sync whose worker is stuck below the socket layer (no read timeout)."""
        with self._lock:
            status = self._sync_status
            started_at = status.get("started_at")
            if not status.get("running") or not started_at:
                return
            if time.time() - started_at < self._sync_watchdog_seconds:
                return
            self._sync_status = {
                "running": False,
                "message": f"热点抓取超过 {int(self._sync_watchdog_seconds)}s 未返回，已自动复位，可重新触发",
                "updated_at": _now_str(),
                "last_result": {"ok": False, "error": "watchdog_timeout"},
                "started_at": None,
            }

    def get_state(self, domain: str | None = None, project: str | None = None) -> dict[str, Any]:
        self._reap_stalled_sync()
        resolved_model, alias = get_current_model(env_path=self.env_path)
        with self._lock:
            sync_status = dict(self._sync_status)
            capture_status = dict(self._capture_status)
        return {
            "model": alias,
            "model_full": resolved_model,
            "clipboard_watcher": self.clipboard_watcher.status(),
            "live_companion": self.live_companion.status(),
            "last_sync_status": sync_status,
            "last_capture_status": capture_status,
            "projects": list_projects(self.vault_root, self.data_dir),
            "entries": list_knowledge_entries(self.data_dir, domain=domain or None, project=project or None),
        }

    def switch_model(self, model: str) -> dict[str, Any]:
        cleaned = (model or "").strip()
        if not cleaned:
            raise ValueError("模型名称不能为空")
        resolved = switch_default_model(cleaned, env_path=self.env_path)
        return {"ok": True, "model": get_model_alias(resolved), "model_full": resolved}

    def trigger_sync_hotspots(self, top_k: int | None = None, dry_run: bool = False) -> dict[str, Any]:
        with self._lock:
            if self._sync_status["running"]:
                return {"ok": True, "started": False, "running": True, "message": "热点抓取正在进行中"}
            self._sync_status = {"running": True, "message": "正在抓取今日热点...", "updated_at": _now_str(), "last_result": None, "started_at": time.time()}

        k = top_k if top_k is not None else int(os.getenv("TOP_K_TOPICS", "3"))

        def _worker() -> None:
            try:
                resolved_model, _ = get_current_model(env_path=self.env_path)
                result = self._sync_runner(
                    top_k=k, dry_run=dry_run, model=resolved_model, vault_root=self.vault_root, data_dir=self.data_dir
                )
                msg = self._format_sync_message(result)
                self._set_sync_done(msg, result)
            except Exception as exc:  # noqa: BLE001
                self._set_sync_done(f"抓取失败: {exc}", {"ok": False, "error": str(exc)})

        threading.Thread(target=_worker, name="workbench-sync", daemon=True).start()
        return {"ok": True, "started": True, "running": True, "message": "已在后台启动热点抓取"}

    def _set_sync_done(self, message: str, result: Any) -> None:
        with self._lock:
            self._sync_status = {"running": False, "message": message, "updated_at": _now_str(), "last_result": result, "started_at": None}

    @staticmethod
    def _format_sync_message(result: Any) -> str:
        if not isinstance(result, dict):
            return "同步完成"
        if result.get("message"):
            return str(result["message"])
        status = result.get("status")
        if status == "empty":
            return f"暂无新热点（共检查 {result.get('fetched', 0)} 条）"
        if status == "dry_run":
            return f"预检完成（未处理 {result.get('unseen', 0)} 条）"
        if status == "failed":
            return "热点拆解失败，请稍后重试"
        saved = result.get("saved_count", result.get("saved"))
        return f"已同步 {saved} 条热点" if isinstance(saved, int) else "同步完成"

    def toggle_clipboard(self) -> dict[str, Any]:
        status = self.clipboard_watcher.stop() if self.clipboard_watcher.is_running else self.clipboard_watcher.start()
        running = bool(self.clipboard_watcher.is_running)
        return {"ok": True, "running": running, "message": "剪贴板监测已开启" if running else "剪贴板监测已关闭", "status": status}

    def toggle_companion(self) -> dict[str, Any]:
        status = self.live_companion.stop() if self.live_companion.is_running else self.live_companion.start()
        running = bool(self.live_companion.is_running)
        return {"ok": True, "running": running, "message": "伴随同看已开启" if running else "伴随同看已关闭", "status": status}

    def submit_capture(self, raw_input: str, source_label: str = "手动提交") -> dict[str, Any]:
        cleaned = (raw_input or "").strip()
        if not cleaned:
            raise ValueError("请输入链接或笔记内容")
        self._set_capture_state(True, "后台拆解中...", None)

        def _worker() -> None:
            try:
                agent = self._agent_factory()
                result = self._capture_runner(
                    cleaned, agent, self.vault_root, self.data_dir, allow_plain_text=True, source_label=source_label
                )
                self._set_capture_state(False, self._format_capture_message(result), result)
            except Exception as exc:  # noqa: BLE001
                self._set_capture_state(False, f"拆解失败: {exc}", {"ok": False, "error": str(exc)})

        threading.Thread(target=_worker, name="workbench-capture", daemon=True).start()
        return {"ok": True, "accepted": True, "message": "已提交后台拆解"}

    def _set_capture_state(self, running: bool, message: str, result: Any) -> None:
        now = _now_str()
        with self._lock:
            self._capture_status = {"running": running, "message": message, "updated_at": now, "last_result": result}
            if not self._sync_status["running"]:
                self._sync_status["message"] = message
                self._sync_status["updated_at"] = now

    @staticmethod
    def _format_capture_message(result: Any) -> str:
        if not isinstance(result, dict):
            return "拆解完成"
        if result.get("skipped") or result.get("filtered") or result.get("status") == "rejected":
            return f"已过滤: {result.get('reason') or '未通过过滤规则'}"
        if result.get("ok") is False or result.get("status") == "error":
            return f"拆解失败: {result.get('error') or result.get('reason') or '未知错误'}"
        entry = result.get("entry")
        if isinstance(entry, dict) and entry.get("title"):
            return f"已收录: {entry['title']}"
        if result.get("title"):
            return f"已收录: {result['title']}"
        return str(result.get("message") or "拆解完成并已写入知识库")

    def create_project(self, name: str, idea_summary: str = "") -> dict[str, Any]:
        cleaned_name = (name or "").strip()
        if not cleaned_name:
            raise ValueError("项目名称不能为空")
        summary = (idea_summary or "").strip() or cleaned_name
        return {"ok": True, "project": create_project_idea(self.vault_root, self.data_dir, cleaned_name, summary)}

    def describe_action(self, action: str) -> tuple[str, str]:
        normalized = (action or "").strip().lower()
        try:
            return _ACTION_DESCRIPTIONS[normalized]
        except KeyError:
            raise KeyError(f"未知操作: {action}") from None

    def trigger_action(self, action: str) -> dict[str, Any]:
        normalized = (action or "").strip().lower()
        self.describe_action(normalized)
        if normalized in ("sync", "sync-hotspots"):
            return self.trigger_sync_hotspots()
        if normalized == "toggle-clipboard":
            return self.toggle_clipboard()
        if normalized == "toggle-companion":
            return self.toggle_companion()
        raise KeyError(f"未知操作: {action}")

    def shutdown(self) -> None:
        for svc in (self.clipboard_watcher, self.live_companion):
            try:
                if svc.is_running:
                    svc.stop()
            except Exception:  # noqa: BLE001
                pass


if __name__ == "__main__":
    # Keep `python -m src.workbench.app` (used by the silent launcher) working.
    from src.workbench.server import main

    main()
