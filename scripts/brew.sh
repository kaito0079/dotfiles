#!/bin/bash

if [ "$(uname)" != "Darwin" ] ; then
	if [ "${DOTFILES_SKIP_UNSUPPORTED:-0}" = "1" ] ; then
		# make all 経由: 対象外の OS なので黙ってスキップする
		echo "macOS 以外のためスキップします: $(basename "$0")"
		exit 0
	fi
	# 個別に指定して実行された: 実行したいのに OS が違うのでエラーにする
	echo "エラー: $(basename "$0") は macOS 専用です (現在: $(uname))" >&2
	exit 1
fi

echo "Brewfileに記載されているパッケージをインストールします"
brew bundle --global
