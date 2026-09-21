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

# 履歴
# 既定は SAVEHIST=1000 で数日分しか残らず、過去の使い方を引けなかったため拡大する。
HISTFILE=~/.zsh_history
HISTSIZE=10000             # メモリ上に保持する件数
SAVEHIST=10000             # HISTFILE に保存する件数
setopt EXTENDED_HISTORY    # 実行日時も記録する (いつ使ったかを引けるようにする)
setopt INC_APPEND_HISTORY  # シェル終了時ではなく実行の都度追記する
setopt HIST_REDUCE_BLANKS  # 余分な空白を詰めて記録する
setopt HIST_IGNORE_ALL_DUPS  # 同じコマンドは古い方を削除し、一意な履歴にする
setopt HIST_SAVE_NO_DUPS     # HISTFILE にも重複を書き込まない
# SHARE_HISTORY は入れない。複数ワークスペースを並行して使うため、他タブの
# コマンドが矢印キーに混ざると追いにくい。INC_APPEND_HISTORY だけで
# HISTFILE には全タブ分が溜まるので、横断検索には支障がない。

# Load aliases
source ~/dotfiles/zsh/aliases.zsh

if [ "$(uname)" = "Darwin" ] ; then
    source ~/dotfiles/zsh/mac.zsh
fi

# vim を Homebrew 版へ変更
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

# cmux のワークスペース色を git origin URL のハッシュから自動決定 (chpwd 連動)
source ~/.config/zsh/cmux-workspace-color.zsh

# cmux サイドバーに現在の git ブランチをピル表示 (chpwd/precmd 連動)
source ~/.config/zsh/cmux-workspace-branch.zsh

# takumi guard: pip / uv のパッケージ取得をセキュアプロキシ経由に固定 (悪性パッケージ対策)
# https://shisho.dev/docs/ja/t/guard/quickstart/pypi
export PIP_INDEX_URL=https://pypi.flatt.tech/simple/
export UV_INDEX_URL=https://pypi.flatt.tech/simple/
