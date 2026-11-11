#!/usr/bin/env bash
# Exercises skills/close/lib/check-correct.sh (issue #40): the C-5 correction
# ledger sweep behind session:close.
#
# Cases: (a) no ledger -> PASS, exit 0 (b) one open entry -> "단발" NOTE
# (c) same class twice -> "재발" NOTE (d) entries above the last swept: marker
# are not reported (e) no marker -> "첫 실행" NOTE, rules checked at HEAD
# (f) new commits + no Correction Rules section -> "정의 없음" NOTE
# (g) new commits + resolvable .bats token -> command printed by default, run
# with --run-rule-tests via a stub bats (pass, RULE-FAIL, duplicate token run
# once, 2+ matches all run, token-less row counted, unresolvable token WARN)
# (h) dirty tree -> WARN, no test run (i) unparseable line -> WARN, rest parsed
# (j) read-only: ledger content and mtime unchanged, ledger dir never created
# (k) audited repo's untracked count unchanged (l) bad path / non-git -> WARN,
# zero valid targets -> exit 2. Also: bats missing -> WARN, unreachable swept
# sha -> WARN + --since fallback, slug shared across worktrees and injective,
# never a BLOCKED line or exit 1.
# Offline; uses temp git repos and a temp XDG_STATE_HOME.
set -uo pipefail

root=$(cd "$(dirname "$0")/.." && pwd)
cc=$root/skills/close/lib/check-correct.sh
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT
fail=0
export XDG_STATE_HOME=$tmp/state
gitc() { git -c user.name=t -c user.email=t@t "$@"; }

# Stub bats: logs each call to $tmp/bats.log, fails when the path is listed
# in $tmp/bats.fail.
stub=$tmp/stub
mkdir "$stub"
cat >"$stub/bats" <<EOF
#!/usr/bin/env bash
echo "\$*" >>"$tmp/bats.log"
grep -qxF "\$1" "$tmp/bats.fail" 2>/dev/null && exit 1
exit 0
EOF
chmod +x "$stub/bats"
run() { PATH=$stub:$PATH bash "$cc" "$@"; }

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
        *"$2"*) echo "FAIL  $1: '$2' unexpectedly in output"; printf '%s\n' "$3" | sed 's/^/      /'; fail=1 ;;
        *) echo "ok    $1" ;;
    esac
}

mkrepo() { # <dir>
    git init -q -b main "$1"
    gitc -C "$1" commit -q --allow-empty -m init
}
ledger_of() { bash "$cc" --ledger-path "$1"; }
head_of() { git -C "$1" rev-parse HEAD; }
now() { date +%Y-%m-%dT%H:%M:%S%z; }

# --- (a) no ledger ----------------------------------------------------------
a=$tmp/a
mkrepo "$a"
out=$(run "$a")
check "(a) exit 0" "0" "$?"
has "(a) no ledger PASS" "PASS: $a: 원장 없음 — 기록된 실수 0건" "$out"
check "(j) ledger dir not created" "no" "$([ -e "$XDG_STATE_HOME" ] && echo yes || echo no)"

# --- (b)(c)(d)(i) open entries, marker, bad line ----------------------------
b=$tmp/b
mkrepo "$b"
lb=$(ledger_of "$b")
mkdir -p "$(dirname "$lb")"
cat >"$lb" <<EOF
- [2026-11-01T10:00:00+09:00] old-class: handled before the sweep
swept: 2026-11-02T10:00:00+09:00 $(head_of "$b")
- [2026-11-11T14:30:00+09:00] gh-guard-adhoc-matcher: inline glob again
this line is not a ledger entry
- [2026-11-11T15:00:00+09:00] bats-env-leak: per-file unset
- [2026-11-11T16:02:00+09:00] gh-guard-adhoc-matcher: and again
EOF
before=$(cat "$lb"; stat -c %Y "$lb")
untracked_before=$(git -C "$b" status --porcelain --untracked-files=all | grep -c '^??')
out=$(run "$b")
check "(b) exit 0" "0" "$?"
has "(b) single NOTE" "NOTE: $b: 'bats-env-leak' 1회 목격 — 단발, 버릴 후보" "$out"
has "(c) recurrence NOTE" "NOTE: $b: 'gh-guard-adhoc-matcher' 2회 재발 — /correct 실행 후보" "$out"
lacks "(d) swept entry excluded" "old-class" "$out"
has "(i) bad line WARN" "WARN: $b: 원장 4행 파싱 불가 — 제외" "$out"
has "(b) no new commits since sha" "PASS: $b: 새 커밋 0건" "$out"
check "(j) ledger content+mtime unchanged" "$before" "$(cat "$lb"; stat -c %Y "$lb")"
check "(k) untracked count unchanged" "$untracked_before" \
    "$(git -C "$b" status --porcelain --untracked-files=all | grep -c '^??')"
lacks "never BLOCKED" "BLOCKED" "$out"

# --- (e) no marker -> first run at HEAD; (f) no rules section -------------
e=$tmp/e
mkrepo "$e"
le=$(ledger_of "$e")
echo "- [$(now)] some-class: one sighting" >"$le"
out=$(run "$e")
has "(e) first-run NOTE" "NOTE: $e: 스윕 이력 없음 — 첫 실행, 기준선 HEAD 에서 규칙 테스트 확인" "$out"
has "(e) rules still checked at HEAD" "기준선 HEAD — 규칙 테스트 정의 없음" "$out"

f=$tmp/f
mkrepo "$f"
lf=$(ledger_of "$f")
echo "swept: 2026-01-01T00:00:00+09:00 $(head_of "$f")" >"$lf"
gitc -C "$f" commit -q --allow-empty -m two
gitc -C "$f" commit -q --allow-empty -m three
out=$(run "$f")
has "(f) no rules NOTE" "NOTE: $f: 새 커밋 2건 — 규칙 테스트 정의 없음 (AGENTS.md/CLAUDE.md)" "$out"
has "(f) empty open set PASS" "PASS: $f: 원장 open 항목 0건" "$out"

# --- (g) rule tests ---------------------------------------------------------
g=$tmp/g
mkrepo "$g"
mkdir -p "$g/tests/a" "$g/tests/b" "$g/tests/x"
for p in tests/a/gh_host.bats tests/b/gh_host.bats tests/x/old_gh_host.bats tests/x/env.bats tests/x/fails.bats; do
    echo '@test t { true; }' >"$g/$p"
done
cat >"$g/AGENTS.md" <<'EOF'
# Project

## Correction Rules

| Rule | Enforcement |
|---|---|
| host matcher | `gh_host.bats` T18-T25 |
| host fallback | `gh_host.bats` |
| env leak | every suite loads `test_helper.bash` |
| env check | `tests/x/env.bats` |
| ghost | `missing.bats` |

## Other

| Rule | Enforcement |
|---|---|
| not a rule | `tests/x/fails.bats` |
EOF
git -C "$g" add .
gitc -C "$g" commit -q -m rules
lg=$(ledger_of "$g")
echo "swept: 2026-01-01T00:00:00+09:00 $(git -C "$g" rev-parse HEAD~1)" >"$lg"
rm -f "$tmp/bats.log"
out=$(run "$g")
has "(g) default prints command" "NOTE: $g: 새 커밋 1건 — 규칙 테스트 확인: (cd $g && bats tests/a/gh_host.bats tests/b/gh_host.bats tests/x/env.bats)" "$out"
check "(g) default runs nothing" "no" "$([ -e "$tmp/bats.log" ] && echo yes || echo no)"
has "(g) token-less row counted" "NOTE: $g: 규칙 5개 중 1개는 .bats 테스트 토큰이 없어 기계 검증 불가" "$out"
has "(g) unresolved token WARN" "WARN: $g: 'missing.bats' 해석 실패" "$out"
lacks "(g) basename exact (no old_gh_host)" "old_gh_host" "$out"
lacks "(g) section ends at next heading" "fails.bats" "$out"

out=$(run --run-rule-tests "$g")
check "(g) run exit 0" "0" "$?"
check "(g) bats calls: dedup + 2 matches" "tests/a/gh_host.bats
tests/b/gh_host.bats
tests/x/env.bats" "$(cat "$tmp/bats.log")"
has "(g) PASS line" "PASS: $g: 새 커밋 1건, 규칙 테스트 3개 통과 (규칙 5개 중 1개 기계 검증 불가)" "$out"

echo tests/x/env.bats >"$tmp/bats.fail"
out=$(run --run-rule-tests "$g")
check "(g) RULE-FAIL exit 0" "0" "$?"
has "(g) RULE-FAIL NOTE" "NOTE: [RULE-FAIL] $g: 규칙 테스트 실패 (tests/x/env.bats) — 위반 커밋이 이미 착지했을 수 있다. /correct 또는 revert 검토" "$out"
lacks "(g) no PASS on failure" "규칙 테스트 3개 통과" "$out"
lacks "(g) RULE-FAIL never BLOCKED" "BLOCKED" "$out"
rm -f "$tmp/bats.fail"

# bats missing -> WARN (PATH without the stub or a real bats)
nobats=$tmp/nobats
mkdir "$nobats"
for t in git awk sed grep tr cat dirname tail; do ln -s "$(command -v "$t")" "$nobats/$t"; done
out=$(PATH=$nobats "$BASH" "$cc" --run-rule-tests "$g")
has "bats missing WARN" "WARN: $g: bats 미설치 — 테스트 스윕 불가" "$out"

# unreachable sha -> WARN + --since fallback
echo "swept: 2000-01-01T00:00:00+00:00 0123456789abcdef0123456789abcdef01234567" >"$lg"
out=$(run "$g")
has "unreachable sha WARN" "스윕 기준 커밋 0123456789abcdef0123456789abcdef01234567 에 도달할 수 없다" "$out"
has "--since fallback counts" "새 커밋 2건" "$out"

# --- (h) dirty tree -> WARN, no run ------------------------------------------
echo "swept: 2026-01-01T00:00:00+09:00 $(git -C "$g" rev-parse HEAD~1)" >"$lg"
echo dirty >>"$g/AGENTS.md"
rm -f "$tmp/bats.log"
out=$(run --run-rule-tests "$g")
has "(h) dirty WARN" "WARN: $g: dirty tree — 규칙 테스트 스윕 건너뜀 (C-1 부터 해결)" "$out"
check "(h) no test run" "no" "$([ -e "$tmp/bats.log" ] && echo yes || echo no)"
git -C "$g" checkout -q -- AGENTS.md

# --- slug: worktrees share the main ledger; slug is injective ---------------
git -C "$g" worktree add -q "$tmp/g-wt" -b wt >/dev/null 2>&1
check "worktree shares ledger" "$lg" "$(ledger_of "$tmp/g-wt")"
mkdir -p "$tmp/s/a_b/c" "$tmp/s/a/b_c"
mkrepo "$tmp/s/a_b/c"
mkrepo "$tmp/s/a/b_c"
[ "$(ledger_of "$tmp/s/a_b/c")" != "$(ledger_of "$tmp/s/a/b_c")" ]
check "slug injective" "0" "$?"

# --- (l) bad targets ---------------------------------------------------------
mkdir "$tmp/plain"
out=$(GIT_CEILING_DIRECTORIES=$tmp run "$tmp/nope" "$tmp/plain")
check "(l) zero valid targets exit 2" "2" "$?"
has "(l) missing path WARN" "WARN: $tmp/nope: 경로가 없다 — 건너뜀" "$out"
has "(l) non-git WARN" "WARN: $tmp/plain: git 저장소가 아니다 — 건너뜀" "$out"
run >/dev/null
check "(l) no args exit 2" "2" "$?"
out=$(run "$tmp/nope" "$a")
check "(l) mixed targets exit 0" "0" "$?"

exit "$fail"
