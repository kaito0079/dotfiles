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

- **パッケージ**: `zsh` `git` `claude` `cmux` `ghostty` `nvim` `tmux` `vim` `raycast` `homebrew`
  - `setup/link.sh` がパッケージ直下のドットエントリを `$HOME` へ symlink する
  - ドットで始まらないファイル（`zsh/aliases.zsh`、`zsh/mac.zsh`）はリンクされず、
    `.zshrc` から `source ~/dotfiles/zsh/...` とパス指定で読み込む
  - `.darwin-only` を置いたパッケージ（`raycast` `cmux` `homebrew`）は macOS 以外ではリンクされない
  - リンク先に**実ファイルがある場合は `.bak.<日時>` に退避**してから張る。新しいマシンで
    OS やインストーラが用意した `~/.zshrc` などを失わないため。`make link` は末尾に
    `作成 / 更新 / 変更なし / 退避` の件数を出すので、意図しない変化に気づける
- `setup/`: セットアップ用のシェルスクリプト（`make` から呼ばれる）
- `claude-tools/`: Claude Code のスキル / エージェント / ステータスライン（submodule）

## 参考資料

- [Macの環境をdotfilesでセットアップしてみた改](https://zenn.dev/tsukuboshi/articles/6e82aef942d9af)
- [Macの環境をdotfilesでセットアップしてみた \| DevelopersIO](https://dev.classmethod.jp/articles/joined-mac-dotfiles-customize/)
