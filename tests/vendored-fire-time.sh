#!/usr/bin/env bash
# Drift guard for the vendored copies of compute-fire-time.py (issue #30).
#
# resume-after-limit and schedule each carry their own byte-identical copy in
# references/ so a single-skill install (no sibling rate-limit-guard/) can still
# run it. The SSOT stays skills/rate-limit-guard/references/compute-fire-time.py:
# edit it there, then `cp` it over both copies in the same commit.
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
done

exit "$fail"
