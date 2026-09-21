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
            # Raycast は macOS 専用。対象外 OS ではリンクしない
            # (link.sh 自体は OS 非依存の設定も扱うのでスクリプト全体は止めない)
            if [[ "$(basename "$item")" == "raycast-scripts" ]] && [ "$(uname)" != "Darwin" ]; then
                continue
            fi
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
