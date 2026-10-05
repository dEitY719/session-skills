#!/usr/bin/env bash
# Exercises skills/resume-after-limit/lib/load-state.py (issue #32): the
# state-file loader for Step 1 and the worktree/branch check for Step 3.
#
# Cases: (a) all fields present pass through (b) missing multi-cycle fields
# default to 1/1/305 (c) no state file -> silent exit 0 (d) broken JSON ->
# exit 1 (e) --check-context worktree mismatch -> exact [FAIL] line + exit 1
# (f) branch-only mismatch -> [WARN] + exit 0. Offline; uses a temp git repo.
set -uo pipefail

root=$(git rev-parse --show-toplevel)
helper=$root/skills/resume-after-limit/lib/load-state.py
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected '$2', got '$3'"
        fail=1
    fi
}

wt=$tmp/wt
mkdir -p "$wt/.claude"
git -C "$wt" init -q -b feat/x
state=$wt/.claude/.rate-limit-guard.json

# (a) all fields present -> values pass through, shell-quoted
cat >"$state" <<EOF
{"command": "/gh-flow:issue 7 origin", "worktree": "$wt", "branch": "feat/x",
 "max_cycles": 3, "cycles_remaining": 2, "cycle_window_min": 120}
EOF
out=$(cd "$wt" && python3 "$helper")
check "(a) exit 0" "0" "$?"
eval "$out"
check "(a) COMMAND" "/gh-flow:issue 7 origin" "$COMMAND"
check "(a) WORKTREE" "$wt" "$WORKTREE"
check "(a) BRANCH" "feat/x" "$BRANCH"
check "(a) cycles" "3/2/120" "$MAX_CYCLES/$CYCLES_REMAINING/$CYCLE_WINDOW_MIN"

# (b) multi-cycle fields missing -> 1/1/305
printf '{"command": "x", "worktree": "%s", "branch": "feat/x"}\n' "$wt" >"$state"
eval "$(python3 "$helper" "$state")"
check "(b) defaults" "1/1/305" "$MAX_CYCLES/$CYCLES_REMAINING/$CYCLE_WINDOW_MIN"

# (c) no state file -> no output, exit 0 (both modes)
out=$(python3 "$helper" "$tmp/missing.json" 2>&1)
check "(c) exit 0" "0" "$?"
check "(c) no output" "" "$out"
out=$(python3 "$helper" --check-context "$tmp/missing.json" 2>&1)
check "(c) --check-context exit 0" "0" "$?"

# (d) broken JSON -> [FAIL] + exit 1
printf '{"command": ' >"$tmp/broken.json"
out=$(python3 "$helper" "$tmp/broken.json" 2>&1)
check "(d) exit 1" "1" "$?"
check "(d) message" "[FAIL] state 파일 파싱 실패: $tmp/broken.json" "$out"

# (e) --check-context from another dir -> exact [FAIL] + exit 1
printf '{"command": "x", "worktree": "%s", "branch": "feat/x"}\n' "$wt" >"$state"
out=$(cd "$tmp" && python3 "$helper" --check-context "$state" 2>&1)
check "(e) exit 1" "1" "$?"
check "(e) message" "[FAIL] 워크트리 불일치 — 예상: $wt, 현재: $tmp." "$out"

# (e') symlinked path to the same worktree is not a mismatch
ln -s "$wt" "$tmp/link"
out=$(cd "$tmp/link" && python3 "$helper" --check-context 2>&1)
check "(e') symlink exit 0" "0" "$?"
check "(e') symlink silent" "" "$out"

# (f) right worktree, branch moved -> [WARN] + exit 0
printf '{"command": "x", "worktree": "%s", "branch": "main"}\n' "$wt" >"$state"
out=$(cd "$wt" && python3 "$helper" --check-context 2>&1)
check "(f) exit 0" "0" "$?"
check "(f) message" "[WARN] 브랜치 이동" "$out"

exit "$fail"
