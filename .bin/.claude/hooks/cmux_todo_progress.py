#!/usr/bin/env python3
"""TodoWrite の状態から cmux サイドバーのプログレスバーを更新する。

対象イベント:
- PostToolUse (matcher: TodoWrite): 完了数/総数の比率を再計算して表示
- Stop / SessionStart: プログレスバーをクリア

Running / Needs input のステータスピルは cmux の Claude ラッパーが管理するため、
このフックはプログレスバー (サイドバーの別レーン) だけを触る。ラッパー側の
状態遷移とは競合しない。

Best-effort: cmux CLI が無い・$CMUX_WORKSPACE_ID 未設定なら黙って exit 0。
例外はすべて握り潰す。
"""
from __future__ import annotations

import json
import os
import shutil
import subprocess
import sys


def cmux(args: list[str]) -> None:
    if not shutil.which("cmux") or not os.environ.get("CMUX_WORKSPACE_ID"):
        return
    try:
        subprocess.run(["cmux", *args], capture_output=True, timeout=2)
    except Exception:
        pass


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    event = payload.get("hook_event_name") or ""

    if event in ("Stop", "SessionStart"):
        cmux(["clear-progress"])
        return 0

    if event == "PostToolUse" and payload.get("tool_name") == "TodoWrite":
        todos = (payload.get("tool_input") or {}).get("todos") or []
        if not todos:
            cmux(["clear-progress"])
            return 0
        total = len(todos)
        done = sum(1 for t in todos if t.get("status") == "completed")
        ratio = done / total if total > 0 else 0.0
        cmux(["set-progress", f"{ratio:.2f}", "--label", f"{done}/{total} todos"])

    return 0


if __name__ == "__main__":
    sys.exit(main())
