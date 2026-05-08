# keybind-overrides.zsh
# このドットファイル群で zsh デフォルトのキーバインドを上書きしている箇所の
# 明示的な unbind を一覧でここに集める。
# 各 feature ファイル (ghq-fzf.zsh / pr-fzf.zsh など) より前に source すること。

bindkey -r '^g'   # 元: send-break           → ghq-fzf.zsh (repo-switch)
bindkey -r '^p'   # 元: up-line-or-history   → pr-fzf.zsh  (pr-switch)
