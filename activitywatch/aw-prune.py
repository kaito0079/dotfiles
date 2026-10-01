#!/usr/bin/env python3
"""ActivityWatch のイベントのうち、保持期間 (90 日) より古いものを削除する。

記録はローカルに 90 日分だけ残す方針とする。
ActivityWatch には保持期間の設定がないため、ローカルの REST API 経由で消す。
setup.sh で登録した LaunchAgent から毎日実行される。

  python3 aw-prune.py            # 削除する
  python3 aw-prune.py --dry-run  # 削除対象の件数だけ表示する
"""

import json
import sys
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone

API = "http://localhost:5600/api/0"
RETENTION_DAYS = 90


def request(method, path):
    req = urllib.request.Request(API + path, method=method)
    with urllib.request.urlopen(req, timeout=30) as res:
        body = res.read()
    return json.loads(body) if body else None


def main():
    dry_run = "--dry-run" in sys.argv
    cutoff = datetime.now(timezone.utc) - timedelta(days=RETENTION_DAYS)
    query = urllib.parse.urlencode({"end": cutoff.isoformat(), "limit": -1})

    try:
        buckets = request("GET", "/buckets/")
    except urllib.error.URLError as e:
        # サーバーが起動していなければ新しい記録も増えないので、次回に回す
        print(f"ActivityWatch に接続できません: {e}", file=sys.stderr)
        return 1

    for bucket_id in buckets:
        bucket = urllib.parse.quote(bucket_id, safe="")
        events = request("GET", f"/buckets/{bucket}/events?{query}")
        if not dry_run:
            for event in events:
                request("DELETE", f"/buckets/{bucket}/events/{event['id']}")
        verb = "削除対象" if dry_run else "削除"
        print(f"{bucket_id}: {verb} {len(events)} 件 ({cutoff:%Y-%m-%d} より前)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
