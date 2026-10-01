# aw-cmdlog.zsh
# 実行したコマンドを 1 回ごとに ~/.local/share/aw-insights/commands.tsv に追記する。
# HISTFILE は HIST_IGNORE_ALL_DUPS で重複を消しているため回数や並びが残らない。
# 繰り返し作業の分析 (activitywatch/aw-collect.py) 用に別途記録する。
# 形式: epoch<TAB>シェルの pid<TAB>cmux ワークスペース ID<TAB>cmux サーフェス ID
#       <TAB>カレントディレクトリ<TAB>入力したままのコマンド
# 並行して使うタブの作業が混ざらないよう、どのタブで打ったかを残す。
# cmux ワークスペース名は Claude のセッション名と同期している
# (claude/.claude/hooks/cmux_workspace_name_sync.sh) ので、ActivityWatch の
# ウィンドウタイトルや Claude のセッションと突き合わせられる。cmux 外では空欄。
# 先頭が空白のコマンドは記録しない (履歴に残したくないときの慣習に合わせる)。
# cmux がセッション復元時にシェルへ流し込む `cmux restore ...` も、自分で打った
# コマンドではなく集計のノイズになるため記録しない。
# 90 日より古い行は activitywatch/aw-prune.py が削除する。

typeset -g _AW_CMDLOG=~/.local/share/aw-insights/commands.tsv
[[ -d ${_AW_CMDLOG:h} ]] || mkdir -p ${_AW_CMDLOG:h}

_aw_cmdlog_preexec() {
    [[ $1 == ' '* || $1 == 'cmux restore '* ]] && return 0
    # 1 行 1 コマンドに保つため、改行とタブを置き換える
    local cmd=${${1//$'\n'/ ; }//$'\t'/ }
    print -r -- "${EPOCHSECONDS}	$$	${CMUX_WORKSPACE_ID:-}	${CMUX_SURFACE_ID:-}	${PWD}	${cmd}" >> $_AW_CMDLOG
}

zmodload zsh/datetime
autoload -Uz add-zsh-hook
add-zsh-hook preexec _aw_cmdlog_preexec
