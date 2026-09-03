#!/usr/bin/env python3
"""devcontainer 内でのみ、cmux の claude_code ステータスピルを再現する。

ホストでは cmux の Claude ラッパーがピル (Running / Needs input) を管理するが、
devcontainer 経由の起動はラッパーを通らないため、hooks から同じキー
(claude_code) を set_status して再現する。ホスト (非コンテナ) では何もしない。

対象イベント:
- SessionStart / Stop / Notification: Needs input (入力待ち)
- UserPromptSubmit: Running
- SessionEnd: ピルを消す

Best-effort: cmux ラッパー CLI が無い・失敗した場合は黙って exit 0。
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys

RUNNING = ("Running", "sparkle", "#34C759")
NEEDS_INPUT = ("Needs input", "bell.fill", "#4C8DFF")

EVENT_STATUS = {
    "SessionStart": NEEDS_INPUT,
    "UserPromptSubmit": RUNNING,
    "Stop": NEEDS_INPUT,
    "Notification": NEEDS_INPUT,
}


def cmux(args: list[str]) -> None:
    try:
        subprocess.run(["cmux", *args], capture_output=True, timeout=3)
    except Exception:
        pass


def main() -> int:
    # コンテナ内 + cmux 連携が配線されているときだけ動く
    if not os.path.exists("/.dockerenv"):
        return 0
    if not os.environ.get("CMUX_WORKSPACE_ID") or not shutil.which("cmux"):
        return 0

    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    event = payload.get("hook_event_name") or ""

    if event == "SessionEnd":
        cmux(["clear-status", "claude_code"])
        return 0

    status = EVENT_STATUS.get(event)
    if status:
        value, icon, color = status
        cmux(["set-status", "claude_code", value, "--icon", icon, "--color", color])
    return 0


if __name__ == "__main__":
    sys.exit(main())
