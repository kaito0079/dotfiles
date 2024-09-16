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
zstyle ':vcs_info:git:*' stagedstr "%F{magenta}!"
zstyle ':vcs_info:git:*' unstagedstr "%F{yellow}+"
zstyle ':vcs_info:*' formats "%F{cyan}%c%u[%b]%f"
zstyle ':vcs_info:*' actionformats '[%b|%a]'
precmd () { vcs_info }

# プロンプトカスタマイズ
PROMPT='
[%B%F{red}%n@%m%f%b:%F{green}%~%f]%F{cyan}$vcs_info_msg_0_%f
%F{yellow}$%f '

# alias
alias ls='ls -GF'
alias la='ls -aGF'
alias ll='ls -lGF'

if [ "$(uname)" = "Darwin" ] ; then
    source ~/dotfiles/.bin/mac.zsh
fi
