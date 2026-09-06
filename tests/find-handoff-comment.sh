#!/usr/bin/env bash
# Exercises skills/handoff/lib/find-handoff-comment.sh — the Step 2
# duplicate-handoff guard.
#
# Offline: no network, no gh auth. `gh` is stubbed on PATH with a script that
# emulates the one call shape the helper makes — `gh api --paginate <path>
# --jq <filter>`, applying the filter once per page, which is what makes the
# helper's `tail -n 1` necessary. The real jq filter therefore runs here.
#
# What is covered: session-scoped matching (a prior session's handoff and the
# legacy id-less marker must never be returned), the across-pages last-match,
# and argument validation short-circuiting before any API call.
set -uo pipefail

root=$(git rev-parse --show-toplevel)
helper=$root/skills/handoff/lib/find-handoff-comment.sh
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
fail=0

mkdir -p "$work/bin"
cat > "$work/bin/gh" <<'STUB'
#!/usr/bin/env bash
echo "called" >> "$GH_CALLS"
filter=""
while [ $# -gt 0 ]; do
    case "$1" in
        --jq) filter=$2; shift 2 ;;
        *) shift ;;
    esac
done
for page in "$GH_PAGES"/page*.json; do
    jq -r "$filter" "$page" || exit 1
done
STUB
chmod +x "$work/bin/gh"
PATH=$work/bin:$PATH
export PATH
GH_CALLS=$work/calls
export GH_CALLS
GH_PAGES=$work/pages
export GH_PAGES
mkdir -p "$GH_PAGES"

comment() { printf '{"id": %s, "body": "%s"}' "$1" "$2"; }

# Page 1: an earlier session's handoff plus the legacy id-less marker.
# Page 2: this session's handoff, then a later unrelated comment.
{
    printf '[\n'
    comment 101 '<!-- session-handoff:sess-OLD --> older session'
    printf ',\n'
    comment 102 '<!-- session-handoff --> legacy marker, no id'
    printf '\n]\n'
} > "$GH_PAGES/page1.json"
{
    printf '[\n'
    comment 201 '<!-- session-handoff:sess-MINE --> this session'
    printf ',\n'
    comment 202 'plain chatter'
    printf '\n]\n'
} > "$GH_PAGES/page2.json"

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected '$2', got '$3'"
        fail=1
    fi
}

: > "$GH_CALLS"
got=$(bash "$helper" o/r 7 sess-MINE)
check "returns this session's comment id" "201" "$got"

: > "$GH_CALLS"
got=$(bash "$helper" o/r 7 sess-OTHER)
check "another session's handoff never matches" "" "$got"

# A second handoff from this session on a later page: the last one wins, and
# only tail -n 1 gets that right once --jq has run per page.
{
    printf '[\n'
    comment 301 '<!-- session-handoff:sess-MINE --> this session, later'
    printf '\n]\n'
} > "$GH_PAGES/page3.json"
: > "$GH_CALLS"
got=$(bash "$helper" o/r 7 sess-MINE)
check "last match across pages wins" "301" "$got"

for bad in "o/r 0 sess-MINE" "o/r abc sess-MINE" "o/r 7 " " 7 sess-MINE" "o/r 7 bad;id"; do
    : > "$GH_CALLS"
    # shellcheck disable=SC2086
    out=$(bash "$helper" $bad 2>&1)
    rc=$?
    check "rejects args [$bad] (rc)" "1" "$rc"
    check "rejects args [$bad] (no API call)" "" "$(cat "$GH_CALLS")"
    case "$out" in usage:*) ;; *) echo "FAIL  args [$bad]: no usage line"; fail=1 ;; esac
done

exit "$fail"
