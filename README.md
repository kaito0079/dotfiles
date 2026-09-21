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

- `scripts/`: セットアップ用のシェルスクリプト（`make` から呼ばれる）
- `.bin/`: `$HOME` に配置する設定一式
  - **ドットで始まるエントリ**は `link.sh` が `$HOME` 配下へ symlink する。
    `$HOME` の構造をそのまま写す形（`.zshrc` → `~/.zshrc`、`.config/cmux` → `~/.config/cmux`）
  - **ドットで始まらないエントリ**（`aliases.zsh`、`mac.zsh`）はリンクされず、
    `.zshrc` から `source ~/dotfiles/.bin/...` とパス指定で読み込む
  - `.config/raycast-scripts` のような macOS 専用のものは、対象外 OS ではリンクされない
- `claude-tools/`: Claude Code のスキル / エージェント / ステータスライン（submodule）
- `Brewfile`: Homebrewでインストールするアプリケーションの一覧

## 参考資料

- [Macの環境をdotfilesでセットアップしてみた改](https://zenn.dev/tsukuboshi/articles/6e82aef942d9af)
- [Macの環境をdotfilesでセットアップしてみた \| DevelopersIO](https://dev.classmethod.jp/articles/joined-mac-dotfiles-customize/)
