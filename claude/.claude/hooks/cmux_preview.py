#!/usr/bin/env python3
"""cmux の右ペインを「生成物の確認用」として固定し、そこにタブを積むヘルパー。

左 (セッションのペイン) と右 (プレビュー用ペイン) の 2 分割を維持し、markdown
プレビューも差分ビューアも右ペインのタブとして開く。cmux のコマンドは既定では
split するため、放っておくとペインがどんどん増える。ここで挙動を揃える。

使い方:
    cmux_preview.py markdown <path>   markdown をプレビュータブとして開く
    cmux_preview.py diff [args...]    差分ビューアを開く (既定は --last-turn)

設計方針は他のフックと同じ best-effort。前提 (cmux 内で動いている・cmux CLI が
ある) を満たさなければ黙って exit 0 し、失敗しても Claude Code をブロックしない。

cmux の ref (pane:1 など) はインデックスであり、サーフェスの開閉で振り直される。
そのためキャッシュせず、毎回 `cmux tree` を読み直して UUID で対象を指定する。
"""

from __future__ import annotations

import os
import re
import subprocess
import sys
import time
from dataclasses import dataclass, field

UUID = r"[0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}"
PANE_RE = re.compile(rf"pane (pane:\d+) ({UUID})")
SURFACE_RE = re.compile(rf'surface (surface:\d+) ({UUID}) \[(\w+)\] "(.*?)"')
DIFF_URL_PREFIX = "cmux-diff-viewer://"


@dataclass
class Surface:
    ref: str
    uuid: str
    kind: str
    title: str
    line: str

    @property
    def is_diff(self) -> bool:
        return DIFF_URL_PREFIX in self.line


@dataclass
class Pane:
    ref: str
    uuid: str
    focused: bool = False
    surfaces: list[Surface] = field(default_factory=list)

    @property
    def has_terminal(self) -> bool:
        return any(s.kind == "terminal" for s in self.surfaces)


def cmux_bin() -> str:
    for key in ("CMUX_CLAUDE_HOOK_CMUX_BIN", "CMUX_BUNDLED_CLI_PATH"):
        value = os.environ.get(key)
        if value:
            return value
    return "cmux"


def run(*args: str) -> str | None:
    """cmux コマンドを実行して stdout を返す。失敗したら None。"""
    try:
        proc = subprocess.run(
            [cmux_bin(), *args],
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, "CMUX_QUIET": "1"},
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout


def run_stdin(data: str, *args: str) -> str | None:
    """標準入力を渡して cmux コマンドを実行する。"""
    try:
        proc = subprocess.run(
            [cmux_bin(), *args],
            input=data,
            capture_output=True,
            text=True,
            timeout=10,
            env={**os.environ, "CMUX_QUIET": "1"},
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if proc.returncode != 0:
        return None
    return proc.stdout


def read_tree(workspace: str) -> tuple[list[Pane], Pane | None, Pane | None]:
    """現ワークスペースのペイン一覧と、セッションのペイン・プレビューペインを返す。"""
    out = run("tree", "--workspace", workspace, "--id-format", "both")
    if not out:
        return [], None, None

    panes: list[Pane] = []
    session: Pane | None = None
    for line in out.splitlines():
        pane_match = PANE_RE.search(line)
        if pane_match:
            panes.append(Pane(pane_match.group(1), pane_match.group(2), "[focused]" in line))
            continue
        surface_match = SURFACE_RE.search(line)
        if surface_match and panes:
            pane = panes[-1]
            pane.surfaces.append(
                Surface(
                    surface_match.group(1),
                    surface_match.group(2),
                    surface_match.group(3),
                    surface_match.group(4),
                    line,
                )
            )
            # "◀ here" は呼び出し元のサーフェス = セッションのペイン
            if "◀ here" in line:
                session = pane

    # プレビューペイン = セッション以外で、ターミナルを含まないペイン
    preview = next(
        (p for p in panes if p is not session and p.surfaces and not p.has_terminal),
        None,
    )
    return panes, session, preview


def selected_workspace() -> str | None:
    """ウィンドウが現在選択しているワークスペースの UUID を返す。"""
    out = run("list-windows")
    if not out:
        return None
    m = re.search(r"selected_workspace=([0-9A-Fa-f-]{36})", out)
    return m.group(1) if m else None


def restore_focus(pane: Pane | None, was_selected: bool) -> None:
    """操作前にフォーカスされていたペインへ戻す。

    ユーザーが意図してプレビュー側を見ている場合にフォーカスを奪わないよう、
    セッション側へ固定せず「元々フォーカスされていたペイン」に戻す。

    ただし cmux の focus-pane はワークスペースごと切り替える。裏で動いている
    セッションがこれを呼ぶと、ユーザーが見ている画面を奪ってしまうため、
    自分のワークスペースが選択中のときだけフォーカスを触る。
    """
    if pane is None or not was_selected:
        return
    # ペインを新規作成した直後は cmux 側が遅れて新サーフェスへフォーカスを
    # 当て直すため、少し待ってから戻す。
    time.sleep(0.2)
    run("focus-pane", "--pane", pane.uuid)


def cmd_markdown(path: str) -> int:
    workspace = os.environ.get("CMUX_WORKSPACE_ID")
    surface = os.environ.get("CMUX_SURFACE_ID")
    if not workspace or not os.path.isfile(path):
        return 0

    path = os.path.abspath(path)
    name = os.path.basename(path)
    was_selected = selected_workspace() == workspace
    panes, _, preview = read_tree(workspace)
    focused = next((p for p in panes if p.focused), None)

    if preview is None:
        # 右ペインがまだ無いので、split して作る (以後はここに積む)
        if surface:
            run("markdown", "open", path, "--surface", surface,
                "--direction", "right", "--focus", "false")
        else:
            run("markdown", "open", path, "--direction", "right", "--focus", "false")
        restore_focus(focused, was_selected)
        return 0

    # 同じファイルのタブが既にあれば何もしない。markdown ビューアはファイルを
    # 監視していて中身が自動更新されるため、開き直すとタブが重複するだけ。
    if any(s.kind == "markdown" and s.title == name for s in preview.surfaces):
        return 0

    run("open", path, "--pane", preview.uuid, "--no-focus")
    restore_focus(focused, was_selected)
    return 0


def git(*args: str) -> str:
    """git の出力を返す。失敗時は空文字 (差分が無い場合も空)。"""
    try:
        proc = subprocess.run(
            ["git", *args], capture_output=True, text=True, timeout=10
        )
    except (OSError, subprocess.SubprocessError):
        return ""
    return proc.stdout


def build_patch() -> str:
    """未コミットの変更をパッチとして組み立てる。

    cmux diff の --source 系 (last-turn / unstaged) は手元で期待どおりに
    内容を描画できなかったため、パッチを標準入力で渡す経路を使う。
    git diff HEAD には未追跡ファイルが含まれないので、--no-index で個別に
    足している (新規作成されたファイルこそ確認したいため)。
    """
    if not git("rev-parse", "--is-inside-work-tree").strip():
        return ""

    patch = git("diff", "HEAD")
    for name in git("ls-files", "--others", "--exclude-standard").splitlines():
        if name:
            patch += git("diff", "--no-index", "--", os.devnull, name)
    return patch


def cmd_diff(extra: list[str]) -> int:
    workspace = os.environ.get("CMUX_WORKSPACE_ID")
    if not workspace:
        return 0

    patch = build_patch()
    was_selected = selected_workspace() == workspace
    panes, _, preview = read_tree(workspace)
    focused = next((p for p in panes if p.focused), None)
    # 既存の差分タブを控えておく。新しい方を開いてから閉じることで、
    # プレビューペインが一瞬空になって畳まれるのを避ける。
    stale = [s.uuid for p in panes for s in p.surfaces if s.is_diff]

    if not patch.strip():
        # 未コミットの変更が無いなら差分タブも残さない。残すとコミット前の
        # 内容を表示したままになり、実態と食い違うため。
        for uuid in stale:
            run("close-surface", "--surface", uuid)
        if stale:
            restore_focus(focused, was_selected)
        return 0

    out = run_stdin(patch, "diff", "-", *extra, "--no-focus")
    if out is None:
        return 0

    created = re.search(r"surface=(surface:\d+)", out)
    created_pane = re.search(r"pane=(pane:\d+)", out)
    if created is None:
        return 0
    surface_ref = created.group(1)

    # 差分は新しいペインに split されることがある。その場合はプレビューペインへ寄せる。
    if preview is not None and created_pane is not None and created_pane.group(1) != preview.ref:
        run("move-surface", "--surface", surface_ref, "--pane", preview.uuid, "--focus", "false")

    run("rename-tab", "--surface", surface_ref, f"差分 {time.strftime('%H:%M')}")

    for uuid in stale:
        run("close-surface", "--surface", uuid)

    restore_focus(focused, was_selected)
    return 0


def main(argv: list[str]) -> int:
    if os.environ.get("CMUX_WORKSPACE_ID") is None:
        return 0
    if len(argv) < 2:
        return 0
    command = argv[1]
    if command == "markdown":
        return cmd_markdown(argv[2]) if len(argv) > 2 else 0
    if command == "diff":
        return cmd_diff(argv[2:])
    return 0


if __name__ == "__main__":
    try:
        sys.exit(main(sys.argv))
    except Exception:
        # フックは何があっても Claude Code をブロックしない
        sys.exit(0)
