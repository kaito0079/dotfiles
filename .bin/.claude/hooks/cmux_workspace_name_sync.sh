#!/usr/bin/env bash
# Claude セッション名を cmux ワークスペース名に同期する。
#
# Claude Code には SessionRename のような hook イベントが無く、hook の
# stdin にもセッション名は含まれない。一方 statusline への入力 JSON には
# `session_name` が含まれる (`/rename` や `claude -n` で付けた名前、または
# AI 生成タイトル。`dotfiles-82` のような自動派生名では空)。
# そこで statusline_entry.sh 経由で毎リフレッシュこのスクリプトに入力 JSON を
# 流し、名前が付いていて前回適用値と異なるときだけ rename する。
#
# cmux 側では CLI からの rename はユーザー設定名として扱われ、OSC タイトルや
# workspaceAutoNaming に上書きされない (cmux docs/workspace-auto-naming.md)。
# 前回適用値を状態ファイルに覚えておくことで、ユーザーが cmux 側で手動
# リネームした名前を、セッション名が変わらない限り塗り潰さない。
#
# Best-effort: cmux 外・CLI 無し・JSON 不正時は黙って exit 0。
set -u

[ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0
command -v jq >/dev/null 2>&1 || exit 0

cmux_bin="${CMUX_BUNDLED_CLI_PATH:-cmux}"
command -v "$cmux_bin" >/dev/null 2>&1 || exit 0

name="$(jq -r '.session_name // ""' 2>/dev/null)" || exit 0
[ -n "$name" ] || exit 0

state_dir="$HOME/.claude/.cmux-ws-name-sync"
state_file="$state_dir/$CMUX_WORKSPACE_ID"
[ -f "$state_file" ] && [ "$(cat "$state_file" 2>/dev/null)" = "$name" ] && exit 0

if "$cmux_bin" rename-workspace --workspace "$CMUX_WORKSPACE_ID" "$name" >/dev/null 2>&1; then
    mkdir -p "$state_dir"
    printf '%s' "$name" > "$state_file"
fi
exit 0
