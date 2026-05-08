# 補完機能を有効にする
autoload -Uz compinit
compinit -u
if [ -e /opt/homebrew/bin/zsh/zsh-completions ]; then
    fpath=(/opt/homebrew/bin/zsh/zsh-completions $fpath)
fi

# 補完機能で小文字でも大文字にマッチさせる
zstyle ':completion:*' matcher-list 'm:{a-z}={A-Z}'

# 補完機能を詰めて表示
setopt list_packed

# 補完候補一覧をカラー表示
autoload colors
zstyle ':completion:*' list-colors ''

# git
export PATH="/opt/homebrew/opt/git/bin:$PATH"
autoload -Uz vcs_info
setopt prompt_subst
zstyle ':vcs_info:git:*' check-for-changes true
zstyle ':vcs_info:git:*' stagedstr " !"
zstyle ':vcs_info:git:*' unstagedstr " +"
zstyle ':vcs_info:*' formats $' \ue0a0 %b%c%u'
zstyle ':vcs_info:*' actionformats $' \ue0a0 %b|%a'
precmd () { vcs_info }

# プロンプトカスタマイズ
PROMPT='
%K{117}%F{black} %~ %k%f%K{75}%F{black}$vcs_info_msg_0_ %k%f
%F{red}❯%f '

# Load aliases
source ~/dotfiles/.bin/aliases.zsh

if [ "$(uname)" = "Darwin" ] ; then
    source ~/dotfiles/.bin/mac.zsh
fi

# vimをHomevrew版へ変更
export PATH="/opt/homebrew/bin:$PATH"

# Claude Codeのインストールで追加
export PATH="$HOME/.local/bin:$PATH"

# worktree用の自作ツールの登録
source "${XDG_DATA_HOME:-$HOME/.local/share}/pwt/pwt.sh"

# pwt の worktree 配置先を <ghq_root>/.worktrees/<host>/<owner>/<repo>/ に動的セット
source ~/.config/zsh/pwt-base.zsh

# .tmuxstartがあるディレクトリは自動でtmuxを起動する
source ~/.config/zsh/tmuxstart.zsh

# fzf 共通デフォルト (tmux 内は中央ポップアップ表示)
source ~/.config/zsh/fzf-defaults.zsh

# 上書きする zsh デフォルトキーバインドの明示的 unbind (一覧)
source ~/.config/zsh/keybind-overrides.zsh

# ghq で管理しているリポジトリを fzf で検索して移動 (repo-switch / Ctrl+G)
source ~/.config/zsh/ghq-fzf.zsh

# GitHub の PR を fzf で検索して worktree に移動する (pr-switch / Ctrl+P)
source ~/.config/zsh/pr-fzf.zsh
