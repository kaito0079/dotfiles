# cmux-workspace-color.zsh
# cmux のワークスペース色を、現在のリポジトリのハッシュから決定して
# chpwd ごとに自動適用する。
#
# ハッシュキー:
#   1. git remote.origin.url (worktree や fork でも同じ色になる)
#   2. なければ repo root の basename
#   3. それも無ければ (= git 外) 何もしない
#
# cmux 内 (CMUX_WORKSPACE_ID が set) でなければ no-op。
# 同じ key が連続したら socket 呼び出しをスキップする。

# cmux ビルトインの 16 色 (workspace-action set-color の引数として有効)
typeset -ga _CMUX_WS_COLORS=(
    Red Crimson Orange Amber Olive Green Teal Aqua
    Blue Navy Indigo Purple Magenta Rose Brown Charcoal
)

_cmux_workspace_color_apply() {
    [[ -n "$CMUX_WORKSPACE_ID" ]] || return 0
    (( $+commands[cmux] )) || return 0

    local key
    key=$(git config --get remote.origin.url 2>/dev/null)
    if [[ -n "$key" ]]; then
        # 末尾の .git / / を剥がして表記揺れで色が分かれないようにする
        key="${key%.git}"
        key="${key%/}"
    else
        local root
        root=$(git rev-parse --show-toplevel 2>/dev/null) || return 0
        [[ -n "$root" ]] || return 0
        key="${root:t}"
    fi

    [[ "$_CMUX_WS_COLOR_KEY" == "$key" ]] && return 0
    typeset -g _CMUX_WS_COLOR_KEY="$key"

    # cksum で 32bit ハッシュを得て 16 色に分配
    local n idx color
    n=$(printf '%s' "$key" | cksum | awk '{print $1}')
    idx=$(( n % ${#_CMUX_WS_COLORS[@]} ))
    color="${_CMUX_WS_COLORS[idx+1]}"  # zsh の配列は 1-indexed

    # socket 呼び出しで shell をブロックしないよう非同期に
    { cmux workspace-action set-color "$color" >/dev/null 2>&1 } &!
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cmux_workspace_color_apply

# 起動時の PWD には chpwd が発火しないので 1 回だけ手動適用
_cmux_workspace_color_apply
