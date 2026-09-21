#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

# リポジトリ直下のディレクトリ 1 つが「パッケージ」= 1 ツール分の設定。
# パッケージの中は $HOME からの相対パスをそのまま再現しているので、
# 直下のドットエントリを $HOME に symlink すれば元の構造が復元される。
# (例: cmux/.config/cmux/ -> ~/.config/cmux/)
for package in "${SCRIPT_DIR}"/*/ ; do
    package="${package%/}"
    package_name="$(basename "$package")"

    # setup/ はこのスクリプト自身、claude-tools/ は submodule (下部で個別に扱う)
    case "$package_name" in
        setup|claude-tools) continue ;;
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
                ln -fnsv "$item" "$dest_dir"
            done
        else
            # ファイルはそのままリンク
            ln -fnsv "$dotfile" "$HOME"
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

# claude-tools (submodule) の公開資産を本マシンに symlink する。
# (skills/agents/scripts は他人にも勧められる shareable artifact として claude-tools 側に置く)
# 別の場所に clone したものを使いたい場合は CLAUDE_TOOLS_DIR で上書きする。
CLAUDE_TOOLS="${CLAUDE_TOOLS_DIR:-${SCRIPT_DIR}/claude-tools}"

# --recursive なしで clone した場合、submodule が空ディレクトリのままになり
# 以降のループが黙って空振りするため、未取得ならここで取得する。
if [ -z "${CLAUDE_TOOLS_DIR:-}" ] && [ ! -d "$CLAUDE_TOOLS/skills" ]; then
    echo "claude-tools submodule を取得します..."
    git -C "$SCRIPT_DIR" submodule update --init claude-tools
fi

if [ -d "$CLAUDE_TOOLS" ]; then
    # skills/ と agents/ を ~/.claude/ にぶら下げる
    for sub in skills agents; do
        [ -d "$CLAUDE_TOOLS/$sub" ] || continue
        mkdir -p "$HOME/.claude/$sub"
        for item in "$CLAUDE_TOOLS/$sub"/*; do
            [ -e "$item" ] || continue
            ln -fnsv "$item" "$HOME/.claude/$sub"
        done
    done

    # scripts/*.py を ~/.local/bin/<拡張子なしのコマンド名> に配置
    if [ -d "$CLAUDE_TOOLS/scripts" ]; then
        mkdir -p "$HOME/.local/bin"
        for script_file in "$CLAUDE_TOOLS/scripts"/*; do
            [ -f "$script_file" ] || continue
            [ -x "$script_file" ] || continue
            cmd_name="$(basename "$script_file")"
            case "$cmd_name" in README*|*.md) continue ;; esac
            ln -fnsv "$script_file" "$HOME/.local/bin/${cmd_name%.*}"
        done
    fi

    # status-line.sh を ~/.claude/statusline.sh に配置 (settings.json から参照)
    if [ -f "$CLAUDE_TOOLS/status-line.sh" ]; then
        ln -fnsv "$CLAUDE_TOOLS/status-line.sh" "$HOME/.claude/statusline.sh"
    fi
fi
