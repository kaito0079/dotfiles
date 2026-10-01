#!/bin/bash
# aw-prune.py を毎日実行する LaunchAgent を登録する。
# plist にはスクリプトの絶対パスが必要なため、リポジトリの場所を解決してから書き出す。

set -eu

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
LABEL="local.activitywatch.prune"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG="${HOME}/Library/Logs/aw-prune.log"

mkdir -p "$(dirname "$PLIST")" "$(dirname "$LOG")"

# 毎日 12:00 に実行する。スリープ中だった場合は復帰時に実行される。
cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>${LABEL}</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/bin/python3</string>
        <string>${SCRIPT_DIR}/aw-prune.py</string>
    </array>
    <key>StartCalendarInterval</key>
    <dict>
        <key>Hour</key>
        <integer>12</integer>
        <key>Minute</key>
        <integer>0</integer>
    </dict>
    <key>StandardOutPath</key>
    <string>${LOG}</string>
    <key>StandardErrorPath</key>
    <string>${LOG}</string>
</dict>
</plist>
EOF

# 登録済みなら入れ替える
launchctl bootout "gui/$(id -u)/${LABEL}" 2>/dev/null || true
launchctl bootstrap "gui/$(id -u)" "$PLIST"
echo "登録しました: ${PLIST}"
