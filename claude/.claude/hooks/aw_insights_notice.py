#!/usr/bin/env python3
"""新しい繰り返し作業の分析レポートがあれば、セッションの開始時に知らせる。

activitywatch/aw-insights.sh が週 1 回 ~/.local/share/aw-insights/report-<日付>.md を
書く。macOS の通知は数秒で消えて見逃しやすいため、Claude Code を開いたときにも
知らせる。

対象イベント:
- SessionStart: 最新のレポートを、まだどのセッションでも知らせていなければ、
  提案の件数とパスをユーザーへのメッセージとして出す

レポートごとに 1 回だけ知らせる。cmux はログイン時に複数のセッションを同時に
復元するため、印のファイルを O_EXCL で作れたセッションだけが知らせる。

Best-effort: レポートが無い・読めないなら黙って exit 0。例外はすべて握り潰す。
"""
from __future__ import annotations

import glob
import json
import os
import sys

OUT_DIR = os.path.expanduser("~/.local/share/aw-insights")
# 知らせたレポートの印を置く場所。レポートと同じ名前で作る
NOTICED_DIR = os.path.join(OUT_DIR, ".noticed")


def latest_report() -> str | None:
    reports = sorted(glob.glob(os.path.join(OUT_DIR, "report-*.md")))
    return reports[-1] if reports else None


def claim(report: str) -> bool:
    """このレポートをまだ誰も知らせていなければ印を作り、True を返す。"""
    os.makedirs(NOTICED_DIR, exist_ok=True)
    marker = os.path.join(NOTICED_DIR, os.path.basename(report))
    try:
        fd = os.open(marker, os.O_CREAT | os.O_EXCL | os.O_WRONLY)
    except FileExistsError:
        return False
    os.close(fd)
    return True


def count_proposals(report: str) -> int:
    # レポートの提案は「### 1. <案の名前>」の見出しで並ぶ
    with open(report, encoding="utf-8", errors="replace") as f:
        return sum(1 for line in f if line.startswith("### "))


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0
    # compact では会話の途中なので知らせない
    if payload.get("source") == "compact":
        return 0

    report = latest_report()
    if not report or not claim(report):
        return 0

    path = report.replace(os.path.expanduser("~"), "~", 1)
    count = count_proposals(report)
    # Claude には渡さず、ユーザーへのメッセージだけにする。最初の返答で触れさせると作業の邪魔になるため
    print(json.dumps({
        "systemMessage": f"📊 新しい繰り返し作業の分析レポート (提案 {count} 件): {path}",
    }, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main())
    except Exception:
        sys.exit(0)
