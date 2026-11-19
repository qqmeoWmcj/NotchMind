from __future__ import annotations

import argparse
import html
import json
import os
import threading
from datetime import datetime
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any, Callable
from urllib.parse import parse_qs, urlparse

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
UI_HTML_PATH = Path(__file__).resolve().parent / "ui.html"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765


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

    def _default_agent_factory(self) -> GeminiHotspotAgent:
        resolved, _ = get_current_model(env_path=self.env_path)
        return GeminiHotspotAgent(model=resolved)

    def get_state(self, domain: str | None = None, project: str | None = None) -> dict[str, Any]:
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
            self._sync_status = {"running": True, "message": "正在抓取今日热点...", "updated_at": _now_str(), "last_result": None}

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
            self._sync_status = {"running": False, "message": message, "updated_at": _now_str(), "last_result": result}

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

    def trigger_action(self, action: str) -> dict[str, Any]:
        normalized = (action or "").strip().lower()
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


def _render_trigger_page(title: str, message: str) -> bytes:
    st, sm = html.escape(title), html.escape(message)
    doc = (
        '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">'
        f"<title>{st}</title><style>"
        'body{margin:0;padding:24px 16px;background:#F7F7F7;color:#111111;font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;font-size:14px;}'
        ".box{max-width:480px;margin:0 auto;background:#FFFFFF;border:1px solid #E5E5E5;border-radius:6px;padding:16px;}"
        "h1{font-size:20px;font-weight:600;margin:0 0 10px 0;}p{font-size:14px;color:#111111;margin:0 0 14px 0;}"
        "a{display:inline-block;padding:6px 12px;border:1px solid #E5E5E5;border-radius:6px;background:#FFFFFF;color:#111111;text-decoration:none;font-size:14px;}"
        "a:hover{background:#F7F7F7;}"
        f'</style></head><body><div class="box"><h1>{st}</h1><p>{sm}</p><a href="/">打开工作台</a></div></body></html>'
    )
    return doc.encode("utf-8")


class WorkbenchHTTPServer(ThreadingHTTPServer):
    allow_reuse_address = True
    daemon_threads = True

    def __init__(self, server_address: tuple[str, int], handler_cls: type[BaseHTTPRequestHandler], controller: WorkbenchController) -> None:
        self.controller = controller
        super().__init__(server_address, handler_cls)


class WorkbenchRequestHandler(BaseHTTPRequestHandler):
    server: WorkbenchHTTPServer

    def log_message(self, format: str, *args: Any) -> None:  # noqa: A002
        return

    def _send_common_headers(self, content_type: str, length: int) -> None:
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(length))
        self.send_header("Cache-Control", "no-store")
        self.send_header("Content-Security-Policy", "frame-ancestors * http: https: app: obsidian: file:")
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")

    def _send_bytes(self, status: int, content_type: str, body: bytes) -> None:
        self.send_response(status)
        self._send_common_headers(content_type, len(body))
        self.end_headers()
        self.wfile.write(body)

    def _send_json(self, status: int, payload: dict[str, Any]) -> None:
        self._send_bytes(status, "application/json; charset=utf-8", json.dumps(payload, ensure_ascii=False).encode("utf-8"))

    def _read_json_body(self) -> dict[str, Any]:
        length = int(self.headers.get("Content-Length", "0") or "0")
        if length <= 0:
            return {}
        raw = self.rfile.read(min(length, 1_048_576))
        if not raw:
            return {}
        data = json.loads(raw.decode("utf-8"))
        if not isinstance(data, dict):
            raise ValueError("请求体必须为 JSON 对象")
        return data

    def do_OPTIONS(self) -> None:  # noqa: N802
        self.send_response(HTTPStatus.NO_CONTENT)
        self._send_common_headers("text/plain; charset=utf-8", 0)
        self.end_headers()

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        path, query = parsed.path, parse_qs(parsed.query)
        ctrl = self.server.controller

        if path in ("/", "/index.html"):
            self._send_bytes(HTTPStatus.OK, "text/html; charset=utf-8", UI_HTML_PATH.read_bytes())
            return

        if path == "/api/state":
            domain = (query.get("domain") or [None])[0]
            project = (query.get("project") or [None])[0]
            self._send_json(HTTPStatus.OK, ctrl.get_state(domain=domain, project=project))
            return

        if path.startswith("/api/trigger/"):
            action = path.removeprefix("/api/trigger/").strip("/")
            wants_json = (query.get("format") or [""])[0].lower() == "json"
            try:
                result = ctrl.trigger_action(action)
            except KeyError as exc:
                if wants_json:
                    self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": str(exc)})
                else:
                    self._send_bytes(HTTPStatus.NOT_FOUND, "text/html; charset=utf-8", _render_trigger_page("操作不存在", str(exc)))
                return
            if wants_json:
                self._send_json(HTTPStatus.OK, result)
            else:
                self._send_bytes(HTTPStatus.OK, "text/html; charset=utf-8", _render_trigger_page("操作已执行", str(result.get("message") or "已完成")))
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": f"未找到路径: {path}"})

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        ctrl = self.server.controller
        try:
            body = self._read_json_body()
        except (ValueError, json.JSONDecodeError) as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": f"无效请求体: {exc}"})
            return

        try:
            if path == "/api/model":
                self._send_json(HTTPStatus.OK, ctrl.switch_model(str(body.get("model") or "")))
                return
            if path == "/api/sync-hotspots":
                top_k_raw = body.get("top_k")
                top_k = int(top_k_raw) if top_k_raw is not None else None
                self._send_json(HTTPStatus.OK, ctrl.trigger_sync_hotspots(top_k=top_k, dry_run=bool(body.get("dry_run", False))))
                return
            if path == "/api/toggle-clipboard":
                self._send_json(HTTPStatus.OK, ctrl.toggle_clipboard())
                return
            if path == "/api/toggle-companion":
                self._send_json(HTTPStatus.OK, ctrl.toggle_companion())
                return
            if path == "/api/capture-url":
                raw_input = str(body.get("input") or body.get("url") or body.get("text") or "")
                self._send_json(HTTPStatus.OK, ctrl.submit_capture(raw_input, source_label=str(body.get("source_label") or "手动提交")))
                return
            if path == "/api/projects":
                name = str(body.get("name") or "")
                summary = str(body.get("idea_summary") or body.get("summary") or "")
                self._send_json(HTTPStatus.OK, ctrl.create_project(name=name, idea_summary=summary))
                return
        except ValueError as exc:
            self._send_json(HTTPStatus.BAD_REQUEST, {"ok": False, "error": str(exc)})
            return
        except Exception as exc:  # noqa: BLE001
            self._send_json(HTTPStatus.INTERNAL_SERVER_ERROR, {"ok": False, "error": str(exc)})
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": f"未找到路径: {path}"})


def create_server(
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
    controller: WorkbenchController | None = None,
    **controller_kwargs: Any,
) -> WorkbenchHTTPServer:
    return WorkbenchHTTPServer((host, port), WorkbenchRequestHandler, controller=controller or WorkbenchController(**controller_kwargs))


def main() -> None:
    parser = argparse.ArgumentParser(description="AI hotspot local minimalist workbench server.")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    parser.add_argument("--auto-clipboard", action="store_true", help="Enable clipboard watcher on startup.")
    args = parser.parse_args()

    server = create_server(host=args.host, port=args.port)
    if args.auto_clipboard:
        server.controller.clipboard_watcher.start()
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.controller.shutdown()
        server.server_close()


if __name__ == "__main__":
    main()
