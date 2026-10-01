# dotfiles

## 概要

このリポジトリは、macOSの開発環境を自動的にセットアップするための設定ファイルとスクリプトを含んでいます。

## 必要条件

- macOS
- Git
- Homebrew

## インストール方法

1. リポジトリをクローンします。

```shell
git clone https://github.com/kaito0079/dotfiles
cd dotfiles
```

2. セットアップを実行します。

```shell
make
```

このコマンドは以下の処理を順番に実行します：
- `init`: 初期設定の実行
- `link`: ドットファイルのシンボリックリンク作成
- `defaults`: macOSのシステム設定
- `brew`: Homebrewを使用したアプリケーションのインストール

## 更新方法

リポジトリの更新を適用するには、以下のコマンドを実行します。

```shell
cd dotfiles
make update
```

## ディレクトリ構成

ツール 1 つにつき 1 ディレクトリ（パッケージ）で管理する。パッケージの中は
`$HOME` からの相対パスをそのまま再現しているので、リポジトリを見ればどのツールの
設定がどこに配置されるか分かる。

```
zsh/.zshrc                    →  ~/.zshrc
git/.gitconfig                →  ~/.gitconfig
cmux/.config/cmux/cmux.json   →  ~/.config/cmux/cmux.json
claude/.claude/settings.json  →  ~/.claude/settings.json
```

- **パッケージ**: `zsh` `git` `claude` `cmux` `ghostty` `nvim` `tmux` `vim` `raycast` `homebrew` `hammerspoon` `activitywatch`
  - `setup/link.sh` がパッケージ直下のドットエントリを `$HOME` へ symlink する
  - ドットで始まらないファイル（`zsh/aliases.zsh`、`zsh/mac.zsh`）はリンクされず、
    `.zshrc` から `source ~/dotfiles/zsh/...` とパス指定で読み込む
  - `.darwin-only` を置いたパッケージ（`raycast` `cmux` `homebrew` `hammerspoon` `activitywatch`）は macOS 以外ではリンクされない
  - リンク先に**実ファイルがある場合は `.bak.<日時>` に退避**してから張る。新しいマシンで
    OS やインストーラが用意した `~/.zshrc` などを失わないため。`make link` は末尾に
    `作成 / 更新 / 変更なし / 退避 / 削除` の件数を出すので、意図しない変化に気づける
  - `claude-tools/skills/` だけは symlink ではなくコピーで `~/.claude/skills/` に置く。
    パスを realpath で解決して作業ディレクトリ外を拒否する PreToolUse hook があると、
    symlink 先の `references/` などを Read できないため。スキルを編集したら `make link` で反映する。
    claude-tools から消えたスキル（名前の変更や削除）のコピーは、`make link` が自動で削除する
  - `make unlink` で解除できる。対象はリポジトリを指す symlink と、`make link` が
    コピーしたスキルのみで、それ以外の実ファイルやリンク先の実体には触れない
- `setup/`: セットアップ用のシェルスクリプト（`make` から呼ばれる）
- `claude-tools/`: Claude Code のスキル / エージェント / ステータスライン（submodule）

## 繰り返し作業の分析 (ActivityWatch)

ActivityWatch の記録・zsh のコマンド記録・Hammerspoon の入力記録・Claude Code の
トランスクリプトを週 1 回集計し、繰り返している作業をショートカットやコマンドにする案を Claude に書かせる。
`activitywatch/` はリンク対象のドットエントリを持たず、`setup.sh` で LaunchAgent を
登録して使う。

```shell
activitywatch/setup.sh        # LaunchAgent を登録する (初回・スクリプトの場所を変えたとき)
activitywatch/aw-insights.sh  # 今すぐ分析する (--days 14 で期間を変える)
```

| ファイル | 役割 |
|---|---|
| `aw-collect.py` | 直近 N 日の記録を、回数・時間・切り替え順の JSON に集計する (ウィンドウは離席中を除く、コマンドの並びはタブ・セッションごとに数える) |
| `aw-insights.sh` | 集計結果を `claude -p` (読み取り専用ツールのみ) に渡してレポートを書かせる |
| `insights-prompt.md` | Claude への指示。出力形式や参照する設定ファイルはここで変える |
| `aw-prune.py` | 90 日より古い記録を毎日削除する |
| `hammerspoon/.hammerspoon/input-log.lua` | アプリをどうやって切り替えたか (ショートカット / Raycast / マウスなど) と、修飾キー付きの組み合わせの回数を記録する |
| `zsh/.config/zsh/aw-cmdlog.zsh` | 実行したコマンドを、どの cmux タブで打ったかと一緒に 1 回ごとに記録する (履歴は重複を消すため別に取る) |

- 出力先は `~/.local/share/aw-insights/`（`report-<日付>.md`、`summary-<日付>.json`、`commands.tsv`、`switches.tsv`、`combos.tsv`）。
  ウィンドウタイトルやコマンドがそのまま入るため、リポジトリの外に置く
- Claude のトランスクリプトは `~/.claude/projects/*/*.jsonl` を読むだけで、新たに記録はしない
- 実行ログは `~/Library/Logs/aw-insights.log` と `aw-prune.log`
- ブラウザの記録には、各ブラウザに ActivityWatch の Web Watcher 拡張を入れる必要がある (Brewfile では入らない)
- 先頭を空白にしたコマンドは記録されない
- 入力の記録は修飾キー付きの組み合わせだけで、文字入力・セキュア入力中の入力・クリックの座標は残さない

## 参考資料

- [Macの環境をdotfilesでセットアップしてみた改](https://zenn.dev/tsukuboshi/articles/6e82aef942d9af)
- [Macの環境をdotfilesでセットアップしてみた \| DevelopersIO](https://dev.classmethod.jp/articles/joined-mac-dotfiles-customize/)
