#!/usr/bin/env python3
"""Stop hook: worktree ごとに分散するトランスクリプトを main worktree にミラーする。

Claude Code はセッションのトランスクリプトを
~/.claude/projects/<encoded-cwd>/<session>.jsonl に書き出す (<encoded-cwd> は
cwd の絶対パスの `/` と `.` を `-` に置換したもの)。git worktree で作業すると
worktree ごとに別の project dir ができ、履歴がそこに散らばってしまう。

このフックは Stop が発火するたび (アシスタントのターンごと) に、現在のセッションの
トランスクリプトを **main worktree の project dir** へコピー (更新) する。これにより
project dir を 1 つだけ走査するツール — 例えば同梱の /fewer-permission-prompts
スキル — が、worktree を跨いだリポジトリ全体の履歴を見られるようになる。

冪等性: コピー先の mtime がコピー元より古くなければコピーをスキップする。変更の無い
トランスクリプトに対する 1 ターンあたりのコストは stat() 1 回で済む。

安全性:
- cwd が git repo でない / main worktree を解決できない / cwd が既に main worktree
  と同じ (ミラー不要) 場合は黙って exit 0。
- Claude Code 側に例外を投げない。すべて握り潰して exit 0。
- tempfile + os.replace によるアトミックな書き込みなので、並行して読む側が中途半端な
  jsonl を見ることはない。
"""
from __future__ import annotations

import json
import os
import pathlib
import shutil
import subprocess
import sys
import tempfile


PROJECTS_ROOT = pathlib.Path.home() / ".claude" / "projects"


def encode_cwd(path: str) -> str:
    """Claude Code と同じエンコード規則で `/` と `.` を `-` に置換する。"""
    return path.replace("/", "-").replace(".", "-")


def main_worktree_for(cwd: str) -> str | None:
    """`cwd` を含むリポジトリの main worktree の絶対パスを返す。

    main worktree は `git worktree list --porcelain` の最初の `worktree` エントリで、
    リポジトリの主チェックアウトでもある。リンク worktree はその後に並ぶ。
    """
    try:
        out = subprocess.run(
            ["git", "-C", cwd, "worktree", "list", "--porcelain"],
            capture_output=True, text=True, timeout=2,
        )
    except (OSError, subprocess.SubprocessError):
        return None
    if out.returncode != 0:
        return None
    for line in out.stdout.splitlines():
        if line.startswith("worktree "):
            return line[len("worktree "):].strip() or None
    return None


def mirror(src: pathlib.Path, dst: pathlib.Path) -> bool:
    """dst が無いか古い場合に src を dst へコピーする。コピーしたら True を返す。"""
    try:
        src_mtime = src.stat().st_mtime
    except OSError:
        return False
    if dst.exists():
        try:
            if dst.stat().st_mtime >= src_mtime:
                return False
        except OSError:
            pass
    dst.parent.mkdir(parents=True, exist_ok=True)
    fd, tmp_path = tempfile.mkstemp(
        prefix=f".{dst.name}.", suffix=".tmp", dir=str(dst.parent)
    )
    os.close(fd)
    try:
        shutil.copy2(src, tmp_path)
        os.replace(tmp_path, dst)
    except Exception:
        try:
            os.unlink(tmp_path)
        except OSError:
            pass
        raise
    return True


def main() -> int:
    try:
        payload = json.load(sys.stdin)
    except Exception:
        return 0

    cwd = payload.get("cwd") or ""
    transcript = payload.get("transcript_path") or ""
    session_id = payload.get("session_id") or ""

    if not cwd or not transcript or not session_id:
        return 0
    if not os.path.isdir(cwd):
        return 0
    src = pathlib.Path(transcript)
    if not src.exists():
        return 0

    main_wt = main_worktree_for(cwd)
    if not main_wt:
        return 0
    if os.path.realpath(cwd) == os.path.realpath(main_wt):
        return 0  # 既に main worktree にいるのでミラー不要

    dst = PROJECTS_ROOT / encode_cwd(main_wt) / f"{session_id}.jsonl"
    try:
        mirror(src, dst)
    except Exception:
        return 0
    return 0


if __name__ == "__main__":
    sys.exit(main())
