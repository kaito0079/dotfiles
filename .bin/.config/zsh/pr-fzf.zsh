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
#
# 検索対象 (fzf):
#   PR 番号 / タイトル / ブランチ名 / ラベル名 / リポジトリ / 作者
#
# 依存:
#   gh, fzf, ghq, pwt, jq, git

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
  author { login }
  repository { nameWithOwner }
  labels(first: 20) { nodes { name color } }
}'

    # jq で TSV を生成: repo \t number \t branch \t display(ANSI 付き)
    # ラベルは GitHub のカラーコードを 24bit ANSI 背景色で表示する
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

        [.data.author.nodes, .data.assignee.nodes,
         .data.reviewRequested.nodes, .data.reviewedBy.nodes]
        | add
        | map(select(. != null and .number != null and .headRefName != null))
        | unique_by(.repository.nameWithOwner + "#" + (.number|tostring))
        | sort_by(.updatedAt) | reverse
        | .[]
        | (.labels.nodes // []
           | map(select(.name != null and .color != null))
           | map(label_ansi)
           | join(" ")) as $labels
        | [
            .repository.nameWithOwner,
            (.number|tostring),
            .headRefName,
            ("#\(.number)  "
             + (if .isDraft then "[Draft] " else "" end)
             + .title
             + "  \(.headRefName)"
             + (if ($labels | length) > 0 then "  \($labels)" else "" end)
             + "  (\(.repository.nameWithOwner) @\(.author.login // "?"))"
            )
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

    local repo_full pr_num branch
    IFS=$'\t' read -r repo_full pr_num branch _ <<< "$selected"

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
