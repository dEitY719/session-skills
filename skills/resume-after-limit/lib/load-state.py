#!/usr/bin/env python3
"""Load the rate-limit-guard state file for session:resume-after-limit.

Usage:
  load-state.py [state-path]                  # Step 1: KEY=value lines
  load-state.py --check-context [state-path]  # Step 3: worktree/branch check

Default state-path: .claude/.rate-limit-guard.json (worktree root = cwd).

Default mode prints shell-quoted COMMAND, WORKTREE, BRANCH, MAX_CYCLES,
CYCLES_REMAINING, CYCLE_WINDOW_MIN lines for `eval "$(python3 ...)"`.
Missing multi-cycle fields default to 1 / 1 / 305 (single-cycle behavior).

--check-context compares realpath(pwd) with realpath(WORKTREE): mismatch
prints the [FAIL] line to stderr and exits 1; a branch mismatch prints
[WARN] and exits 0.

No state file: prints nothing, exit 0 (both modes). Broken JSON: exit 1.
"""
import json
import os
import shlex
import subprocess
import sys

DEFAULT_PATH = ".claude/.rate-limit-guard.json"
DEFAULTS = {"max_cycles": 1, "cycles_remaining": 1, "cycle_window_min": 305}
FIELDS = ("command", "worktree", "branch",
          "max_cycles", "cycles_remaining", "cycle_window_min")


def load(path):
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
        if not isinstance(data, dict):
            raise ValueError("top level is not an object")
    except (ValueError, OSError):
        print(f"[FAIL] state 파일 파싱 실패: {path}", file=sys.stderr)
        sys.exit(1)
    state = {}
    for key in FIELDS:
        value = data.get(key)
        if value is None:
            value = DEFAULTS.get(key, "")
        state[key] = str(value)
    return state


def current_branch():
    try:
        out = subprocess.run(["git", "branch", "--show-current"],
                             capture_output=True, text=True, check=True)
        return out.stdout.strip() or "unknown"
    except (OSError, subprocess.CalledProcessError):
        return "unknown"


def check_context(state):
    pwd_now = os.environ.get("PWD") or os.getcwd()
    worktree = state["worktree"]
    # An empty worktree must not realpath() to cwd and pass silently.
    if not worktree or os.path.realpath(pwd_now) != os.path.realpath(worktree):
        print(f"[FAIL] 워크트리 불일치 — 예상: {worktree}, 현재: {pwd_now}.",
              file=sys.stderr)
        sys.exit(1)
    if current_branch() != state["branch"]:
        print("[WARN] 브랜치 이동", file=sys.stderr)


def main(argv):
    check = "--check-context" in argv
    rest = [a for a in argv if a != "--check-context"]
    path = rest[0] if rest else DEFAULT_PATH
    if not os.path.exists(path):
        return 0
    state = load(path)
    if check:
        check_context(state)
    else:
        for key in FIELDS:
            print(f"{key.upper()}={shlex.quote(state[key])}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
