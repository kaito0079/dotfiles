#!/bin/bash
# Claude Code Status Line (2 行)
#   📁 dir (🌿 branch) │ 🤖 Model
#   ⏳5h ▓▓▓▓░░░░░░ 42% │ 📅週 ▓▓░░░░░░░░ 23%
# レート制限 (5h/週) は常時表示。色 = ペース比較:
#   緑 = 経過時間ベースの期待ペースより余裕 (まだ使える)
#   黄 = ペース超過 (このペースだとリセット前に枯渇)
#   赤 = ペース超過かつ残りわずか (使用率 RATE_RED_THRESHOLD% 以上)
#   resets_at が取れないときは無色
# コンテキスト使用率は 80% 以上のときだけ 2 行目に追加: 🧠 ████████░░ 84%

THRESHOLD=80
RATE_RED_THRESHOLD=80
GREEN=$'\033[32m'
YELLOW=$'\033[33m'
RED=$'\033[31m'
RESET=$'\033[0m'

input=$(cat)

model=$(echo "$input" | jq -r '.model.display_name // "Unknown"')
cwd=$(echo "$input" | jq -r '.workspace.current_dir // .cwd // ""')
if [ -z "$cwd" ] || [ "$cwd" = "null" ]; then
  cwd=$(pwd)
fi
short_cwd=$(basename "$cwd")

git_branch=""
if git -C "$cwd" rev-parse --git-dir >/dev/null 2>&1; then
  git_branch=$(git -C "$cwd" symbolic-ref --short HEAD 2>/dev/null || git -C "$cwd" rev-parse --short HEAD 2>/dev/null || echo "")
fi

if [ -n "$git_branch" ]; then
  line1="📁 $short_cwd (🌿 $git_branch) │ 🤖 $model"
else
  line1="📁 $short_cwd │ 🤖 $model"
fi

line2=""
append2() {
  if [ -n "$line2" ]; then line2+=" │ $1"; else line2="$1"; fi
}

# コンテキスト使用率: 閾値以上のときだけバー + % を表示
ctx_pct=$(echo "$input" | jq -r '.context_window.used_percentage // 0')
ctx_int=$(awk "BEGIN {printf \"%.0f\", ${ctx_pct:-0}}")
if [ "$ctx_int" -ge "$THRESHOLD" ] 2>/dev/null; then
  filled=$((ctx_int / 10))
  [ "$filled" -gt 10 ] && filled=10
  bar=""
  for ((i = 0; i < filled; i++)); do bar+="█"; done
  for ((i = filled; i < 10; i++)); do bar+="░"; done
  append2 "🧠 $bar ${ctx_int}%"
fi

# レート制限: 常時表示。resets_at からウィンドウ開始を逆算し、期待ペースとの比較で色付け
# $1: rate_limits 配下の jq パス, $2: ラベル, $3: ウィンドウ長 (秒)
rate_segment() {
  local pct pct_int resets filled bar i pace color reset_c
  pct=$(echo "$input" | jq -r "$1.used_percentage // empty")
  [ -z "$pct" ] && return
  pct_int=$(awk "BEGIN {printf \"%.0f\", $pct}")
  filled=$((pct_int / 10))
  [ "$filled" -gt 10 ] && filled=10

  color=""
  reset_c=""
  resets=$(echo "$input" | jq -r "$1.resets_at // empty")
  if [[ "$resets" =~ ^[0-9]+$ ]]; then
    pace=$(awk "BEGIN {p=(($3 - ($resets - $(date +%s))) / $3) * 100; if (p < 0) p = 0; if (p > 100) p = 100; printf \"%.0f\", p}")
    if [ "$pct_int" -le "$pace" ]; then
      color="$GREEN"
    elif [ "$pct_int" -ge "$RATE_RED_THRESHOLD" ]; then
      color="$RED"
    else
      color="$YELLOW"
    fi
    reset_c="$RESET"
  fi

  bar=""
  for ((i = 0; i < filled; i++)); do bar+="▓"; done
  for ((i = filled; i < 10; i++)); do bar+="░"; done
  printf '%s %s%s%s %d%%' "$2" "$color" "$bar" "$reset_c" "$pct_int"
}

seg=$(rate_segment '.rate_limits.five_hour' '⏳5h' 18000)
[ -n "$seg" ] && append2 "$seg"
seg=$(rate_segment '.rate_limits.seven_day' '📅週' 604800)
[ -n "$seg" ] && append2 "$seg"

if [ -n "$line2" ]; then
  printf '%s\n%s' "$line1" "$line2"
else
  printf '%s' "$line1"
fi
