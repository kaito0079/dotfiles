#!/usr/bin/env python3
"""ActivityWatch とシェルのコマンドログから、繰り返し作業の集計を JSON で出力する。

生のイベントは 1 日で数千件になり、そのまま Claude に渡すと読み切れないため、
「何を・何回・どの順で」だけに縮めてから aw-insights.sh に渡す。
離席中 (afk) の時間は集計から除く。

  python3 aw-collect.py            # 直近 7 日分
  python3 aw-collect.py --days 14  # 期間を変える
"""

import json
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from collections import Counter, defaultdict
from datetime import datetime, timedelta, timezone

API = "http://localhost:5600/api/0"
CMDLOG = os.path.expanduser("~/.local/share/aw-insights/commands.tsv")
TOP = 20
# これより短い滞在は通過しただけとみなし、切り替えの集計に含めない
MIN_DWELL_SEC = 3
# 連続コマンドとみなす間隔
CMD_SEQ_GAP_SEC = 300
# トークン類がそのまま Claude に渡らないよう、英字と数字が混ざった長い文字列は伏せる。
# `-` や `/` で区切られたブランチ名・パスは読めるよう対象にしない
SECRET_RE = re.compile(r"(?=[A-Za-z0-9_+=]*[0-9])(?=[A-Za-z0-9_+=]*[A-Za-z])[A-Za-z0-9_+=]{24,}")


def request(path, body=None):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(
        API + path, data=data, headers={"Content-Type": "application/json"}
    )
    with urllib.request.urlopen(req, timeout=60) as res:
        return json.loads(res.read())


def concat_buckets(var, buckets):
    """複数バケットのイベントを 1 つの変数にまとめるクエリ行を作る。"""
    lines = [f"{var} = [];"]
    for b in buckets:
        lines.append(f'{var} = concat({var}, flood(query_bucket("{b}")));')
    return lines


def query(period, buckets, afk_buckets):
    """離席していない時間帯に重なるイベントだけをサーバー側で絞り込む。

    ホスト名が変わるとバケットが分かれるため、同じ種類のバケットはまとめて扱う。
    """
    q = [
        *concat_buckets("afk", afk_buckets),
        'not_afk = filter_keyvals(afk, "status", ["not-afk"]);',
        *concat_buckets("events", buckets),
        "events = filter_period_intersect(events, not_afk);",
        "RETURN = sort_by_timestamp(events);",
    ]
    return request("/query/", {"timeperiods": [period], "query": q})[0]


def top(counter, n=TOP):
    return [[k, round(v, 1)] for k, v in counter.most_common(n)]


def minutes(sec_counter):
    return Counter({k: v / 60 for k, v in sec_counter.items()})


def ngrams(seq, n):
    return Counter(tuple(seq[i : i + n]) for i in range(len(seq) - n + 1))


def fmt_ngrams(counter, n=TOP):
    # 同じ要素の往復 (A→A) は切り替えではないので除く
    return [[" → ".join(k), c] for k, c in counter.most_common(n * 2) if len(set(k)) > 1][:n]


def summarize_window(events):
    app_sec = Counter()
    title_sec = Counter()
    title_cnt = Counter()
    switches = []
    for e in events:
        app, title = e["data"].get("app", "?"), e["data"].get("title", "")[:80]
        app_sec[app] += e["duration"]
        title_sec[f"{app} | {title}"] += e["duration"]
        title_cnt[f"{app} | {title}"] += 1
        if e["duration"] >= MIN_DWELL_SEC and (not switches or switches[-1] != app):
            switches.append(app)
    return {
        "app_minutes": top(minutes(app_sec)),
        "title_minutes": top(minutes(title_sec), 30),
        "title_visits": top(title_cnt, 30),
        "app_switch_pairs": fmt_ngrams(ngrams(switches, 2)),
        "app_switch_triples": fmt_ngrams(ngrams(switches, 3), 15),
    }


def summarize_web(events):
    domain_sec = Counter()
    url_cnt = Counter()
    visits = []
    for e in events:
        u = urllib.parse.urlsplit(e["data"].get("url", ""))
        if not u.netloc:
            continue
        domain_sec[u.netloc] += e["duration"]
        # クエリ文字列は検索語やトークンを含むため落とす
        page = u.netloc + u.path
        url_cnt[page] += 1
        if e["duration"] >= MIN_DWELL_SEC and (not visits or visits[-1] != u.netloc):
            visits.append(u.netloc)
    return {
        "domain_minutes": top(minutes(domain_sec)),
        "page_visits": top(url_cnt, 30),
        "domain_switch_pairs": fmt_ngrams(ngrams(visits, 2)),
    }


def run_ngrams(groups, gap_sec):
    """作業単位ごとに、間隔の短いコマンドの並びから 2 連・3 連を数える。

    groups は {作業単位: [(epoch, コマンド), ...]}。単位をまたいでつなげると
    並行して進めている別の作業が 1 つの手順に見えてしまうため、単位ごとに数える。
    """
    pairs, triples = Counter(), Counter()
    for seq in groups.values():
        run = []
        # 同じ秒のコマンドは記録順を保つ (コマンド名で並べ替えない)
        for ts, cmd in sorted(seq, key=lambda x: x[0]):
            if run and ts - run[-1][0] > gap_sec:
                pairs += ngrams([c for _, c in run], 2)
                triples += ngrams([c for _, c in run], 3)
                run = []
            run.append((ts, cmd))
        pairs += ngrams([c for _, c in run], 2)
        triples += ngrams([c for _, c in run], 3)
    return fmt_ngrams(pairs), fmt_ngrams(triples, 15)


def home(path):
    return path.replace(os.path.expanduser("~"), "~", 1)


def summarize_commands(since):
    """zsh の preexec フック (aw-cmdlog.zsh) が書いたログを集計する。"""
    if not os.path.exists(CMDLOG):
        return None
    rows = []
    with open(CMDLOG, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if not parts[0].isdigit():
                continue
            if len(parts) == 6:
                ts, pid, ws, surface, cwd, cmd = parts
            elif len(parts) == 4:
                # cmux の ID を記録する前の形式
                (ts, pid, cwd, cmd), ws, surface = parts, "", ""
            else:
                continue
            if int(ts) >= since:
                rows.append({
                    "ts": int(ts),
                    # 同じタブでもシェルを開き直すと pid が変わるため、サーフェス ID を優先する
                    "tab": surface or pid,
                    "ws": ws,
                    "cwd": home(cwd),
                    "cmd": SECRET_RE.sub("<redacted>", cmd),
                })

    by_tab = defaultdict(list)
    by_ws = defaultdict(list)
    for r in rows:
        by_tab[r["tab"]].append((r["ts"], r["cmd"]))
        if r["ws"]:
            by_ws[r["ws"]].append(r)
    pairs, triples = run_ngrams(by_tab, CMD_SEQ_GAP_SEC)
    # ワークスペース ID は読んでも意味がないので、一番多いディレクトリを名前代わりにする
    workspaces = [
        {
            "cwd": Counter(r["cwd"] for r in rs).most_common(1)[0][0],
            "commands": len(rs),
            "top": top(Counter(r["cmd"] for r in rs), 5),
        }
        for rs in sorted(by_ws.values(), key=len, reverse=True)[:10]
    ]
    return {
        "total": len(rows),
        "commands": top(Counter(r["cmd"] for r in rows), 30),
        "command_heads": top(Counter(" ".join(r["cmd"].split()[:2]) for r in rows)),
        "directories": top(Counter(r["cwd"] for r in rows), 15),
        "command_pairs": pairs,
        "command_triples": triples,
        "workspaces": workspaces,
    }


def main():
    days = 7
    if "--days" in sys.argv:
        days = int(sys.argv[sys.argv.index("--days") + 1])
    end = datetime.now(timezone.utc)
    start = end - timedelta(days=days)
    period = f"{start.isoformat()}/{end.isoformat()}"

    try:
        buckets = request("/buckets/")
    except urllib.error.URLError as e:
        print(f"ActivityWatch に接続できません: {e}", file=sys.stderr)
        return 1

    def find(prefix):
        return [b for b in buckets if b.startswith(prefix)]

    afk = find("aw-watcher-afk_")
    if not afk:
        print("aw-watcher-afk のバケットがありません", file=sys.stderr)
        return 1

    result = {"period": {"start": start.isoformat(), "end": end.isoformat(), "days": days}}
    # macOS は HostName 未設定だとホスト名がネットワーク次第で変わり、
    # そのたびに aw-watcher-*_<ホスト名> のバケットが増える
    result["window"] = summarize_window(query(period, find("aw-watcher-window_"), afk))
    # aw-watcher-web は拡張機能を入れたブラウザごとにバケットが分かれる
    web = find("aw-watcher-web")
    web_events = query(period, web, afk) if web else []
    result["web"] = summarize_web(web_events) if web_events else None
    result["shell"] = summarize_commands(int(start.timestamp()))

    json.dump(result, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
