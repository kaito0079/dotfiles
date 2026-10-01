#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

created=0
updated=0
unchanged=0
backed_up=0

# $1 の実体を $2 のパスに symlink する。
# - 既に同じリンクなら何もしない (毎回 25 行出力されると差分が埋もれるため)
# - 別のリンクなら張り替える
# - 実ファイル / 実ディレクトリがある場合は破壊せず退避する。
#   新しいマシンでは OS やインストーラが用意した ~/.zshrc などが既に存在する。
link_one() {
    local src="$1" dest="$2" backup

    if [ -L "$dest" ]; then
        if [ "$(readlink "$dest")" = "$src" ]; then
            unchanged=$((unchanged + 1))
            return
        fi
        ln -fns "$src" "$dest"
        updated=$((updated + 1))
        echo "  更新  ~${dest#"$HOME"}"
        return
    fi

    if [ -e "$dest" ]; then
        backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
        mv "$dest" "$backup"
        backed_up=$((backed_up + 1))
        echo "  退避  ~${dest#"$HOME"} -> ~${backup#"$HOME"}"
    fi

    ln -fns "$src" "$dest"
    created=$((created + 1))
    echo "  作成  ~${dest#"$HOME"}"
}

# リポジトリ直下のディレクトリ 1 つが「パッケージ」= 1 ツール分の設定。
# パッケージの中は $HOME からの相対パスをそのまま再現しているので、
# 直下のドットエントリを $HOME に symlink すれば元の構造が復元される。
# (例: cmux/.config/cmux/ -> ~/.config/cmux/)
for package in "${SCRIPT_DIR}"/*/ ; do
    package="${package%/}"
    package_name="$(basename "$package")"

    # setup/ はこのスクリプト自身
    case "$package_name" in
        setup) continue ;;
    esac

    # macOS 専用のパッケージには .darwin-only を置いておく
    # (Raycast や cask 前提の Brewfile など)
    if [ -e "${package}/.darwin-only" ] && [ "$(uname)" != "Darwin" ]; then
        echo "macOS 以外のためスキップします: ${package_name}"
        continue
    fi

    for dotfile in "$package"/.??* ; do
        [ -e "$dotfile" ] || continue
        case "$(basename "$dotfile")" in
            .DS_Store|.darwin-only) continue ;;
        esac
        [[ "$dotfile" == *".example" ]] && continue  # テンプレートファイルは除外

        if [ -d "$dotfile" ] && [ ! -L "$dotfile" ]; then
            # ディレクトリは親を作成し、直下の各項目をディレクトリごとリンク
            dest_dir="${HOME}/$(basename "$dotfile")"
            mkdir -p "$dest_dir"
            for item in "$dotfile"/* "$dotfile"/.??* ; do
                [ -e "$item" ] || continue
                [[ "$(basename "$item")" == ".DS_Store" ]] && continue
                link_one "$item" "${dest_dir}/$(basename "$item")"
            done
        else
            # ファイルはそのままリンク
            link_one "$dotfile" "${HOME}/$(basename "$dotfile")"
        fi
    done
done

# .gitconfig.localが存在しない場合、テンプレートからコピーを促す
if [ ! -f "$HOME/.gitconfig.local" ] && [ -f "${SCRIPT_DIR}/git/.gitconfig.local.example" ]; then
    echo ""
    echo "⚠️  ~/.gitconfig.local が存在しません"
    echo "以下のコマンドでテンプレートからコピーし、編集してください:"
    echo "  cp ${SCRIPT_DIR}/git/.gitconfig.local.example ~/.gitconfig.local"
    echo ""
fi

echo "作成 ${created} / 更新 ${updated} / 変更なし ${unchanged} / 退避 ${backed_up}"
if [ "$backed_up" -gt 0 ]; then
    echo "⚠️  既存のファイルを .bak.<日時> に退避しました。不要なら削除してください。"
fi
