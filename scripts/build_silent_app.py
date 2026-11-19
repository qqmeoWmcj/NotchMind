from __future__ import annotations

import argparse
import os
import plistlib
import shutil
import stat
from pathlib import Path

APP_NAME = "启动静默助手.app"
BUNDLE_ID = "com.aihotspot.workbench.launcher"
DEFAULT_HOST = "127.0.0.1"
DEFAULT_PORT = 8765


def _launcher_script(project_root: Path, host: str = DEFAULT_HOST, port: int = DEFAULT_PORT) -> str:
    fallback_root = str(project_root.resolve()).replace('"', '\\"')
    return f'''#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
CANDIDATE_ROOT="$(cd "$SCRIPT_DIR/../../.." && pwd)"
if [ -f "$CANDIDATE_ROOT/pyproject.toml" ]; then
  PROJECT_DIR="$CANDIDATE_ROOT"
else
  PROJECT_DIR="{fallback_root}"
fi

export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:/usr/bin:/bin:/usr/sbin:/sbin:${{PATH:-}}"

HOST="{host}"
PORT="{port}"
URL="http://${{HOST}}:${{PORT}}/"
STATE_URL="http://${{HOST}}:${{PORT}}/api/state"
LOG_DIR="$PROJECT_DIR/data"
LOG_FILE="$LOG_DIR/workbench.log"

mkdir -p "$LOG_DIR"

is_running() {{
  curl -fsS --max-time 1 "$STATE_URL" >/dev/null 2>&1
}}

if ! is_running; then
  UV_BIN=""
  for candidate in "$HOME/.local/bin/uv" "/opt/homebrew/bin/uv" "/usr/local/bin/uv" "$(command -v uv 2>/dev/null || true)"; do
    if [ -n "$candidate" ] && [ -x "$candidate" ]; then
      UV_BIN="$candidate"
      break
    fi
  done

  cd "$PROJECT_DIR"
  if [ -n "$UV_BIN" ]; then
    nohup "$UV_BIN" run python -m src.workbench.app --host "$HOST" --port "$PORT" </dev/null >>"$LOG_FILE" 2>&1 &
  elif [ -x "$PROJECT_DIR/.venv/bin/python" ]; then
    nohup "$PROJECT_DIR/.venv/bin/python" -m src.workbench.app --host "$HOST" --port "$PORT" </dev/null >>"$LOG_FILE" 2>&1 &
  else
    nohup python3 -m src.workbench.app --host "$HOST" --port "$PORT" </dev/null >>"$LOG_FILE" 2>&1 &
  fi
  disown 2>/dev/null || true

  for _ in $(seq 1 40); do
    if is_running; then
      break
    fi
    sleep 0.25
  done
fi

if [ "${{WORKBENCH_NO_OPEN:-0}}" != "1" ]; then
  open "$URL" >/dev/null 2>&1 || true
fi
'''


def build_silent_app(
    project_root: Path | None = None,
    output_dir: Path | None = None,
    host: str = DEFAULT_HOST,
    port: int = DEFAULT_PORT,
) -> Path:
    root = (project_root or Path(__file__).resolve().parent.parent).resolve()
    target_dir = (output_dir or root).resolve()
    app_path = target_dir / APP_NAME
    contents_dir = app_path / "Contents"
    macos_dir = contents_dir / "MacOS"

    if app_path.exists():
        shutil.rmtree(app_path)
    macos_dir.mkdir(parents=True, exist_ok=True)

    plist_data = {
        "CFBundleDevelopmentRegion": "zh_CN",
        "CFBundleDisplayName": "启动静默助手",
        "CFBundleExecutable": "launcher",
        "CFBundleIdentifier": BUNDLE_ID,
        "CFBundleInfoDictionaryVersion": "6.0",
        "CFBundleName": "启动静默助手",
        "CFBundlePackageType": "APPL",
        "CFBundleShortVersionString": "1.0.0",
        "CFBundleVersion": "1",
        "LSMinimumSystemVersion": "12.0",
        "LSUIElement": True,
        "NSHighResolutionCapable": True,
    }
    plist_bytes = plistlib.dumps(plist_data, fmt=plistlib.FMT_XML, sort_keys=True)
    (contents_dir / "Info.plist").write_bytes(plist_bytes)
    (contents_dir / "PkgInfo").write_text("APPL????", encoding="utf-8")

    launcher_path = macos_dir / "launcher"
    launcher_path.write_text(_launcher_script(root, host=host, port=port), encoding="utf-8")
    current_mode = os.stat(launcher_path).st_mode
    os.chmod(launcher_path, current_mode | stat.S_IXUSR | stat.S_IXGRP | stat.S_IXOTH)
    return app_path


def main() -> None:
    parser = argparse.ArgumentParser(description="Build silent macOS .app bundle for workbench.")
    parser.add_argument("--output-dir", type=Path, default=None, help="Directory to create the .app bundle in.")
    parser.add_argument("--host", type=str, default=DEFAULT_HOST)
    parser.add_argument("--port", type=int, default=DEFAULT_PORT)
    args = parser.parse_args()
    app_path = build_silent_app(output_dir=args.output_dir, host=args.host, port=args.port)
    print(f"Built silent app: {app_path}")


if __name__ == "__main__":
    main()
