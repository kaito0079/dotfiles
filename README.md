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

- `scripts/`: セットアップ用のシェルスクリプト
- `.bin/`: カスタムコマンドやユーティリティ
- `Brewfile`: Homebrewでインストールするアプリケーションの一覧

## 参考資料

- [Macの環境をdotfilesでセットアップしてみた改](https://zenn.dev/tsukuboshi/articles/6e82aef942d9af)
- [Macの環境をdotfilesでセットアップしてみた \| DevelopersIO](https://dev.classmethod.jp/articles/joined-mac-dotfiles-customize/)
