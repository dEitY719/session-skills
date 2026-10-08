#!/usr/bin/env bash
# Exercises skills/worktree-audit/lib/audit.sh (issue #34): the forensic
# collector behind session:worktree-audit.
#
# Cases: (a) symlinked .venv reported as a symlink whose target exists
# (b) the dir-only `.venv/` gitignore gap on that symlink is named in a HINT
# (c) a real ignored dir is not listed (d) an untracked file is reported
# (e) a tracked modification hints commit (f) zero artifacts -> exit 0
# (g) bad path / non-checkout -> exit 1 (h) the audit deletes nothing
# (i) no temp dir leaks, with >=2 symlinks probed (j) tracked lockfile gets no
# discard hint (k) setup-doc matching: whole-word path, tracked docs only, and
# no suppression of the commit hint (l) unpushed commits counted, base ref
# order origin/main first (m) symlink nested in a collapsed untracked dir.
# Offline; uses temp git repos.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
audit=$root/skills/worktree-audit/lib/audit.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
# Private TMPDIR for audit runs: must be empty afterwards (i).
atmp=$tmp/audit-tmp
mkdir "$atmp"
run_audit() { TMPDIR=$atmp bash "$audit" "$@"; }
gitc() { git -c user.name=t -c user.email=t@t "$@"; }

check() { # <name> <expected> <actual>
    if [ "$2" = "$3" ]; then
        echo "ok    $1"
    else
        echo "FAIL  $1: expected '$2', got '$3'"
        fail=1
    fi
}
has() { # <name> <needle> <haystack>
    case "$3" in
        *"$2"*) echo "ok    $1" ;;
        *) echo "FAIL  $1: '$2' not in output"; printf '%s\n' "$3" | sed 's/^/      /'; fail=1 ;;
    esac
}

mkrepo() { # <dir>
    git init -q -b main "$1"
    git -C "$1" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init
}

# Main repo owns the real venv; the "worktree" links to it, as local-ci.sh does.
main=$tmp/main
mkrepo "$main"
mkdir -p "$main/backend/.venv/bin"
echo py >"$main/backend/.venv/bin/python"

wt=$tmp/wt
mkrepo "$wt"
mkdir -p "$wt/backend"
printf '.venv/\nbuild/\n' >"$wt/.gitignore"
echo v1 >"$wt/tracked.txt"
echo app >"$wt/backend/app.py"
echo 'lock v1' >"$wt/uv.lock"
echo 'ln -s ../main/backend/.venv backend/.venv' >"$wt/local-ci.sh"
git -C "$wt" add .gitignore tracked.txt backend/app.py uv.lock local-ci.sh
git -C "$wt" -c user.name=t -c user.email=t@t commit -q -m base
git -C "$wt" checkout -q -b wt/issue-17/1
git -C "$wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m work
ln -s "$main/backend/.venv" "$wt/backend/.venv"
mkdir -p "$wt/build" && echo o >"$wt/build/out.o"
echo note >"$wt/notes.txt"
echo v2 >"$wt/tracked.txt"
echo 'lock v2' >"$wt/uv.lock"
ln -s "$main/backend/.venv" "$wt/.venv"
mkdir -p "$wt/service" && echo s >"$wt/service/app.py"
ln -s "$main/backend/.venv" "$wt/service/.venv"

out=$(run_audit "$wt")
check "(a) exit 0" "0" "$?"
venv=$(printf '%s\n' "$out" | grep '^ARTIFACT:' | grep -F "	path=backend/.venv	")
has "(a) type symlink" "	type=symlink	" "$venv"
has "(a) target exists" "	target_exists=yes	" "$venv"
has "(a) target path" "	target=$main/backend/.venv	" "$venv"
has "(a) not ignored" "	ignored_by=none	" "$venv"
has "(b) gap hint" "suggest=gitignore-gap	reason=dir-only pattern .gitignore:1:.venv/" "$out"
has "(b) link-only removal hint" "remove the link only: rm backend/.venv" "$out"
check "(c) ignored build/ not listed" "0" "$(printf '%s\n' "$out" | grep -c 'path=build')"
has "(d) untracked file" "	path=notes.txt	status=??	type=file	" "$out"
has "(e) tracked mod hints commit" "path=tracked.txt	suggest=commit" "$out"
has "(a) STATUS count" "	artifacts=7	" "$out"
has "(a) STATUS branch" "	branch=wt/issue-17/1	base=main	" "$out"
has "(a) no upstream" "	unpushed=none-upstream" "$out"
has "(a) documented by tracked local-ci.sh" "	documented_in=local-ci.sh" "$venv"
has "(b) gap hint on root .venv too" "path=.venv	suggest=gitignore-gap" "$out"
check "(i) no temp dir leaked" "" "$(ls -A "$atmp")"
check "(j) tracked uv.lock: no discard" "0" "$(printf '%s\n' "$out" | grep -c 'path=uv.lock	suggest=discard')"
has "(j) tracked uv.lock: commit" "path=uv.lock	suggest=commit" "$out"
has "(m) collapsed dir kept" "	path=service	status=??	type=dir	" "$out"
nested=$(printf '%s\n' "$out" | grep '^ARTIFACT:' | grep -F "	path=service/.venv	")
has "(m) nested symlink" "	type=symlink	" "$nested"
has "(m) nested target exists" "	target_exists=yes	" "$nested"
has "(m) nested gap hint" "path=service/.venv	suggest=gitignore-gap" "$out"

# (h) nothing was deleted or changed
[ -L "$wt/backend/.venv" ] && [ -f "$main/backend/.venv/bin/python" ] && [ -f "$wt/notes.txt" ] &&
    [ -f "$wt/build/out.o" ]
check "(h) link, target, files survive" "0" "$?"

# (f) clean checkout -> zero artifacts, exit 0
clean=$tmp/clean
mkrepo "$clean"
out=$(run_audit "$clean")
check "(f) exit 0" "0" "$?"
check "(f) no ARTIFACT lines" "0" "$(printf '%s\n' "$out" | grep -c '^ARTIFACT:')"
has "(f) STATUS zero" "	artifacts=0" "$out"
# (g) bad parameters -> exit 1
run_audit >/dev/null 2>&1
check "(g) missing arg exit 1" "1" "$?"
bash "$audit" "$tmp/nope" >/dev/null 2>&1
check "(g) nonexistent exit 1" "1" "$?"
mkdir "$tmp/plain"
GIT_CEILING_DIRECTORIES=$tmp bash "$audit" "$tmp/plain" >/dev/null 2>&1
check "(g) non-checkout exit 1" "1" "$?"


# (k) setup-doc matching
doc=$tmp/doc
mkrepo "$doc"
mkdir -p "$doc/scripts"
echo 'Run the build step before testing.' >"$doc/README.md"
echo 'echo old' >"$doc/scripts/old.sh"
git -C "$doc" add README.md scripts/old.sh
gitc -C "$doc" commit -q -m base
git -C "$doc" checkout -q -b feat
gitc -C "$doc" commit -q --allow-empty -m work
sleep 1
mkdir "$doc/build" && echo 'int main(){}' >"$doc/build/main.c"
echo 'bash scripts/new.sh' >"$doc/scripts/new.sh"
out=$(run_audit "$doc")
has "(k) build/ with real work still hints commit" "path=build	suggest=commit" "$out"
has "(k) new.sh self-reference not counted" "	path=scripts/new.sh	" "$out"
check "(k) new.sh documented_in none" "1" \
    "$(printf '%s\n' "$out" | grep -F '	path=scripts/new.sh	' | grep -c '	documented_in=none')"

# (l) unpushed commits with a local bare remote; base ref origin/main first
bare=$tmp/remote.git
git init -q --bare "$bare"
up=$tmp/up
mkrepo "$up"
git -C "$up" remote add origin "$bare"
git -C "$up" push -q -u origin main
git -C "$up" checkout -q -b feat
git -C "$up" push -q -u origin feat
gitc -C "$up" commit -q --allow-empty -m one
gitc -C "$up" commit -q --allow-empty -m two
out=$(run_audit "$up")
has "(l) unpushed count" "	unpushed=2" "$out"
has "(l) push hint" "suggest=push	reason=2 unpushed commit(s) on feat" "$out"
has "(l) base origin/main first" "	base=origin/main	" "$out"
check "(i) no temp dir leaked overall" "" "$(ls -A "$atmp")"

exit "$fail"
