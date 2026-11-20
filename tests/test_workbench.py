from __future__ import annotations

import json
import os
import plistlib
import re
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from pathlib import Path
from typing import Any

from scripts.build_silent_app import build_silent_app
from src.exporters import save_knowledge_entry
from src.models import KnowledgeEntry
from src.workbench.app import UI_HTML_PATH, create_server

PROJECT_ROOT = Path(__file__).resolve().parent.parent
ALLOWED_HEX_COLORS = {"#FFFFFF", "#F7F7F7", "#111111", "#666666", "#E5E5E5"}
ALLOWED_FONT_SIZES = {"12px", "14px", "16px", "20px"}
EMOJI_RE = re.compile(r"[\U0001F300-\U0001FAFF\u2600-\u27BF]")


def _http_request(
    base_url: str, path: str, method: str = "GET", payload: dict[str, Any] | None = None
) -> tuple[int, Any, bytes]:
    data = json.dumps(payload, ensure_ascii=False).encode("utf-8") if payload is not None else None
    headers = {"Content-Type": "application/json"} if payload is not None else {}
    req = urllib.request.Request(f"{base_url}{path}", data=data, headers=headers, method=method)
    try:
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status, resp.headers, resp.read()
    except urllib.error.HTTPError as err:
        return err.code, err.headers, err.read()


def test_real_workbench_http_server_endpoints(tmp_path: Path, monkeypatch) -> None:
    monkeypatch.setenv("GEMINI_MODEL", "gemini-4-hydrogen")
    vault_root = tmp_path / "vault"
    data_dir = tmp_path / "data"
    env_path = tmp_path / ".env"
    env_path.write_text("GEMINI_API_KEY=demo\nGEMINI_MODEL=gemini-4-hydrogen\n", encoding="utf-8")

    save_knowledge_entry(
        vault_root,
        data_dir,
        KnowledgeEntry(
            title="Blender MCP 联动实测",
            source="B站视频",
            url="https://www.bilibili.com/video/BV1xx411c7mD",
            domain="03-AI创作与3D工具",
            ladder_level="L2工具与AI联动",
            matched_project="Blender一站式AI建模",
            one_line_essence="本地 Socket 桥接 Blender API 后可按截图反馈修正材质。",
            how_to_apply="在 Blender 启用 MCP 监听并接入多模态模型回看。",
            deep_insight="闭环反馈是 3D 自动化稳定落地的关键。",
        ),
    )

    sync_called = threading.Event()
    capture_called = threading.Event()

    def _sync_runner(**kwargs) -> dict[str, Any]:
        sync_called.set()
        return {"status": "ok", "saved": 0, "message": "测试同步完成"}

    def _capture_runner(raw_input, agent, v_root, d_dir, **kwargs) -> dict[str, Any]:
        saved = save_knowledge_entry(
            v_root,
            d_dir,
            KnowledgeEntry(
                title="手动提交拆解条目",
                source="手动提交",
                url="",
                domain="02-AI学习与教程",
                ladder_level="L1基础教程",
                one_line_essence=f"已分析输入：{raw_input[:24]}",
                how_to_apply="复制到 Obsidian 即可复用。",
                deep_insight="实时后台拆解不阻塞页面。",
            ),
        )
        capture_called.set()
        return {"ok": True, "entry": saved}

    server = create_server(
        host="127.0.0.1",
        port=0,
        vault_root=vault_root,
        data_dir=data_dir,
        env_path=env_path,
        agent_factory=lambda: object(),
        sync_runner=_sync_runner,
        capture_runner=_capture_runner,
    )
    port = server.server_address[1]
    base_url = f"http://127.0.0.1:{port}"
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()

    try:
        # 1. GET / serves ui.html with permissive iframe headers for Obsidian Web Viewer
        status, headers, body = _http_request(base_url, "/")
        assert status == 200
        assert "text/html" in headers.get("Content-Type", "")
        assert "frame-ancestors" in headers.get("Content-Security-Policy", "")
        assert headers.get("X-Frame-Options") is None
        html_text = body.decode("utf-8")
        assert "抓今日热点" in html_text
        assert "复制结论" in html_text

        # 2. GET /api/state returns valid state + supports domain/project filtering
        status, _, body = _http_request(base_url, "/api/state")
        assert status == 200
        state = json.loads(body.decode("utf-8"))
        assert state["model"] == "4h"
        assert state["model_full"] == "gemini-4-hydrogen"
        assert state["clipboard_watcher"]["running"] is False
        assert state["live_companion"]["running"] is False
        assert len(state["entries"]) == 1
        assert any(p["name"] == "Blender一站式AI建模" for p in state["projects"])

        q = urllib.parse.urlencode({"domain": "03-AI创作与3D工具"})
        status, _, body = _http_request(base_url, f"/api/state?{q}")
        assert status == 200
        assert len(json.loads(body.decode("utf-8"))["entries"]) == 1

        # 3. POST /api/projects creates a real L1/L2/L3 incubator note and updates state
        status, _, body = _http_request(
            base_url,
            "/api/projects",
            method="POST",
            payload={"name": "自动化知识播客", "idea_summary": "自动汇总热点并生成每日口播稿"},
        )
        assert status == 200
        proj_resp = json.loads(body.decode("utf-8"))
        assert proj_resp["ok"] is True
        assert (vault_root / "05-项目孵化池" / "自动化知识播客.md").exists()

        # 4. POST /api/model switches model in .env and reflects in /api/state
        status, _, body = _http_request(
            base_url, "/api/model", method="POST", payload={"model": "3.8f"}
        )
        assert status == 200
        model_resp = json.loads(body.decode("utf-8"))
        assert model_resp["model"] == "3.8f"
        assert model_resp["model_full"] == "gemini-3.8-flash"
        assert "GEMINI_MODEL=gemini-3.8-flash" in env_path.read_text(encoding="utf-8")

        status, _, body = _http_request(base_url, "/api/state")
        assert json.loads(body.decode("utf-8"))["model"] == "3.8f"

        # 5. Toggle clipboard & companion watchers on and off cleanly
        status, _, body = _http_request(base_url, "/api/toggle-clipboard", method="POST", payload={})
        assert status == 200 and json.loads(body.decode("utf-8"))["running"] is True
        status, _, body = _http_request(base_url, "/api/toggle-clipboard", method="POST", payload={})
        assert status == 200 and json.loads(body.decode("utf-8"))["running"] is False

        status, _, body = _http_request(base_url, "/api/toggle-companion", method="POST", payload={})
        assert status == 200 and json.loads(body.decode("utf-8"))["running"] is True
        status, _, body = _http_request(base_url, "/api/toggle-companion", method="POST", payload={})
        assert status == 200 and json.loads(body.decode("utf-8"))["running"] is False

        # 6. POST /api/capture-url + GET /api/trigger/sync work non-blocking
        status, _, body = _http_request(
            base_url, "/api/capture-url", method="POST", payload={"input": "一段用于验证的 AI 工作流笔记"}
        )
        assert status == 200 and json.loads(body.decode("utf-8"))["accepted"] is True
        assert capture_called.wait(timeout=3.0)

        status, _, body = _http_request(base_url, "/api/trigger/sync?format=json")
        assert status == 200 and json.loads(body.decode("utf-8"))["ok"] is True
        assert sync_called.wait(timeout=3.0)

        # Wait briefly for status update and confirm trigger HTML & 404 handling
        time.sleep(0.1)
        status, headers, body = _http_request(base_url, "/api/trigger/toggle-clipboard")
        assert status == 200 and "text/html" in headers.get("Content-Type", "")
        assert "操作已执行" in body.decode("utf-8")
        # Turn clipboard watcher back off
        _http_request(base_url, "/api/toggle-clipboard", method="POST", payload={})

        status, _, _ = _http_request(base_url, "/api/trigger/unknown-action")
        assert status == 404
    finally:
        server.shutdown()
        server.controller.shutdown()
        server.server_close()


def test_ui_strict_de_slop_compliance_against_design_md() -> None:
    ui_html = UI_HTML_PATH.read_text(encoding="utf-8")
    app_py = (PROJECT_ROOT / "src" / "workbench" / "app.py").read_text(encoding="utf-8")

    # 1. Strictly monochrome palette (#FFFFFF, #F7F7F7, #111111, #666666, #E5E5E5)
    style_match = re.search(r"<style>(.*?)</style>", ui_html, flags=re.DOTALL)
    assert style_match, "ui.html must contain inline <style>"
    css = style_match.group(1)
    found_hex = {c.upper() for c in re.findall(r"#[0-9a-fA-F]{3,8}\b", css)}
    assert found_hex <= ALLOWED_HEX_COLORS, f"Disallowed non-monochrome colors in CSS: {found_hex - ALLOWED_HEX_COLORS}"
    assert "gradient(" not in css.lower()
    assert "box-shadow" not in css.lower()

    # 2. Zero emojis anywhere in UI HTML or trigger confirmation HTML
    assert not EMOJI_RE.findall(ui_html), f"Emojis found in ui.html: {EMOJI_RE.findall(ui_html)}"
    assert not EMOJI_RE.findall(app_py), f"Emojis found in app.py: {EMOJI_RE.findall(app_py)}"

    # 3. At most 4 font sizes (12px / 14px / 16px / 20px), minimum >= 12px
    found_sizes = set(re.findall(r"font-size\s*:\s*([0-9]+px)", css))
    assert found_sizes <= ALLOWED_FONT_SIZES, f"Disallowed font sizes: {found_sizes - ALLOWED_FONT_SIZES}"

    # 4. Required controls, tabs, copy buttons, and L1/L2/L3 ladder labels
    for required in (
        "抓今日热点",
        "剪贴板监测:",
        "伴随同看:",
        "记为项目想法",
        "拆解链接",
        "全部速览",
        "项目孵化池",
        "LLM与新模型",
        "AI学习与教程",
        "AI创作与3D工具",
        "行业深度认知",
        "复制结论",
        "复制怎么用",
        "已复制",
        "L1 基础教程与认知",
        "L2 工具与AI联动",
        "L3 一站式自动化闭环",
    ):
        assert required in ui_html, f"Missing UI element/copy: {required}"

    # 5. No gray explanatory subtitle under <h1>
    header_match = re.search(r"<header[^>]*>(.*?)</header>", ui_html, flags=re.DOTALL)
    assert header_match
    header_html = header_match.group(1)
    assert "<p" not in header_html and "subtitle" not in header_html.lower()


def test_silent_macos_app_bundle_structure_and_no_terminal(tmp_path: Path) -> None:
    app_bundle = PROJECT_ROOT / "启动静默助手.app"
    assert app_bundle.is_dir(), "Missing 启动静默助手.app bundle in repo root"

    plist_path = app_bundle / "Contents" / "Info.plist"
    launcher_path = app_bundle / "Contents" / "MacOS" / "launcher"
    assert plist_path.is_file()
    assert launcher_path.is_file()
    assert os.access(launcher_path, os.X_OK), "launcher must have executable permission"

    plist = plistlib.loads(plist_path.read_bytes())
    assert plist["LSUIElement"] is True
    assert plist["CFBundlePackageType"] == "APPL"
    assert plist["CFBundleExecutable"] == "launcher"

    script_text = launcher_path.read_text(encoding="utf-8")
    assert "Terminal" not in script_text
    assert "osascript" not in script_text
    assert "nohup" in script_text
    assert "src.workbench.app" in script_text
    assert "is_running" in script_text

    # Old Terminal-popping .command script should be gone
    assert not (PROJECT_ROOT / "运行热点创作.command").exists()

    # Rebuilding into tmp_path via build_silent_app works cleanly
    rebuilt = build_silent_app(project_root=PROJECT_ROOT, output_dir=tmp_path, port=18765)
    assert (rebuilt / "Contents" / "Info.plist").is_file()
    assert os.access(rebuilt / "Contents" / "MacOS" / "launcher", os.X_OK)


def test_all_project_source_and_test_files_within_20kb_limit() -> None:
    max_bytes = 20480
    skip_dirs = {".git", ".venv", ".pytest_cache", "__pycache__", ".obsidian", "vault", "data", ".build", "dist"}
    oversized: list[tuple[str, int]] = []

    for path in PROJECT_ROOT.rglob("*"):
        if not path.is_file():
            continue
        rel = path.relative_to(PROJECT_ROOT)
        if any(part in skip_dirs for part in rel.parts):
            continue
        if rel.name in {"uv.lock", ".DS_Store"} or rel.suffix == ".lock":
            continue
        size = path.stat().st_size
        if size > max_bytes:
            oversized.append((str(rel), size))

    assert not oversized, f"Files exceeding 20 KB limit: {oversized}"
