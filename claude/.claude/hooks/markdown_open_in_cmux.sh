#!/usr/bin/env bash
# Claude が .md ファイルを Write / Edit したら、cmux のプレビューペインを
# バックグラウンドで開き、markdown viewer で確認できるようにする。
# cmux 外 (CMUX_WORKSPACE_ID 未設定) では何もしない。
set -euo pipefail

[ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0

payload="$(cat)"

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""')"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')"

case "$tool_name" in
  Write | Edit) : ;;
  *) exit 0 ;;
esac

case "$file_path" in
  *.md) : ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

# 右のプレビューペインにタブとして積む (ペインの解決と重複回避はヘルパー側)
python3 "$(dirname "$0")/cmux_preview.py" markdown "$file_path" >/dev/null 2>&1 || true
