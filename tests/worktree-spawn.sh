#!/usr/bin/env bash
# Exercises skills/worktree-spawn/lib/spawn.sh (issue #38): paths come from the
# main worktree, a matching linked worktree is adopted, --no-enter drops `cd`.
#
# Cases: (a) main checkout: unchanged layout ../<project>-<agent>-<N>, cd line
# (b) linked worktree on wt/<agent>/<k>-<slug>, --task <slug>: adopted, exit 0,
# nothing created, dirty -> stderr warning (c) same for wt/<slug>/<k>
# (d) slug mismatch: sibling of MAIN, named after the main project
# (e) no --task inside a worktree: sibling spawn too (f) --no-enter: no cd line.
# Offline; uses temp git repos.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
spawn=$root/skills/worktree-spawn/lib/spawn.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
unset AI_AGENT_NAME CLAUDECODE

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
lacks() { # <name> <needle> <haystack>
    case "$3" in
        *"$2"*) echo "FAIL  $1: '$2' unexpectedly in output"; fail=1 ;;
        *) echo "ok    $1" ;;
    esac
}
wtcount() { git -C "$main" worktree list | wc -l | tr -d ' '; }

p=$tmp/p
mkdir "$p"
main=$p/proj
git init -q -b main "$main"
git -C "$main" -c user.name=t -c user.email=t@t commit -q --allow-empty -m init

# (a) main checkout
out=$(cd "$main" && bash "$spawn" --ai tst 2>&1)
check "(a) exit 0" "0" "$?"
has "(a) ready" "[OK] Worktree ready" "$out"
has "(a) path" "Path:   $p/proj-tst-1" "$out"
has "(a) branch" "Branch: wt/tst/1" "$out"
has "(a) cd line" "  cd $p/proj-tst-1" "$out"
check "(a) created" "yes" "$([ -d "$p/proj-tst-1" ] && echo yes)"

# (b) adopt wt/<agent>/<k>-<slug>, dirty
git -C "$main" worktree add -q -b wt/other/7-login-feature "$p/adopt-a" main
echo x >"$p/adopt-a/dirty.txt"
before=$(wtcount)
err=$tmp/err
out=$(cd "$p/adopt-a" && bash "$spawn" --ai tst --task "Login Feature" 2>"$err")
check "(b) exit 0" "0" "$?"
has "(b) already isolated" "[OK] Worktree already isolated" "$out"
has "(b) path" "Path:   $p/adopt-a" "$out"
has "(b) branch" "Branch: wt/other/7-login-feature" "$out"
has "(b) base" "Base:   main" "$out"
check "(b) nothing created" "$before" "$(wtcount)"
has "(b) dirty warning on stderr" "uncommitted changes" "$(cat "$err")"
lacks "(b) warning not on stdout" "Warning" "$out"

# (c) adopt wt/<slug>/<k>, clean -> no warning
git -C "$main" worktree add -q -b wt/login-feature/2 "$p/adopt-b" main
before=$(wtcount)
out=$(cd "$p/adopt-b" && bash "$spawn" --ai tst --task login-feature 2>"$err")
check "(c) exit 0" "0" "$?"
has "(c) already isolated" "[OK] Worktree already isolated" "$out"
has "(c) branch" "Branch: wt/login-feature/2" "$out"
check "(c) nothing created" "$before" "$(wtcount)"
check "(c) clean -> no stderr" "" "$(cat "$err")"

# (c2) adopt with an unresolvable --base is a hard error, not an [OK]
out=$(cd "$p/adopt-b" && bash "$spawn" --ai tst --task login-feature --base nope 2>&1)
check "(c2) bad base exit 1" "1" "$?"
lacks "(c2) no [OK]" "[OK]" "$out"

# (c3) an explicit <branch> wins over a matching slug: spawn, not adopt
out=$(cd "$p/adopt-b" && bash "$spawn" --ai tst --task login-feature --dry-run explicit-br 2>&1)
has "(c3) explicit branch planned" "Branch:  explicit-br" "$out"

# (d) slug mismatch -> sibling of main named after the main project
before=$(wtcount)
out=$(cd "$p/adopt-b" && bash "$spawn" --ai tst --task other-task 2>&1)
check "(d) exit 0" "0" "$?"
has "(d) ready" "[OK] Worktree ready" "$out"
has "(d) sibling path" "Path:   $p/proj-tst-2" "$out"
has "(d) branch" "Branch: wt/tst/2-other-task" "$out"
check "(d) created" "$((before + 1))" "$(wtcount)"
check "(d) not named after the linked worktree" "" "$(find "$p" -mindepth 1 -maxdepth 1 -name 'adopt-b-*')"

# (e) no --task inside a worktree -> sibling spawn
out=$(cd "$p/adopt-a" && bash "$spawn" --ai tst 2>&1)
check "(e) exit 0" "0" "$?"
has "(e) sibling path" "Path:   $p/proj-tst-3" "$out"

# (f) --no-enter
out=$(cd "$main" && bash "$spawn" --ai tst --no-enter 2>&1)
check "(f) exit 0" "0" "$?"
has "(f) path" "Path:   $p/proj-tst-4" "$out"
has "(f) enter skipped" "Enter:  skipped (--no-enter" "$out"
lacks "(f) no cd line" "  cd " "$out"

exit $fail
