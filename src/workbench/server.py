"""HTTP server & request handler for the workbench (split from app.py for the 20 KB rule)."""
from __future__ import annotations

import argparse
import html
import json
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import parse_qs, urlparse

from src.workbench.app import DEFAULT_HOST, DEFAULT_PORT, WorkbenchController
from src.workbench.security import ActionTokenStore, render_confirm_page

__all__ = ["UI_HTML_PATH", "WorkbenchHTTPServer", "WorkbenchRequestHandler", "create_server", "main"]

UI_HTML_PATH = Path(__file__).resolve().parent / "ui.html"


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
        self.action_tokens = ActionTokenStore()
        super().__init__(server_address, handler_cls)


class WorkbenchRequestHandler(BaseHTTPRequestHandler):
    server: WorkbenchHTTPServer

    def log_message(self, format: str, *args: Any) ->  None:  # noqa: A002
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
            try:
                title, message = ctrl.describe_action(action)
            except KeyError as exc:
                self._send_bytes(HTTPStatus.NOT_FOUND, "text/html; charset=utf-8", _render_trigger_page("操作不存在", str(exc)))
                return
            token = self.server.action_tokens.issue(action)
            self._send_bytes(HTTPStatus.OK, "text/html; charset=utf-8", render_confirm_page(title, message, action, token))
            return

        self._send_json(HTTPStatus.NOT_FOUND, {"ok": False, "error": f"未找到路径: {path}"})

    def _handle_confirmed_action(self) -> None:
        path = urlparse(self.path).path
        action = path.removeprefix("/api/action/").strip("/")
        if (self.headers.get("Sec-Fetch-Site") or "").strip().lower() == "cross-site":
            self._send_bytes(HTTPStatus.FORBIDDEN, "text/html; charset=utf-8", _render_trigger_page("已拒绝", "跨站请求不能执行本机操作。"))
            return
        length = int(self.headers.get("Content-Length", "0") or "0")
        raw = self.rfile.read(min(length, 16_384)) if length > 0 else b""
        form = parse_qs(raw.decode("utf-8", "replace"))
        token = (form.get("csrf") or [""])[0]
        if not self.server.action_tokens.consume(token, action):
            self._send_bytes(
                HTTPStatus.FORBIDDEN,
                "text/html; charset=utf-8",
                _render_trigger_page("确认已失效", "请回到 Obsidian 控制台重新点击操作链接。"),
            )
            return
        try:
            result = self.server.controller.trigger_action(action)
        except KeyError as exc:
            self._send_bytes(HTTPStatus.NOT_FOUND, "text/html; charset=utf-8", _render_trigger_page("操作不存在", str(exc)))
            return
        except Exception as exc:  # noqa: BLE001
            self._send_bytes(HTTPStatus.INTERNAL_SERVER_ERROR, "text/html; charset=utf-8", _render_trigger_page("操作失败", str(exc)))
            return
        self._send_bytes(HTTPStatus.OK, "text/html; charset=utf-8", _render_trigger_page("操作已执行", str(result.get("message") or "已完成")))

    def do_POST(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        ctrl = self.server.controller
        if path.startswith("/api/action/"):
            self._handle_confirmed_action()
            return
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
