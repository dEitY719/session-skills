#!/usr/bin/env bash
# Exercises skills/rate-limit-guard/references/compute-fire-time.py — the
# fire-time helper shared by rate-limit-guard's Step 2 (absolute anchor) and
# resume-after-limit's Step 4 (relative offset, added by issue #6's Check 12
# fix: one script instead of hand-written python -c one-liners).
#
# What is covered: relative mode always lands in the future; absolute mode
# rolls to tomorrow when today's HH:MM + buffer has already passed; both
# modes emit the 5-field `<min> <hour> <dom> <month> <iso>` line.
set -uo pipefail

root=$(git rev-parse --show-toplevel)
helper=$root/skills/rate-limit-guard/references/compute-fire-time.py
fail=0

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected '$2', got '$3'"
        fail=1
    fi
}

# --- relative mode: --in N ---
out=$(python3 "$helper" --in 10)
check "relative mode: 5 space-separated fields" "5" "$(wc -w <<<"$out")"

iso=$(awk '{print $5}' <<<"$out")
diff=$(python3 -c "from datetime import datetime; print(int((datetime.fromisoformat('$iso') - datetime.now()).total_seconds()))")
# allow a few seconds of test-run slop around the expected 600s (10 min)
if [ "$diff" -ge 590 ] && [ "$diff" -le 650 ]; then
    echo "ok    relative mode: fires ~10 minutes out (${diff}s)"
else
    echo "FAIL  relative mode: expected ~600s out, got ${diff}s"
    fail=1
fi

# --- absolute mode: rolls to tomorrow when already past today ---
# Anchor on *today's* current HH:MM with buffer -1 (one minute ago) rather
# than "now - 1 hour": the latter can land on yesterday's clock time when run
# near midnight, which stops being "past today" and breaks the assertion.
now_hm=$(date +'%H %M')
out=$(python3 "$helper" $now_hm -1)
iso=$(awk '{print $5}' <<<"$out")
today=$(date +%Y-%m-%d)
fire_date=${iso%%T*}
if [ "$fire_date" != "$today" ]; then
    echo "ok    absolute mode: already-passed HH:MM rolls to a future date"
else
    echo "FAIL  absolute mode: past HH:MM did not roll forward (got $iso)"
    fail=1
fi

# --- validation: malformed args exit non-zero with a usage message ---
for bad_args in "--in" "--in 0" "--in -5" "12 30"; do
    # shellcheck disable=SC2086
    out=$(python3 "$helper" $bad_args 2>&1)
    rc=$?
    check "rejects [$bad_args] (rc)" "2" "$rc"
    case "$out" in usage:*|*$'\n'usage:*) ;; *) echo "FAIL  [$bad_args]: no usage line"; fail=1 ;; esac
done

exit "$fail"
