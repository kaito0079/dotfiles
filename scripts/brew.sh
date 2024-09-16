#!/bin/bash

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi

echo "Brewfileに記載されているパッケージをインストールします"
brew bundle --global
