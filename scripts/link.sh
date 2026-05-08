#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

for dotfile in "${SCRIPT_DIR}"/.bin/.??* ; do
    [[ "$dotfile" == "${SCRIPT_DIR}/.git" ]] && continue
    [[ "$dotfile" == "${SCRIPT_DIR}/.github" ]] && continue
    [[ "$dotfile" == "${SCRIPT_DIR}/.DS_Store" ]] && continue
    [[ "$dotfile" == *".example" ]] && continue  # テンプレートファイルは除外

    if [ -d "$dotfile" ] && [ ! -L "$dotfile" ]; then
        # ディレクトリは親を作成し、直下の各項目をディレクトリごとリンク
        dest_dir="${HOME}/$(basename "$dotfile")"
        mkdir -p "$dest_dir"
        for item in "$dotfile"/* "$dotfile"/.??* ; do
            [ -e "$item" ] || continue
            [[ "$(basename "$item")" == ".DS_Store" ]] && continue
            ln -fnsv "$item" "$dest_dir"
        done
    else
        # ファイルはそのままリンク
        ln -fnsv "$dotfile" "$HOME"
    fi
done

# .gitconfig_privateが存在しない場合、テンプレートからコピーを促す
if [ ! -f "$HOME/.gitconfig.local" ] && [ -f "${SCRIPT_DIR}/.bin/.gitconfig.local.example" ]; then
    echo ""
    echo "⚠️  ~/.gitconfig.local が存在しません"
    echo "以下のコマンドでテンプレートからコピーし、編集してください:"
    echo "  cp ${SCRIPT_DIR}/.bin/.gitconfig.local.example ~/.gitconfig.local"
    echo ""
fi
