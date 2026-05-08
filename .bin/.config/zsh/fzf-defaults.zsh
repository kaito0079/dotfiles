# fzf-defaults.zsh
# fzf 共通デフォルト設定
# - tmux 内: 中央ポップアップ表示 (--tmux は fzf 0.53+)
# - tmux 外: 通常の下部表示 (+ rounded border, reverse layout)
#
# FZF_DEFAULT_OPTS は既存値があれば保持して追記する

if [ -n "$TMUX" ]; then
    # tmux 内: 画面中央に 80% × 70% のポップアップ
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --tmux center,80%,70% --border=rounded --layout=reverse"
else
    # tmux 外: 画面下部 40%、上から表示
    export FZF_DEFAULT_OPTS="${FZF_DEFAULT_OPTS:-} --height=40% --border=rounded --layout=reverse"
fi
