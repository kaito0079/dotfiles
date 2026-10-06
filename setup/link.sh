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

# $1 のディレクトリを $2 にコピーする。Claude Code のプラグイン用。
# プラグインを symlink で置くと、パスを realpath で解決してから許可判定する
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

# Claude Code のプラグイン (kaito0079/claude-plugins) を ~/.claude/skills/<プラグイン名>/ にコピーする。
# ~/.claude/skills/ 以下に .claude-plugin/plugin.json があると、Claude Code はそのディレクトリを
# プラグイン (<名前>@skills-dir) として読み込む。symlink にしない理由は copy_one のコメントを参照。
# 別の場所に clone している場合は CLAUDE_PLUGINS_DIR で指定する。
CLAUDE_PLUGINS="${CLAUDE_PLUGINS_DIR:-${HOME}/work/github.com/kaito0079/claude-plugins}"
if [ -d "$CLAUDE_PLUGINS/plugins" ]; then
    mkdir -p "$HOME/.claude/skills"
    for plugin in "$CLAUDE_PLUGINS/plugins"/*/; do
        plugin="${plugin%/}"
        [ -f "$plugin/.claude-plugin/plugin.json" ] || continue
        copy_one "$plugin" "$HOME/.claude/skills/$(basename "$plugin")"
    done

    # リポジトリから消えた (名前を変えた・削除した) プラグインのコピーを片付ける。
    # 印のあるディレクトリだけを対象にし、手で置いたスキルには触れない。
    for dest in "$HOME/.claude/skills"/*/; do
        dest="${dest%/}"
        [ ! -L "$dest" ] && [ -f "$dest/$COPY_MARKER" ] || continue
        [ -d "$CLAUDE_PLUGINS/plugins/$(basename "$dest")" ] && continue
        rm -rf "$dest"
        removed=$((removed + 1))
        echo "  削除  ~${dest#"$HOME"} (claude-plugins に存在しないプラグインのコピー)"
    done
else
    echo ""
    echo "⚠️  Claude Code のプラグインのリポジトリがありません: ${CLAUDE_PLUGINS}"
    echo "以下で取得してから、もう一度 make link を実行してください:"
    echo "  ghq get kaito0079/claude-plugins"
    echo ""
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
