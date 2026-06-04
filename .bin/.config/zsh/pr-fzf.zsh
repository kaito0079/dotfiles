# pr-fzf.zsh
# 全プロジェクト横断で「自分が作業する open PR」を fzf 選択 → worktree に移動する
#
# 使い方:
#   pr-switch        PR を選択して worktree に移動 (コマンド)
#   Ctrl+P           同上 (キーバインド)
#
# 検索スコープ (union):
#   - author:@me              自分が作成した PR
#   - assignee:@me            Assignees に自分が入っている PR
#   - review-requested:@me    Reviewers に自分が指名されている PR (未レビュー)
#   - reviewed-by:@me         自分が一度レビューした PR (追跡・再レビュー候補)
#   いずれも state:open に限定
#
# 選択後の挙動:
#   - ローカルに repo が無ければ ghq get で clone
#   - Enter: 既存 worktree があればそこへ cd し fetch + ff-merge、無ければ pwt で新規作成
#   - レビュー用途 (author/assignee に含まれず review-requested/reviewed-by のみで
#     ヒットした PR) は <ghq_root>/.worktrees/<repo>/review/<branch> に配置する
#
# 検索対象 (fzf):
#   PR 番号 / タイトル / ブランチ名 / ラベル名 / リポジトリ / 作者
#
# 依存:
#   gh, fzf, ghq, pwt, jq, git

# upstream を origin/<branch> に設定する。
# - 既に設定済みなら no-op
# - fork PR (isCrossRepository=true) はそもそも origin にブランチが無いのでスキップ
# - それ以外は GraphQL から得た PR head OID を使って refs/remotes/origin/<branch> を
#   直接 update-ref する。"+refs/heads/<branch>:refs/remotes/origin/<branch>" の
#   fetch は GitHub の ref advertise の transient lag で時々 "couldn't find remote
#   ref" で落ちるため使わない (ローカルには pull/<N>/head 経由で同じ OID の commit
#   が既に入っているので update-ref に必要な object は揃っている前提)。
_pr_ensure_upstream() {
    local branch="$1"
    local is_fork="$2"
    local head_oid="$3"

    if git rev-parse --abbrev-ref "$branch@{upstream}" >/dev/null 2>&1; then
        return 0
    fi

    if [ "$is_fork" = "true" ]; then
        echo "ℹ️  fork PR のため upstream 設定をスキップしました"
        return 0
    fi

    if [ -z "$head_oid" ]; then
        echo "⚠️  PR head OID が無く upstream 設定をスキップしました" >&2
        return 1
    fi

    if ! git update-ref "refs/remotes/origin/$branch" "$head_oid"; then
        echo "⚠️  refs/remotes/origin/$branch の更新に失敗しました" >&2
        return 1
    fi

    git branch --set-upstream-to="origin/$branch" "$branch" >/dev/null \
        && echo "✓ upstream を origin/$branch に設定しました"
}

pr-switch() {
    for cmd in gh fzf ghq pwt jq git; do
        command -v $cmd >/dev/null 2>&1 || {
            echo "エラー: $cmd が見つかりません" >&2
            return 1
        }
    done

    echo "PR 一覧を取得中..." >&2

    # 4 つの検索を 1 回の GraphQL コールにまとめる
    # REST の gh search prs と違い headRefName / labels を一括取得できる
    local gql='
query {
  author: search(query: "is:open is:pr author:@me", type: ISSUE, first: 100) {
    nodes { ... on PullRequest { ...prFields } }
  }
  assignee: search(query: "is:open is:pr assignee:@me", type: ISSUE, first: 100) {
    nodes { ... on PullRequest { ...prFields } }
  }
  reviewRequested: search(query: "is:open is:pr review-requested:@me", type: ISSUE, first: 100) {
    nodes { ... on PullRequest { ...prFields } }
  }
  reviewedBy: search(query: "is:open is:pr reviewed-by:@me", type: ISSUE, first: 100) {
    nodes { ... on PullRequest { ...prFields } }
  }
}
fragment prFields on PullRequest {
  number
  title
  isDraft
  updatedAt
  headRefName
  headRefOid
  isCrossRepository
  author { login }
  repository { nameWithOwner }
  labels(first: 20) { nodes { name color } }
}'

    # jq で TSV を生成: repo \t number \t branch \t display(ANSI 付き) \t kind \t is_fork \t head_oid
    # ラベルは GitHub のカラーコードを 24bit ANSI 背景色で表示する
    # kind は own / review (author/assignee に含まれず review 系のみでヒットしたら review)
    # is_fork / head_oid は upstream 設定 (refs/remotes/origin/<branch> を直接組み立てる) で使う
    local rows
    rows=$(gh api graphql -f query="$gql" | jq -r '
        def hex_to_int:
          reduce (ascii_downcase | explode[]) as $c (0;
            . * 16 + (if $c >= 48 and $c <= 57 then $c - 48
                      elif $c >= 97 and $c <= 102 then $c - 87
                      else 0 end)
          );

        def label_ansi:
          (.color[0:2] | hex_to_int) as $r |
          (.color[2:4] | hex_to_int) as $g |
          (.color[4:6] | hex_to_int) as $b |
          (($r * 299 + $g * 587 + $b * 114) / 1000) as $lum |
          (if $lum > 128 then "30" else "97" end) as $fg |
          "[48;2;\($r);\($g);\($b);\($fg)m \(.name) [0m";

        def tag($s):
          map(select(. != null and .number != null and .headRefName != null)
              | . + {_source: $s});

        [ ((.data.author.nodes // [])          | tag("own")),
          ((.data.assignee.nodes // [])        | tag("own")),
          ((.data.reviewRequested.nodes // []) | tag("review")),
          ((.data.reviewedBy.nodes // [])      | tag("review")) ]
        | add
        | group_by(.repository.nameWithOwner + "#" + (.number|tostring))
        | map(.[0] + {_sources: (map(._source) | unique)})
        | sort_by(.updatedAt) | reverse
        | .[]
        | (.labels.nodes // []
           | map(select(.name != null and .color != null))
           | map(label_ansi)
           | join(" ")) as $labels
        | ((._sources | index("own")) == null) as $is_review
        | [
            .repository.nameWithOwner,
            (.number|tostring),
            .headRefName,
            ("#\(.number)  "
             + (if $is_review then "[Review] " else "" end)
             + (if .isDraft then "[Draft] " else "" end)
             + .title
             + "  \(.headRefName)"
             + (if ($labels | length) > 0 then "  \($labels)" else "" end)
             + "  (\(.repository.nameWithOwner) @\(.author.login // "?"))"
            ),
            (if $is_review then "review" else "own" end),
            (.isCrossRepository | tostring),
            .headRefOid
          ]
        | @tsv
    ')

    if [ -z "$rows" ]; then
        echo "該当する PR が見つかりません" >&2
        echo "  (author:@me ∪ assignee:@me ∪ review-requested:@me ∪ reviewed-by:@me, state:open)" >&2
        return 1
    fi

    # preview はデフォルト非表示、? で toggle (不要な API コールを避けるため)
    # --ansi でラベルの色を反映する
    local selected
    selected=$(printf '%s\n' "$rows" | fzf \
        --ansi \
        --delimiter=$'\t' \
        --with-nth=4 \
        --preview 'gh pr view {2} -R {1}' \
        --preview-window='right:60%:wrap:hidden' \
        --bind '?:toggle-preview' \
        --header='enter: worktree / ?: preview / esc: cancel')

    [ -z "$selected" ] && return 0

    local repo_full pr_num branch kind is_fork head_oid
    IFS=$'\t' read -r repo_full pr_num branch _display kind is_fork head_oid <<< "$selected"

    if [ -z "$repo_full" ] || [ -z "$pr_num" ] || [ -z "$branch" ]; then
        echo "エラー: PR 情報のパースに失敗しました" >&2
        return 1
    fi

    # ghq path を解決。無ければ clone
    local repo_path
    repo_path=$(ghq list -p | awk -v r="/$repo_full\$" '$0 ~ r {print; exit}')
    if [ -z "$repo_path" ]; then
        echo "ローカルに無いので clone します: $repo_full"
        ghq get "github.com/$repo_full" || return 1
        repo_path=$(ghq list -p | awk -v r="/$repo_full\$" '$0 ~ r {print; exit}')
        if [ -z "$repo_path" ]; then
            echo "エラー: clone 後にも repo が見つかりません" >&2
            return 1
        fi
    fi

    # 既存 worktree を問い合わせ
    local existing_wt
    existing_wt=$(git -C "$repo_path" worktree list --porcelain \
        | awk -v b="refs/heads/$branch" '
            /^worktree /{p=substr($0,10)}
            $0=="branch " b{print p; exit}
        ')

    # --- 既存 worktree がある場合: cd して最新化 ---
    if [ -n "$existing_wt" ]; then
        echo "既存 worktree を使用: $existing_wt"
        cd "$existing_wt" || return 1

        echo "最新を取得中..."
        if ! git fetch origin "pull/$pr_num/head"; then
            echo "⚠️  fetch に失敗しました" >&2
            return 1
        fi

        # この経路は元々 upstream を触っていなかったため、過去に未設定のまま
        # 作られた worktree を再訪したケースが恒久的に直らなかった。
        # ここで一度だけ拾い直す (設定済みなら no-op)。
        _pr_ensure_upstream "$branch" "$is_fork" "$head_oid"

        # uncommitted changes があれば更新をスキップ
        if ! git diff --quiet || ! git diff --cached --quiet; then
            echo "⚠️  uncommitted changes があるため更新をスキップしました"
            echo "   現在の worktree: $(git rev-parse --short HEAD)"
            echo "   PR の head     : $(git rev-parse --short FETCH_HEAD)"
            return 0
        fi

        if git merge --ff-only FETCH_HEAD 2>/dev/null; then
            echo "✓ 最新に更新しました ($(git rev-parse --short HEAD))"
        else
            echo "⚠️  ff-merge できません (force-push 等で diverged の可能性)"
            echo "   現在の worktree: $(git rev-parse --short HEAD)"
            echo "   PR の head     : $(git rev-parse --short FETCH_HEAD)"
            echo "   上書きする場合: git reset --hard FETCH_HEAD"
        fi
        return 0
    fi

    # --- 既存 worktree が無い場合: pwt で新規作成 ---
    cd "$repo_path" || return 1

    if ! git show-ref --verify --quiet "refs/heads/$branch"; then
        echo "PR #$pr_num (branch: $branch) を fetch 中..."
        if ! git fetch origin "pull/$pr_num/head:$branch"; then
            echo "エラー: PR の fetch に失敗しました" >&2
            return 1
        fi
    fi

    # upstream を origin/<branch> に貼る (pwt switch 後の worktree でも引き継がれる)
    _pr_ensure_upstream "$branch" "$is_fork" "$head_oid"

    # レビュー用途は <base>/review/<branch> に配置する
    # GIT_PARALLEL_WORKTREES_BASE は pwt-base.zsh の chpwd フックで <ghq_root>/.worktrees/<repo> に export 済み
    # pwt switch 成功時は cd → chpwd で自動的に再計算されるため、明示復元は失敗パスのみ必要
    if [ "$kind" = "review" ]; then
        if [ -z "${GIT_PARALLEL_WORKTREES_BASE:-}" ]; then
            echo "エラー: GIT_PARALLEL_WORKTREES_BASE が未設定です (pwt-base.zsh が読み込まれていない可能性)" >&2
            return 1
        fi
        local _prev_base="$GIT_PARALLEL_WORKTREES_BASE"
        local _review_base="$_prev_base/review"
        mkdir -p "$_review_base" || { echo "エラー: $_review_base の作成に失敗しました" >&2; return 1; }
        export GIT_PARALLEL_WORKTREES_BASE="$_review_base"
        pwt switch -c "$branch"
        local _rc=$?
        if [ "$_rc" -ne 0 ]; then
            export GIT_PARALLEL_WORKTREES_BASE="$_prev_base"
        fi
        return $_rc
    fi

    pwt switch -c "$branch"
}

# ZLE widget: キーバインドから呼び出す用
# Ctrl+P の unbind は ~/.config/zsh/keybind-overrides.zsh で集約管理
# vcs_info を明示的に再実行するのは、ZLE widget 内での cd 後に
# reset-prompt だけだと precmd が走らず vcs_info_msg_0_ が古い値のままになるため
_pr-switch-widget() {
    pr-switch
    vcs_info
    zle reset-prompt
}
zle -N _pr-switch-widget
bindkey '^p' _pr-switch-widget
