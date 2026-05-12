# cmux-workspace-branch.zsh
# git の現在ブランチを cmux のワークスペース description (タイトル下の説明行)
# として表示する。set-status の pill は claude_code ピルに優先順位で負けて
# 隠れることが多いため description を使う。
# chpwd (cd) と precmd (git checkout などコマンド後) で更新。
# cmux 外 (CMUX_WORKSPACE_ID 未設定) では完全 no-op。

_cmux_workspace_branch_apply() {
    [[ -n "$CMUX_WORKSPACE_ID" ]] || return 0
    (( $+commands[cmux] )) || return 0

    local branch
    branch=$(git symbolic-ref --short HEAD 2>/dev/null)
    if [[ -z "$branch" ]]; then
        # detached HEAD の場合は短縮 SHA を表示
        local sha
        sha=$(git rev-parse --short HEAD 2>/dev/null) && branch="@${sha}"
    fi

    # 値が変わってなければ socket を叩かない
    [[ "$_CMUX_WS_BRANCH" == "$branch" ]] && return 0
    typeset -g _CMUX_WS_BRANCH="$branch"

    if [[ -z "$branch" ]]; then
        { cmux workspace-action clear-description >/dev/null 2>&1 } &!
        return 0
    fi

    { cmux workspace-action set-description "$branch" >/dev/null 2>&1 } &!
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _cmux_workspace_branch_apply
add-zsh-hook precmd _cmux_workspace_branch_apply

# 初回適用
_cmux_workspace_branch_apply
