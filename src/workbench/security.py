from __future__ import annotations

import html
import secrets
import threading
import time

ACTION_TOKEN_TTL_SECONDS = 120.0

_PAGE_STYLE = (
    "body{margin:0;padding:24px 16px;background:#F7F7F7;color:#111111;"
    'font-family:-apple-system,BlinkMacSystemFont,"PingFang SC",sans-serif;font-size:14px;}'
    ".box{max-width:480px;margin:0 auto;background:#FFFFFF;border:1px solid #E5E5E5;"
    "border-radius:6px;padding:16px;}"
    "h1{font-size:20px;font-weight:600;margin:0 0 10px 0;}"
    "p{font-size:14px;color:#111111;margin:0 0 14px 0;}"
    "button,a{display:inline-block;padding:6px 12px;border:1px solid #E5E5E5;border-radius:6px;"
    "background:#FFFFFF;color:#111111;text-decoration:none;font-size:14px;cursor:pointer;}"
    "button:hover,a:hover{background:#F7F7F7;}"
    "form{display:inline-block;margin:0 8px 0 0;}"
    ".hint{font-size:12px;color:#666666;margin:14px 0 0 0;}"
)


class ActionTokenStore:
    """Single-use CSRF tokens for the Obsidian GET -> confirm page -> POST flow.

    A GET never mutates state; it only renders a page carrying one of these tokens.
    The matching POST must present it, so a cross-site <img> or auto-submitted form
    cannot trigger work: the attacker cannot read the token off the confirmation page.
    """

    def __init__(self, ttl_seconds: float = ACTION_TOKEN_TTL_SECONDS) -> None:
        self._ttl = max(1.0, float(ttl_seconds))
        self._lock = threading.Lock()
        self._tokens: dict[str, tuple[str, float]] = {}

    def issue(self, action: str) -> str:
        token = secrets.token_urlsafe(18)
        now = time.monotonic()
        with self._lock:
            self._tokens = {key: value for key, value in self._tokens.items() if value[1] > now}
            self._tokens[token] = (action.strip().lower(), now + self._ttl)
        return token

    def consume(self, token: str, action: str) -> bool:
        """Spend the token for this action; on mismatch keep it alive for its own action."""
        if not token:
            return False
        now = time.monotonic()
        with self._lock:
            entry = self._tokens.get(token)
            if entry is None or entry[1] <= now or entry[0] != action.strip().lower():
                return False
            del self._tokens[token]
        return True


def render_confirm_page(title: str, message: str, action: str, token: str) -> bytes:
    """Render the second-step confirmation page with an explicit POST form."""
    escaped_title = html.escape(title)
    escaped_message = html.escape(message)
    escaped_action = html.escape(action, quote=True)
    escaped_token = html.escape(token, quote=True)
    doc = (
        '<!DOCTYPE html><html lang="zh-CN"><head><meta charset="UTF-8">'
        '<meta name="viewport" content="width=device-width,initial-scale=1.0">'
        '<meta name="referrer" content="no-referrer">'
        f"<title>{escaped_title}</title><style>{_PAGE_STYLE}</style></head><body>"
        f'<div class="box"><h1>{escaped_title}</h1><p>{escaped_message}</p>'
        f'<form method="POST" action="/api/action/{escaped_action}">'
        f'<input type="hidden" name="csrf" value="{escaped_token}">'
        '<button type="submit">确认执行</button></form>'
        '<a href="/">打开工作台</a>'
        f'<p class="hint">本次确认 {int(ACTION_TOKEN_TTL_SECONDS)} 秒内有效且只能使用一次。</p>'
        "</div></body></html>"
    )
    return doc.encode("utf-8")
