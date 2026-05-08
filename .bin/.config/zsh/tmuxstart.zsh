# tmuxstart.zsh
# tmux コマンドをラップし、セッション名を自動決定してアタッチ/作成する
#
# セッション名の決定優先度:
#   1. .tmuxstart ファイル (カレント → git root) の 1 行目
#   2. git repository のルート名 (basename)
#   3. カレントディレクトリ名 (basename)
#
# . と : はセッション名で使えないので _ に置換する
# set-titles on (tmux 側) と組み合わせて Ghostty 等のタブタイトルに反映される

tmux() {
    # 引数がある場合は素の tmux をそのまま実行
    if [[ $# -gt 0 ]]; then
        command tmux "$@"
        return
    fi

    # すでに tmux 内なら何もしない
    if [[ -n "$TMUX" ]]; then
        echo "[tmuxstart] Already inside a tmux session."
        return
    fi

    # git root を 1 回だけ取得 (後で .tmuxstart 探索と自動命名の両方で使う)
    local git_root
    git_root=$(git rev-parse --show-toplevel 2>/dev/null)

    # .tmuxstart ファイルを探す (カレント → git root)
    local tmuxstart_file=""
    if [[ -f ".tmuxstart" ]]; then
        tmuxstart_file=".tmuxstart"
    elif [[ -n "$git_root" && -f "$git_root/.tmuxstart" ]]; then
        tmuxstart_file="$git_root/.tmuxstart"
    fi

    # セッション名の決定
    local session_name
    if [[ -n "$tmuxstart_file" ]]; then
        session_name=$(head -1 "$tmuxstart_file" | tr -d '[:space:]')
    elif [[ -n "$git_root" ]]; then
        session_name="$(basename "$git_root")"
    else
        session_name="$(basename "$PWD")"
    fi

    # tmux セッション名で使えない文字 (. と :) を _ に置換
    session_name="${session_name//[.:]/_}"

    # バリデーション (英数字, _, - のみ)
    if [[ ! "$session_name" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        echo "[tmuxstart] Invalid session name: '$session_name', fallback to default tmux"
        command tmux
        return
    fi

    # 既存セッションがあればアタッチ、なければ新規作成
    if command tmux has-session -t "$session_name" 2>/dev/null; then
        command tmux attach-session -t "$session_name"
    else
        command tmux new-session -s "$session_name"
    fi
}
