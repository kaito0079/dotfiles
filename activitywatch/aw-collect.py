#!/usr/bin/env python3
"""ActivityWatch・シェルのコマンドログ・Hammerspoon の入力ログ・Claude のトランスクリプト
から、繰り返し作業の集計を JSON で出力する。

生のイベントは 1 日で数千件になり、そのまま Claude に渡すと読み切れないため、
「何を・何回・どの順で」だけに縮めてから aw-insights.sh に渡す。
離席中 (afk) の時間は集計から除く。

  python3 aw-collect.py            # 直近 7 日分
  python3 aw-collect.py --days 14  # 期間を変える
"""

import glob
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
# hammerspoon/.hammerspoon/input-log.lua が書く
SWITCHES = os.path.expanduser("~/.local/share/aw-insights/switches.tsv")
COMBOS = os.path.expanduser("~/.local/share/aw-insights/combos.tsv")
TOP = 20
# これより短い滞在は通過しただけとみなし、切り替えの集計に含めない
MIN_DWELL_SEC = 3
# 連続コマンドとみなす間隔
CMD_SEQ_GAP_SEC = 300
# トークン類がそのまま Claude に渡らないよう、英字と数字が混ざった長い文字列は伏せる。
# `-` や `/` で区切られたブランチ名・パスは読めるよう対象にしない
SECRET_RE = re.compile(r"(?=[A-Za-z0-9_+=]*[0-9])(?=[A-Za-z0-9_+=]*[A-Za-z])[A-Za-z0-9_+=]{24,}")
# 作業中とみなすイベントの間隔 (これより空いたら中断していたとみなす)
ACTIVE_GAP_SEC = 300
CLAUDE_PROJECTS = os.path.expanduser("~/.claude/projects")
# Claude はコマンドを続けて実行するので、人より短い間隔で区切る
CLAUDE_SEQ_GAP_SEC = 120
CD_PREFIX_RE = re.compile(r"^cd \S+ && ")
SLASH_RE = re.compile(r"<command-name>(/[^<]+)</command-name>")
# Slack のウィンドウタイトル「<名前>（チャンネル） - <ワークスペース> - … - Slack」から名前と種類を取る。
# 先頭の「! 」「* 」は未読の印。ワークスペース名以降は使わない
SLACK_TITLE_RE = re.compile(r"^[!*]?\s*(.+?)(?:（(チャンネル|DM)）)?\s+-\s")


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


def summarize_slack(events):
    """Slack のチャンネル・DM ごとの訪問回数と滞在時間を、ウィンドウタイトルから集計する。"""
    sec, visits, kinds = Counter(), Counter(), {}
    last = None
    for e in events:
        if e["data"].get("app") != "Slack":
            last = None
            continue
        m = SLACK_TITLE_RE.match(e["data"].get("title", ""))
        if not m:
            continue
        name, kind = m.group(1), m.group(2)
        # 種類の付かないタイトルは「アクティビティ」「スレッド」などの画面
        kinds[name] = {"チャンネル": "channel", "DM": "dm"}.get(kind, "view")
        sec[name] += e["duration"]
        if e["duration"] >= MIN_DWELL_SEC and name != last:
            visits[name] += 1
            last = name
    if not visits:
        return None
    return [
        {"name": name, "kind": kinds[name], "visits": n, "minutes": round(sec[name] / 60, 1)}
        for name, n in visits.most_common(30)
    ]


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


def read_tsv(path, since):
    """1 列目が epoch 秒の TSV を読み、since 以降の行を返す。"""
    if not os.path.exists(path):
        return []
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.rstrip("\n").split("\t")
            if parts[0].isdigit() and int(parts[0]) >= since:
                rows.append(parts)
    return rows


def summarize_switches(since):
    """アプリをどうやって切り替えたか (input-log.lua の switches.tsv) を切り替え先ごとに集計する。

    ショートカットを設定していないのか、設定しているのに使えていないのかを見分ける材料にする。
    """
    rows = [r for r in read_tsv(SWITCHES, since) if len(r) == 5]
    if not rows:
        return None
    by_app = defaultdict(lambda: {"total": 0, "how": Counter(), "shortcuts": Counter(), "mouse": Counter(), "raycast_sec": []})
    for _, src, dst, how, detail in rows:
        a = by_app[dst]
        a["total"] += 1
        a["how"][how] += 1
        if how == "shortcut":
            a["shortcuts"][detail] += 1
        elif how == "mouse":
            a["mouse"][detail] += 1
        elif how == "raycast" and detail.isdigit():
            a["raycast_sec"].append(int(detail))
    apps = []
    for name, a in sorted(by_app.items(), key=lambda x: x[1]["total"], reverse=True)[:20]:
        sec = a["raycast_sec"]
        apps.append({
            "app": name,
            "switches": a["total"],
            "how": dict(a["how"].most_common()),
            # 同じ組み合わせで毎回同じアプリに移っていれば、そのアプリへのショートカットとして登録済み
            "shortcuts_used": top(a["shortcuts"], 5),
            "mouse_places": dict(a["mouse"].most_common()),
            "raycast_median_sec": sorted(sec)[len(sec) // 2] if sec else None,
        })
    return {
        "since": datetime.fromtimestamp(int(rows[0][0]), timezone.utc).isoformat(),
        "total": len(rows),
        "how": dict(Counter(r[3] for r in rows).most_common()),
        "by_target_app": apps,
    }


def summarize_combos(since):
    """修飾キー付きの組み合わせの回数 (input-log.lua の combos.tsv) をアプリごとに集計する。"""
    counts = defaultdict(Counter)
    for r in read_tsv(COMBOS, since):
        if len(r) == 4 and r[3].isdigit():
            counts[r[1]][r[2]] += int(r[3])
    if not counts:
        return None
    ranked = sorted(counts.items(), key=lambda x: sum(x[1].values()), reverse=True)[:15]
    return [{"app": app, "total": sum(c.values()), "top": top(c, 10)} for app, c in ranked]


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


def parse_ts(value):
    return int(datetime.fromisoformat(value.replace("Z", "+00:00")).timestamp())


def short_bash(cmd):
    """Claude の Bash コマンドを、集計で揃うように先頭行・cd を除いた形に縮める。"""
    first = cmd.strip().splitlines()[0] if cmd.strip() else ""
    first = CD_PREFIX_RE.sub("", first)
    return SECRET_RE.sub("<redacted>", first)[:100]


def summarize_claude(since):
    """Claude Code のトランスクリプト (~/.claude/projects/*/*.jsonl) を集計する。

    ターミナルでの作業の多くは Claude に任せているため、自分で打つコマンドより
    「何を頼み、Claude が何を実行したか」の方が繰り返しを表す。
    """
    # session_end_transcript_mirror.py が main worktree 側に複製を置くため、
    # 同じセッション ID のファイルは最後に更新された 1 つだけを読む
    latest = {}
    for path in glob.glob(os.path.join(CLAUDE_PROJECTS, "*", "*.jsonl")):
        mtime = os.path.getmtime(path)
        if mtime < since:
            continue
        sid = os.path.basename(path)
        if sid not in latest or mtime > latest[sid][0]:
            latest[sid] = (mtime, path)
    if not latest:
        return None

    sessions = []
    prompts, slash, tools, bash = [], Counter(), Counter(), Counter()
    bash_by_session = {}
    for _, path in latest.values():
        info = {"title": "", "cwd": "", "branch": "", "prompts": 0, "bash": 0, "first": None, "last": None, "active": 0}
        seq = []
        with open(path, encoding="utf-8", errors="replace") as f:
            for line in f:
                try:
                    d = json.loads(line)
                except ValueError:
                    continue
                if d.get("aiTitle"):
                    info["title"] = d["aiTitle"]
                if d.get("isSidechain") or "timestamp" not in d:
                    continue
                ts = parse_ts(d["timestamp"])
                if ts < since:
                    continue
                if info["last"] is not None and 0 < ts - info["last"] <= ACTIVE_GAP_SEC:
                    info["active"] += ts - info["last"]
                info["first"] = info["first"] or ts
                info["last"] = ts
                info["cwd"] = info["cwd"] or home(d.get("cwd", ""))
                info["branch"] = d.get("gitBranch") or info["branch"]
                content = (d.get("message") or {}).get("content")
                if d.get("type") == "user" and isinstance(content, str):
                    m = SLASH_RE.search(content)
                    if m:
                        slash[m.group(1)] += 1
                    elif (d.get("origin") or {}).get("kind") == "human":
                        info["prompts"] += 1
                        prompts.append((ts, SECRET_RE.sub("<redacted>", " ".join(content.split()))[:120]))
                elif d.get("type") == "assistant" and isinstance(content, list):
                    for c in content:
                        if c.get("type") != "tool_use":
                            continue
                        tools[c.get("name", "?")] += 1
                        if c.get("name") == "Bash":
                            cmd = short_bash((c.get("input") or {}).get("command", ""))
                            bash[cmd] += 1
                            seq.append((ts, cmd))
                            info["bash"] += 1
        if info["first"] is None:
            continue
        sessions.append(info)
        bash_by_session[path] = seq

    pairs, triples = run_ngrams(bash_by_session, CLAUDE_SEQ_GAP_SEC)
    # 何日もかけて再開するセッションがあるため、最初と最後の差ではなく作業していた時間で並べる
    sessions.sort(key=lambda s: s["active"], reverse=True)
    return {
        "sessions": len(sessions),
        "busiest_sessions": [
            {
                "title": s["title"][:60],
                "cwd": s["cwd"],
                "branch": s["branch"],
                "active_minutes": round(s["active"] / 60),
                "prompts": s["prompts"],
                "bash": s["bash"],
            }
            for s in sessions[:15]
        ],
        # 言い回しが毎回違うので回数では揃わない。新しい順に並べて傾向を読ませる
        "recent_prompts": [p for _, p in sorted(prompts, reverse=True)[:80]],
        "slash_commands": top(slash),
        "tools": top(tools),
        "bash_commands": top(bash, 30),
        "bash_heads": top(Counter(" ".join(c.split()[:2]) for c in bash.elements())),
        "bash_pairs": pairs,
        "bash_triples": triples,
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
    window_events = query(period, find("aw-watcher-window_"), afk)
    result["window"] = summarize_window(window_events)
    result["slack"] = summarize_slack(window_events)
    # aw-watcher-web は拡張機能を入れたブラウザごとにバケットが分かれる
    web = find("aw-watcher-web")
    web_events = query(period, web, afk) if web else []
    result["web"] = summarize_web(web_events) if web_events else None
    result["shell"] = summarize_commands(int(start.timestamp()))
    result["switches"] = summarize_switches(int(start.timestamp()))
    result["combos"] = summarize_combos(int(start.timestamp()))
    result["claude"] = summarize_claude(int(start.timestamp()))

    json.dump(result, sys.stdout, ensure_ascii=False, indent=1)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main())
