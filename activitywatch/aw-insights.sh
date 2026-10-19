#!/bin/bash
# 直近の作業記録を集計し、Claude に繰り返し作業のショートカット化案を書かせる。
# setup.sh で登録した LaunchAgent から毎週起動され、前回のレポートから 13 日以上
# 経っていれば実行する (2 週間ごと)。手動ならいつでも実行できる。
#
#   ./aw-insights.sh            # 直近 14 日分
#   ./aw-insights.sh --days 7   # 期間を変える (aw-collect.py にそのまま渡す)
#   ./aw-insights.sh --scheduled  # LaunchAgent 用。前回から 13 日未満なら何もしない
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

if [ "${1:-}" = "--scheduled" ]; then
    shift
    # 手動で実行した後もそこから 2 週間空ける
    if [ -n "$(find "$OUT_DIR" -maxdepth 1 -name 'report-*.md' -mtime -13)" ]; then
        echo "前回のレポートから 13 日経っていないため飛ばしました"
        exit 0
    fi
fi
[ $# -eq 0 ] && set -- --days 14

/usr/bin/python3 "${SCRIPT_DIR}/aw-collect.py" "$@" > "$SUMMARY"

# 読み取り系のツールだけを渡し、dotfiles とスキルを置いたリポジトリ以外や編集には触れさせない
PLUGINS="${HOME}/work/github.com/kaito0079/claude-plugins"
# 書きかけを aw_insights_notice.py が拾わないよう、書き終えてから report-*.md にする
TMP="${REPORT}.tmp"
trap 'rm -f "$TMP"' EXIT
cd "$DOTFILES"
"${HOME}/.local/bin/claude" -p "$(cat "${SCRIPT_DIR}/insights-prompt.md")" \
    --tools "Read,Grep,Glob" \
    --add-dir "$PLUGINS" \
    --no-session-persistence \
    < "$SUMMARY" > "$TMP"
mv "$TMP" "$REPORT"

osascript -e "display notification \"${REPORT}\" with title \"繰り返し作業の分析ができました\"" || true

# 同じディレクトリの .env (git 管理外) に AW_SLACK_CHANNEL を書いておけば、
# 概要と提案の見出しを Slack に投稿する。
# claude.ai の Slack コネクタを使うので、Slack アプリやトークンは要らない
# shellcheck source=/dev/null
[ -f "${SCRIPT_DIR}/.env" ] && . "${SCRIPT_DIR}/.env"
if [ -n "${AW_SLACK_CHANNEL:-}" ]; then
    {
        awk '
            /^# /    { print "**" substr($0, 3) "**"; next }
            /^## 概要/ { s = 1; next }
            /^## 提案/ { s = 0; print ""; print "**提案**"; next }
            /^## /   { s = 0; next }
            /^### /  { print substr($0, 5); next }
            s && NF  { print }
        ' "$REPORT"
        echo
        echo "\`${REPORT/#$HOME/~}\`"
    } > "$TMP"
    # コネクタの接続を待ってから始めないと、ツールが見えないまま返答してしまう
    MCP_CONNECTION_NONBLOCKING=false "${HOME}/.local/bin/claude" -p \
        "標準入力の本文を、Slack のチャンネル ${AW_SLACK_CHANNEL} に一字一句変えずに投稿してください。投稿したら「投稿しました」とだけ答えてください。" \
        --tools "" \
        --allowedTools "mcp__claude_ai_Slack__slack_send_message" \
        --no-session-persistence \
        < "$TMP" || true
fi

echo "$REPORT"
