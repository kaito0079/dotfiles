# ghq-fzf.zsh
# ghq で管理しているリポジトリを fzf で検索して移動する
#
# 使い方:
#   repo-switch      リポジトリを選択して移動 (コマンド)
#   Ctrl+G           同上 (キーバインド)

repo-switch() {
    if ! command -v ghq >/dev/null 2>&1; then
        echo "エラー: ghq コマンドが見つかりません" >&2
        return 1
    fi
    if ! command -v fzf >/dev/null 2>&1; then
        echo "エラー: fzf コマンドが見つかりません" >&2
        return 1
    fi

    local root
    root=$(ghq root) || return 1

    local src
    src=$(ghq list | grep -v '\.worktrees/' | fzf \
        --preview "bat --color=always --style=header,grid --line-range :80 ${root}/{}/README.* 2>/dev/null" \
        --header='リポジトリを選択して移動 (Esc でキャンセル)')

    if [ -z "$src" ]; then
        return 0
    fi

    cd "${root}/${src}" || return 1
}

# ZLE widget: キーバインドから呼び出す用
# Ctrl+G の unbind は ~/.config/zsh/keybind-overrides.zsh で集約管理
# vcs_info を明示的に再実行するのは、ZLE widget 内での cd 後に
# reset-prompt だけだと precmd が走らず vcs_info_msg_0_ が古い値のままになるため
_repo-switch-widget() {
    repo-switch
    vcs_info
    zle reset-prompt
}
zle -N _repo-switch-widget
bindkey '^g' _repo-switch-widget
