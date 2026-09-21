#!/usr/bin/env bash
# statusline のエントリポイント (settings.json の statusLine から呼ばれる)。
# 表示本体は claude-tools 由来の ~/.claude/statusline.sh に委譲しつつ、
# 同じ入力 JSON を cmux ワークスペース名同期にも流す。
# 同期はバックグラウンド実行なので statusline の描画をブロックしない。
set -u

input="$(cat)"

printf '%s' "$input" | bash "$HOME/.claude/hooks/cmux_workspace_name_sync.sh" >/dev/null 2>&1 &

if [ -f "$HOME/.claude/statusline.sh" ]; then
    printf '%s' "$input" | bash "$HOME/.claude/statusline.sh"
fi
