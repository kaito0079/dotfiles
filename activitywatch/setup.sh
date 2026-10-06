#!/bin/bash
# ActivityWatch 関連の LaunchAgent を登録する。
# - aw-prune.py:   毎日 12:00 に保持期間 (90 日) より古い記録を削除する
# - aw-insights.sh: 毎週月曜 9:00 (週の始業時) に繰り返し作業を分析してレポートを書く
# plist にはスクリプトの絶対パスが必要なため、リポジトリの場所を解決してから書き出す。
# スリープ中だった場合は復帰時に実行される。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"

# register <ラベル> <ログ名> <StartCalendarInterval の中身> <実行するコマンド...>
register() {
    local label="$1" log="${HOME}/Library/Logs/$2.log" interval="$3"
    shift 3
    local plist="${HOME}/Library/LaunchAgents/${label}.plist"
    local args=""
    for arg in "$@"; do
        args="${args}        <string>${arg}</string>
"
    done

    mkdir -p "$(dirname "$plist")" "$(dirname "$log")"
    cat > "$plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${label}</string>
    <key>ProgramArguments</key>
    <array>
${args}    </array>
    <key>StartCalendarInterval</key>
    <dict>
${interval}
    </dict>
    <key>StandardOutPath</key>
    <string>${log}</string>
    <key>StandardErrorPath</key>
    <string>${log}</string>
</dict>
</plist>
EOF

    # 登録済みなら入れ替える
    launchctl bootout "gui/$(id -u)/${label}" 2>/dev/null || true
    launchctl bootstrap "gui/$(id -u)" "$plist"
    echo "登録しました: ${plist}"
}

register local.activitywatch.prune aw-prune "\
        <key>Hour</key><integer>12</integer>
        <key>Minute</key><integer>0</integer>" \
    /usr/bin/python3 "${SCRIPT_DIR}/aw-prune.py"

register local.activitywatch.insights aw-insights "\
        <key>Weekday</key><integer>1</integer>
        <key>Hour</key><integer>9</integer>
        <key>Minute</key><integer>0</integer>" \
    /bin/bash "${SCRIPT_DIR}/aw-insights.sh"

cat <<'EOF'

ブラウザの記録には拡張機能 aw-watcher-web が必要 (Brewfile では入らない)。
Vivaldi / Google Chrome それぞれで、Chrome ウェブストアから ActivityWatch の
Web Watcher 拡張を追加する。
EOF
