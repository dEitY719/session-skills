#!/usr/bin/env bash
# Drift guard for the vendored copies of compute-fire-time.py (issue #30).
#
# resume-after-limit and schedule each carry their own byte-identical copy in
# references/ so a single-skill install (no sibling rate-limit-guard/) can still
# run it. The SSOT stays skills/rate-limit-guard/references/compute-fire-time.py:
# edit it there, then `cp` it over both copies in the same commit. The full
# behavior suite (tests/compute-fire-time.sh) runs against the SSOT only; this
# script adds a smoke run of each copy at the path its skill executes.
set -uo pipefail

root=$(git rev-parse --show-toplevel)
ssot=$root/skills/rate-limit-guard/references/compute-fire-time.py
fail=0

for skill in resume-after-limit schedule; do
    copy=$root/skills/$skill/references/compute-fire-time.py
    if cmp -s "$ssot" "$copy"; then
        echo "ok    $skill copy matches rate-limit-guard SSOT"
    else
        echo "FAIL  $skill: $copy missing or differs from $ssot — cp the SSOT over it"
        fail=1
    fi
    # Smoke-run the copy the way its skill does (relative mode), so the path
    # the skill actually executes is exercised, not only compared.
    if [ "$(python3 "$copy" --in 10 2>/dev/null | wc -w)" = 5 ]; then
        echo "ok    $skill copy runs: --in 10 prints 5 fields"
    else
        echo "FAIL  $skill: python3 $copy --in 10 did not print 5 fields"
        fail=1
    fi
done

exit "$fail"
