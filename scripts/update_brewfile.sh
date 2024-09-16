#!/bin/bash

BREWFILE_PATH="$(cd "$(dirname "$0")/../" && pwd)"/.bin/.Brewfile

function update_brewfile() {
  # 現在インストールされているパッケージ一覧を取得
  installed_packages=$(brew leaves && brew list --cask)
  # .Brewfileに記載されているパッケージ一覧を取得
  brewfile_packages=$(grep -E '^(brew|cask)' ${BREWFILE_PATH} | awk '{gsub(/"/, "", $2); print $2}')

  # .Brewfileに記載されていないがインストールされているパッケージを.Brewfileに追加
  echo ".Brewfileに記載されていないがインストールされているパッケージを.Brewfileに追加します:"
  installed_any=false
  while read -r package; do
    if ! echo "$brewfile_packages" | grep -q "^$package$"; then
      installed_any=true
    fi
  done < <(echo "$installed_packages")

  if [ "$installed_any" = false ]; then
    echo "すべてのパッケージがすでに.Brewfileに記載されています。"
  else
    echo ".Brewfileの内容と実際のインストール状況が一致しません。"
    echo ".Brewfileを再生成します。"
    brew bundle dump --force --file=${BREWFILE_PATH}
  fi
}

if [ "$(uname)" != "Darwin" ] ; then
	echo "Not macOS!"
	exit 1
fi


update_brewfile
