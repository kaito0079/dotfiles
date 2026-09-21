#!/bin/bash
# link.sh が張った symlink を解除する。
#
# 対象は「リポジトリを指す symlink」のみ。実ファイル / 実ディレクトリや、
# 他の場所を指すリンクには触れない。rm は symlink 自体を消すだけなので、
# リンク先の設定本体が失われることはない。
#
# リポジトリから削除済みのファイルを指す残骸も対象に含める (パッケージ一覧から
# 逆引きする方式だと拾えないため、配置先を走査する方式にしている)。

SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"
CLAUDE_TOOLS="${CLAUDE_TOOLS_DIR:-${SCRIPT_DIR}/claude-tools}"

assume_yes=0
[ "${1:-}" = "-y" ] || [ "${1:-}" = "--yes" ] && assume_yes=1

# 走査先: link.sh が実際に書き込む場所だけ。パッケージ内のドットディレクトリから
# 導出するので、パッケージが増えても追随する。
dest_dirs=("$HOME")
for package in "${SCRIPT_DIR}"/*/ ; do
    package="${package%/}"
    case "$(basename "$package")" in
        setup|claude-tools) continue ;;
    esac
    for dotfile in "$package"/.??* ; do
        [ -d "$dotfile" ] && [ ! -L "$dotfile" ] || continue
        dest_dirs+=("${HOME}/$(basename "$dotfile")")
    done
done
# claude-tools 由来の配置先
dest_dirs+=("$HOME/.claude/skills" "$HOME/.claude/agents" "$HOME/.local/bin")

# 重複を除く (macOS 標準の bash 3.2 には mapfile が無いのでループで組み立てる)
uniq_dirs=()
while IFS= read -r dir; do
    [ -n "$dir" ] && uniq_dirs+=("$dir")
done < <(printf '%s\n' "${dest_dirs[@]}" | sort -u)
dest_dirs=("${uniq_dirs[@]}")

targets=()
for dir in "${dest_dirs[@]}"; do
    [ -d "$dir" ] || continue
    while IFS= read -r link; do
        [ -n "$link" ] || continue
        target="$(readlink "$link")"
        case "$target" in
            "${SCRIPT_DIR}"/*|"${CLAUDE_TOOLS}"/*) targets+=("$link") ;;
        esac
    done < <(find "$dir" -maxdepth 1 -type l 2>/dev/null)
done

if [ "${#targets[@]}" -eq 0 ]; then
    echo "解除対象の symlink はありません。"
    exit 0
fi

echo "以下の ${#targets[@]} 件の symlink を解除します (リンク先の実体は削除しません):"
for link in "${targets[@]}"; do
    printf '  %s -> %s\n' "~${link#"$HOME"}" "$(readlink "$link")"
done

if [ "$assume_yes" -eq 0 ]; then
    printf '続行しますか? [y/N]: '
    read -r answer
    case "$answer" in
        [yY]|[yY][eE][sS]) ;;
        *) echo "中止しました。"; exit 0 ;;
    esac
fi

removed=0
for link in "${targets[@]}"; do
    rm -f "$link" && removed=$((removed + 1))
done
echo "解除 ${removed} 件"
