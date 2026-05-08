# pwt-base.zsh
# pwt の worktree 作成先を ghq tree の外 (<ghq_root>/.worktrees) に動的セットする
#
# 目的:
#   - モバイル系プロジェクトで親ディレクトリの設定/ライブラリに影響されないよう、
#     worktree を ghq の各 repo ディレクトリから切り離した独立ツリーに置く
#   - 複数プロジェクトを同時に扱うため、repo ごとにディレクトリを分離
#   - 作業関連のディレクトリは ghq root (~/work) 配下にまとめる
#
# 配置ルール:
#   <ghq_root>/.worktrees/<host>/<owner>/<repo>/<slug>/
#   例: ~/work/.worktrees/github.com/foo/bar/feature-x/
#
# 挙動:
#   - cd で git repo (worktree 含む) に入った瞬間、
#     GIT_PARALLEL_WORKTREES_BASE に当該 repo の worktree 格納先を export する
#   - worktree の中から実行した場合も git worktree list で main repo を解決するので
#     正しい base を設定できる

_pwt_set_base() {
    git rev-parse --is-inside-work-tree >/dev/null 2>&1 || {
        unset GIT_PARALLEL_WORKTREES_BASE
        return
    }

    local main_repo ghq_root rel
    main_repo="$(git worktree list --porcelain 2>/dev/null \
        | awk '/^worktree /{print substr($0,10); exit}')"
    [ -n "$main_repo" ] || return

    ghq_root="$(ghq root 2>/dev/null)" || return
    [[ "$main_repo" == "$ghq_root"/* ]] || return

    rel="${main_repo#$ghq_root/}"   # <host>/<owner>/<repo>
    export GIT_PARALLEL_WORKTREES_BASE="$ghq_root/.worktrees/$rel"
    [ -d "$GIT_PARALLEL_WORKTREES_BASE" ] || mkdir -p "$GIT_PARALLEL_WORKTREES_BASE"
}

autoload -U add-zsh-hook
add-zsh-hook chpwd _pwt_set_base
_pwt_set_base
