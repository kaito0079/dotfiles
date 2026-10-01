#!/bin/bash

SCRIPT_DIR="$(cd "$(dirname "$0")/../" && pwd)"

created=0
updated=0
unchanged=0
backed_up=0
removed=0

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

# $1 のディレクトリを $2 にコピーする。スキル専用。
# スキルを symlink で置くと、パスを realpath で解決してから許可判定する
# PreToolUse hook (作業ディレクトリ外の参照を拒否するもの) に、
# references/ などの補助ファイルの Read を拒否されるため実体を置く。
# コピーした印として COPY_MARKER を置き、印のあるディレクトリだけを上書き対象にする。
# 配置先を直接編集しても次回の make link で上書きされる。
COPY_MARKER=".copied-by-dotfiles"
copy_one() {
    local src="$1" dest="$2" backup

    if [ -d "$dest" ] && [ ! -L "$dest" ] && [ -f "$dest/$COPY_MARKER" ]; then
        if diff -rq -x "$COPY_MARKER" "$src" "$dest" >/dev/null 2>&1; then
            unchanged=$((unchanged + 1))
            return
        fi
        rm -rf "$dest"
        updated=$((updated + 1))
        echo "  更新  ~${dest#"$HOME"} (コピー)"
    elif [ -L "$dest" ]; then
        rm -f "$dest"
        updated=$((updated + 1))
        echo "  更新  ~${dest#"$HOME"} (symlink -> コピー)"
    else
        if [ -e "$dest" ]; then
            backup="${dest}.bak.$(date +%Y%m%d%H%M%S)"
            mv "$dest" "$backup"
            backed_up=$((backed_up + 1))
            echo "  退避  ~${dest#"$HOME"} -> ~${backup#"$HOME"}"
        fi
        created=$((created + 1))
        echo "  作成  ~${dest#"$HOME"} (コピー)"
    fi

    cp -R "$src" "$dest"
    echo "$src" > "$dest/$COPY_MARKER"
}

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
                link_one "$item" "${dest_dir}/$(basename "$item")"
            done
        else
            # ファイルはそのままリンク
            link_one "$dotfile" "${HOME}/$(basename "$dotfile")"
        fi
    done
done

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
    # skills/ はコピー、agents/ は symlink で ~/.claude/ にぶら下げる
    # (skills をコピーにする理由は copy_one のコメントを参照)
    for sub in skills agents; do
        [ -d "$CLAUDE_TOOLS/$sub" ] || continue
        mkdir -p "$HOME/.claude/$sub"
        for item in "$CLAUDE_TOOLS/$sub"/*; do
            [ -e "$item" ] || continue
            if [ "$sub" = skills ] && [ -d "$item" ]; then
                copy_one "$item" "$HOME/.claude/$sub/$(basename "$item")"
            else
                link_one "$item" "$HOME/.claude/$sub/$(basename "$item")"
            fi
        done
    done

    # claude-tools から消えた (名前を変えた・削除した) スキルのコピーを片付ける。
    # 印のあるディレクトリだけを対象にし、手で置いたスキルには触れない。
    # 印に書かれたコピー元のパスではなく名前で判定するのは、CLAUDE_TOOLS_DIR で
    # 別の clone に切り替えたとき、古いパスがたまたま残っていることがあるため。
    if [ -d "$CLAUDE_TOOLS/skills" ]; then
        for dest in "$HOME/.claude/skills"/*/; do
            dest="${dest%/}"
            [ ! -L "$dest" ] && [ -f "$dest/$COPY_MARKER" ] || continue
            [ -d "$CLAUDE_TOOLS/skills/$(basename "$dest")" ] && continue
            rm -rf "$dest"
            removed=$((removed + 1))
            echo "  削除  ~${dest#"$HOME"} (claude-tools に存在しないスキルのコピー)"
        done
    fi

    # scripts/*.py を ~/.local/bin/<拡張子なしのコマンド名> に配置
    if [ -d "$CLAUDE_TOOLS/scripts" ]; then
        mkdir -p "$HOME/.local/bin"
        for script_file in "$CLAUDE_TOOLS/scripts"/*; do
            [ -f "$script_file" ] || continue
            [ -x "$script_file" ] || continue
            cmd_name="$(basename "$script_file")"
            case "$cmd_name" in README*|*.md) continue ;; esac
            link_one "$script_file" "$HOME/.local/bin/${cmd_name%.*}"
        done
    fi

    # status-line.sh を ~/.claude/statusline.sh に配置 (settings.json から参照)
    if [ -f "$CLAUDE_TOOLS/status-line.sh" ]; then
        link_one "$CLAUDE_TOOLS/status-line.sh" "$HOME/.claude/statusline.sh"
    fi
fi

# .gitconfig.localが存在しない場合、テンプレートからコピーを促す
if [ ! -f "$HOME/.gitconfig.local" ] && [ -f "${SCRIPT_DIR}/git/.gitconfig.local.example" ]; then
    echo ""
    echo "⚠️  ~/.gitconfig.local が存在しません"
    echo "以下のコマンドでテンプレートからコピーし、編集してください:"
    echo "  cp ${SCRIPT_DIR}/git/.gitconfig.local.example ~/.gitconfig.local"
    echo ""
fi

echo "作成 ${created} / 更新 ${updated} / 変更なし ${unchanged} / 退避 ${backed_up} / 削除 ${removed}"
if [ "$backed_up" -gt 0 ]; then
    echo "⚠️  既存のファイルを .bak.<日時> に退避しました。不要なら削除してください。"
fi
