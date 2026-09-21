# ~/.claude 設定 (dotfiles 管理分)

このディレクトリは `scripts/link.sh` により `~/.claude/` 配下へ symlink される。

## 配線

| ~/.claude/ 内のパス | 実体 | 管理リポジトリ |
| --- | --- | --- |
| `settings.json` | `claude/.claude/settings.json` | dotfiles (このリポ) |
| `hooks/` | `claude/.claude/hooks/` | dotfiles (このリポ) |
| `CLAUDE.md` | `claude/.claude/CLAUDE.md` | dotfiles (このリポ) |
| `keybindings.json` | `claude/.claude/keybindings.json` | dotfiles (このリポ) |
| `statusline.sh` | `claude-tools/status-line.sh` | [kaito0079/claude-tools](https://github.com/kaito0079/claude-tools) (submodule) |
| `skills/`, `agents/` | `claude-tools/{skills,agents}/*` | kaito0079/claude-tools (submodule) |

symlink はディレクトリ単位 (`hooks/` ごとリンク) なので、`hooks/` にファイルを
追加すると再リンク不要で即 `~/.claude/hooks/` に現れる。

## claude-tools (submodule)

スキル / エージェント / ユーティリティスクリプト / ステータスラインは、リポジトリ
ルートの `claude-tools/` に submodule として置いている。公開可能な資産とマシン
固有の配線 (`settings.json`・hook 本体) を分けるため。`scripts/link.sh` が
`~/.claude/{skills,agents}/`・`~/.local/bin/`・`~/.claude/statusline.sh` へ
symlink を張る。

```bash
# 新しいマシン: submodule ごと取得
git clone --recursive git@github.com:kaito0079/dotfiles.git ~/dotfiles

# --recursive を忘れた場合 (make link が未取得を検知して自動実行もする)
git submodule update --init claude-tools

# claude-tools の最新を取り込む (取り込み後、ポインタ更新を dotfiles に commit する)
git submodule update --remote claude-tools
```

claude-tools 側を編集したときは、**submodule 内で commit & push してから**
dotfiles 側でポインタ更新を commit する。順序が逆だと、push されていない
コミットを指した状態で dotfiles が push されてしまう。これを防ぐため、
clone 直後に以下を設定しておく (リポジトリローカル設定なのでマシンごとに必要):

```bash
git config push.recurseSubmodules on-demand
```

## フック一覧

配線は `settings.json` の `hooks` セクション。全フック共通の設計方針:
**best-effort** — 前提条件 (cmux 内・git repo 内など) を満たさなければ黙って
exit 0 し、失敗しても Claude Code の動作を絶対にブロックしない。

| スクリプト | トリガー | 何をするか | 動作条件 |
| --- | --- | --- | --- |
| `cmux_claude_status_pill.py` | SessionStart / UserPromptSubmit / Notification / Stop / SessionEnd | cmux サイドバーの `claude_code` ステータスピル (Running / Needs input) を devcontainer 内で再現する。ホストでは cmux の Claude ラッパーが同じピルを管理するため何もしない | `/.dockerenv` があり `$CMUX_WORKSPACE_ID` と `cmux` CLI がある |
| `cmux_todo_progress.py` | SessionStart / Stop / PostToolUse(TodoWrite) | TodoWrite の完了率 (`done/total`) を cmux サイドバーのプログレスバーに表示。Stop / SessionStart でクリア | `$CMUX_WORKSPACE_ID` と `cmux` CLI がある |
| `sdd_open_in_cmux.sh` | PostToolUse(Write) | SDD のフェーズドキュメント (`.docs/specs/**/*.md`) が Write されたら `cmux_preview.py` 経由でプレビュータブを開く | `$CMUX_WORKSPACE_ID` がある |
| `cmux_preview.py` | Stop (差分) / `sdd_open_in_cmux.sh` から呼び出し (markdown) | 右のプレビューペインにタブを積む (下記参照) | `$CMUX_WORKSPACE_ID` と `cmux` CLI がある。差分は git repo 内かつ `cmux enable-browser` 済み |
| `session_end_transcript_mirror.py` | Stop | git worktree で作業中のセッションのトランスクリプトを main worktree の project dir (`~/.claude/projects/<encoded-path>/`) にミラーする。worktree 横断でセッション履歴を一覧できるようにするため | git repo 内かつ main worktree 以外 |
| `cmux_workspace_name_sync.sh` | statusline 描画のたび (`statusline_entry.sh` 経由) | Claude セッション名を cmux ワークスペース名に同期する (下記参照) | `$CMUX_WORKSPACE_ID` と `cmux` CLI と `jq` がある |
| `statusline_entry.sh` | `settings.json` の `statusLine` | statusline の入力 JSON を「表示 (claude-tools の statusline.sh)」と「cmux ワークスペース名同期」に分配するエントリポイント | — |

## プレビューペイン (cmux_preview.py)

左をセッション、右を生成物の確認用として 2 分割に保つ。markdown プレビューも
差分ビューアも右ペインの**タブ**として積み、ペインが増えないようにする。

背景: cmux の `markdown open` も `diff` も既定では split するコマンドなので、
そのままフックに使うとペインが際限なく増える。`cmux open --pane <ref>` は
「同じペインにタブとして開く」挙動なのでこちらを使い、`diff` が別ペインを
作った場合は `move-surface` で右ペインへ寄せる。

| サブコマンド | 挙動 |
| --- | --- |
| `cmux_preview.py markdown <path>` | 右ペインにプレビュータブを追加。同名タブが既にあれば何もしない (ビューアがファイルを監視していて中身は自動更新されるため、開き直すとタブが重複するだけ) |
| `cmux_preview.py diff [cmux diff の引数]` | 未コミットの変更を差分ビューアで表示。古い差分タブは閉じて 1 枚に保つ。変更が無いターンではタブを触らない |

実装上のポイント:

- cmux の ref (`pane:16` など) はインデックスで、サーフェスの開閉のたびに
  振り直される。そのためキャッシュせず毎回 `cmux tree` を読み直し、
  `--id-format both` で得た UUID で対象を指定する。
- 右ペインの判定は「セッション以外で、ターミナルを含まないペイン」。
  ユーザーが手でタブを閉じても次回に作り直されるので自己修復する。
- フォーカスは操作前にフォーカスされていたペインへ戻す。右ペインを見ている
  最中に奪い返さないため。ペイン新規作成時は cmux が遅れてフォーカスを
  当て直すので、少し待ってから戻す。
- 差分は `git diff HEAD` を自前で組み立てて `cmux diff -` に標準入力で渡す。
  `cmux diff --source last-turn` / `--unstaged` は手元で内容が描画されなかった
  ため使っていない。未追跡ファイルは `git diff --no-index` で個別に足している
  (新規作成されたファイルこそ確認したいため)。
- 差分ビューアは cmux の埋め込みブラウザ上で動くため `cmux enable-browser`
  が必要。これはアプリ側の状態で dotfiles には含まれないので、新しいマシンでは
  別途実行する。ターミナルの URL が埋め込みブラウザに横取りされないよう、
  `cmux.json` で `browser.interceptTerminalOpenCommandInCmuxBrowser` と
  `browser.openTerminalLinksInCmuxBrowser` を `false` に固定している。

## cmux ワークスペース名同期の仕組み

背景: cmux のワークスペース名はデフォルトでアクティブなタブの OSC タイトルに
追従するため、複数タブを開いていると実行中コマンドで名前がころころ変わり、
どのワークスペースが何の作業か分からなくなる。

解決: Claude セッションに名前が付いたら、それを cmux ワークスペース名として
固定する。cmux では CLI (`cmux rename-workspace`) で付けた名前は「ユーザー
設定名」として扱われ、OSC タイトルや workspaceAutoNaming に上書きされない
(cmux docs/workspace-auto-naming.md)。

実装上のポイント:

- Claude Code に SessionRename のような hook イベントは無く、hook の stdin
  にもセッション名は含まれない。唯一 **statusline への入力 JSON** に
  `session_name` が含まれる (公式ドキュメント: statusline.md#available-data)。
  そのため statusLine コマンドを `statusline_entry.sh` に差し替え、そこから
  同期スクリプトへ入力を分岐している。
- `session_name` に値が入るのは `/rename` や `claude -n` で明示的に名前を
  付けたとき、または AI 生成タイトルが付いたとき。`dotfiles-82` のような
  自動派生名では空 → 同期しない。
- 前回適用した名前を `~/.claude/.cmux-ws-name-sync/<workspace-id>` に記録し、
  変わったときだけ rename する。これにより cmux 側で手動リネームした名前を
  毎秒塗り潰すことはない (セッション名が次に変わるまで手動名が生きる)。
- 同じワークスペースで複数の名前付き Claude セッションを動かすと後勝ちになる。

## statusline

`settings.json` の `statusLine` → `statusline_entry.sh` → claude-tools の
`statusline.sh` (表示本体: モデル / コンテキスト使用量 / burn rate /
日次・週次・月次トークン集計)。

## 状態ファイル (gitignore 対象・~/.claude 直下)

| パス | 書き手 | 用途 |
| --- | --- | --- |
| `.cmux-ws-name-sync/<workspace-id>` | cmux_workspace_name_sync.sh | 最後に cmux へ適用したワークスペース名 |
| `.sl_session.json` / `.sl_last_state.json` / `.sl_usage_log.csv` / `.sl_compress.json` | statusline.sh | burn rate・使用量集計・圧縮検出 |
