#!/usr/bin/env bash
# Exercises skills/worktree-audit/lib/audit.sh (issue #34): the forensic
# collector behind session:worktree-audit.
#
# Cases: (a) symlinked .venv reported as a symlink whose target exists
# (b) the dir-only `.venv/` gitignore gap on that symlink is named in a HINT
# (c) a real ignored dir is not listed (d) an untracked file is reported
# (e) a tracked modification hints commit (f) zero artifacts -> exit 0
# (g) bad path / non-checkout -> exit 1 (h) the audit deletes nothing.
# Offline; uses temp git repos.
set -uo pipefail

root=$(git rev-parse --show-toplevel)
audit=$root/skills/worktree-audit/lib/audit.sh
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
git -C "$wt" add .gitignore tracked.txt backend/app.py
git -C "$wt" -c user.name=t -c user.email=t@t commit -q -m base
git -C "$wt" checkout -q -b wt/issue-17/1
git -C "$wt" -c user.name=t -c user.email=t@t commit -q --allow-empty -m work
ln -s "$main/backend/.venv" "$wt/backend/.venv"
mkdir -p "$wt/build" && echo o >"$wt/build/out.o"
echo note >"$wt/notes.txt"
echo v2 >"$wt/tracked.txt"

out=$(bash "$audit" "$wt")
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
has "(a) STATUS count" "	artifacts=3" "$out"
has "(a) STATUS branch" "	branch=wt/issue-17/1	base=main	" "$out"

# (h) nothing was deleted or changed
[ -L "$wt/backend/.venv" ] && [ -f "$main/backend/.venv/bin/python" ] && [ -f "$wt/notes.txt" ] &&
    [ -f "$wt/build/out.o" ]
check "(h) link, target, files survive" "0" "$?"

# (f) clean checkout -> zero artifacts, exit 0
clean=$tmp/clean
mkrepo "$clean"
out=$(bash "$audit" "$clean")
check "(f) exit 0" "0" "$?"
check "(f) no ARTIFACT lines" "0" "$(printf '%s\n' "$out" | grep -c '^ARTIFACT:')"
has "(f) STATUS zero" "	artifacts=0" "$out"

# (g) bad parameters -> exit 1
bash "$audit" >/dev/null 2>&1
check "(g) missing arg exit 1" "1" "$?"
bash "$audit" "$tmp/nope" >/dev/null 2>&1
check "(g) nonexistent exit 1" "1" "$?"
mkdir "$tmp/plain"
GIT_CEILING_DIRECTORIES=$tmp bash "$audit" "$tmp/plain" >/dev/null 2>&1
check "(g) non-checkout exit 1" "1" "$?"

exit "$fail"
