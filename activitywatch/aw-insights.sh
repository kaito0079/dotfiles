#!/bin/bash
# 直近の作業記録を集計し、Claude に繰り返し作業のショートカット化案を書かせる。
# setup.sh で登録した LaunchAgent から週 1 回実行される。手動でも実行できる。
#
#   ./aw-insights.sh            # 直近 7 日分
#   ./aw-insights.sh --days 14  # 期間を変える (aw-collect.py にそのまま渡す)
#
# 集計にはウィンドウタイトルやコマンドがそのまま入るため、出力はリポジトリの外に置く。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DOTFILES="$(dirname "$SCRIPT_DIR")"
OUT_DIR="${HOME}/.local/share/aw-insights"
TODAY="$(date +%Y-%m-%d)"
SUMMARY="${OUT_DIR}/summary-${TODAY}.json"
REPORT="${OUT_DIR}/report-${TODAY}.md"

mkdir -p "$OUT_DIR"
/usr/bin/python3 "${SCRIPT_DIR}/aw-collect.py" "$@" > "$SUMMARY"

# 読み取り系のツールだけを渡し、dotfiles とスキルを置いたリポジトリ以外や編集には触れさせない
PLUGINS="${HOME}/work/github.com/kaito0079/claude-plugins"
cd "$DOTFILES"
"${HOME}/.local/bin/claude" -p "$(cat "${SCRIPT_DIR}/insights-prompt.md")" \
    --tools "Read,Grep,Glob" \
    --add-dir "$PLUGINS" \
    --no-session-persistence \
    < "$SUMMARY" > "$REPORT"

osascript -e "display notification \"${REPORT}\" with title \"繰り返し作業の分析ができました\"" || true
echo "$REPORT"
