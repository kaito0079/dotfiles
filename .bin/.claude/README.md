# ~/.claude 設定 (dotfiles 管理分)

このディレクトリは `scripts/link.sh` により `~/.claude/` 配下へ symlink される。

## 配線

| ~/.claude/ 内のパス | 実体 | 管理リポジトリ |
| --- | --- | --- |
| `settings.json` | `.bin/.claude/settings.json` | dotfiles (このリポ) |
| `hooks/` | `.bin/.claude/hooks/` | dotfiles (このリポ) |
| `CLAUDE.md` | `.bin/.claude/CLAUDE.md` | dotfiles (このリポ) |
| `keybindings.json` | `.bin/.claude/keybindings.json` | dotfiles (このリポ) |
| `statusline.sh` | `claude-tools/status-line.sh` | [kaito0079/claude-tools](https://github.com/kaito0079/claude-tools) |
| `skills/`, `agents/` | `claude-tools/{skills,agents}/*` | kaito0079/claude-tools |

symlink はディレクトリ単位 (`hooks/` ごとリンク) なので、`hooks/` にファイルを
追加すると再リンク不要で即 `~/.claude/hooks/` に現れる。

## フック一覧

配線は `settings.json` の `hooks` セクション。全フック共通の設計方針:
**best-effort** — 前提条件 (cmux 内・git repo 内など) を満たさなければ黙って
exit 0 し、失敗しても Claude Code の動作を絶対にブロックしない。

| スクリプト | トリガー | 何をするか | 動作条件 |
| --- | --- | --- | --- |
| `cmux_claude_status_pill.py` | SessionStart / UserPromptSubmit / Notification / Stop / SessionEnd | cmux サイドバーの `claude_code` ステータスピル (Running / Needs input) を devcontainer 内で再現する。ホストでは cmux の Claude ラッパーが同じピルを管理するため何もしない | `/.dockerenv` があり `$CMUX_WORKSPACE_ID` と `cmux` CLI がある |
| `cmux_todo_progress.py` | SessionStart / Stop / PostToolUse(TodoWrite) | TodoWrite の完了率 (`done/total`) を cmux サイドバーのプログレスバーに表示。Stop / SessionStart でクリア | `$CMUX_WORKSPACE_ID` と `cmux` CLI がある |
| `sdd_open_in_cmux.sh` | PostToolUse(Write) | SDD のフェーズドキュメント (`.docs/specs/**/*.md`) が Write されたら cmux の markdown viewer をバックグラウンドで開く | `$CMUX_WORKSPACE_ID` がある |
| `session_end_transcript_mirror.py` | Stop | git worktree で作業中のセッションのトランスクリプトを main worktree の project dir (`~/.claude/projects/<encoded-path>/`) にミラーする。worktree 横断でセッション履歴を一覧できるようにするため | git repo 内かつ main worktree 以外 |
| `cmux_workspace_name_sync.sh` | statusline 描画のたび (`statusline_entry.sh` 経由) | Claude セッション名を cmux ワークスペース名に同期する (下記参照) | `$CMUX_WORKSPACE_ID` と `cmux` CLI と `jq` がある |
| `statusline_entry.sh` | `settings.json` の `statusLine` | statusline の入力 JSON を「表示 (claude-tools の statusline.sh)」と「cmux ワークスペース名同期」に分配するエントリポイント | — |

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
