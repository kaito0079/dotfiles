#!/usr/bin/env bash
# SDD のフェーズドキュメント (.docs/specs/**/*.md) が Write されたら、
# cmux のブラウザサーフェスをバックグラウンドで開き、markdown viewer で確認できるようにする。
# cmux 外 (CMUX_WORKSPACE_ID 未設定) では何もしない。
set -euo pipefail

[ -n "${CMUX_WORKSPACE_ID:-}" ] || exit 0

payload="$(cat)"

tool_name="$(printf '%s' "$payload" | jq -r '.tool_name // ""')"
file_path="$(printf '%s' "$payload" | jq -r '.tool_input.file_path // ""')"

[ "$tool_name" = "Write" ] || exit 0

case "$file_path" in
  *"/.docs/specs/"*.md) : ;;
  *) exit 0 ;;
esac

[ -f "$file_path" ] || exit 0

cmux_bin="${CMUX_BUNDLED_CLI_PATH:-cmux}"
"$cmux_bin" markdown open "$file_path" --focus false >/dev/null 2>&1 || true
