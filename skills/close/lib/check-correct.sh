#!/usr/bin/env bash
# skills/close/lib/check-correct.sh
#
# C-5 — 반복 실수 원장 스윕 (issue #40). 저장소마다 두 가지를 본다.
#   1. 디스크 원장(저장소 밖)의 open 항목 — 마지막 `swept:` 마커 아래 줄을
#      class-slug 별로 세어 "재발(/correct 후보)" / "단발(버릴 후보)" 로 알린다.
#   2. 마지막 스윕 이후 새 커밋 — AGENTS.md(없으면 CLAUDE.md) 의
#      Correction Rules 섹션에서 백틱 `*.bats` 토큰을 뽑아 규칙 테스트를
#      확인할 명령을 찍는다. `--run-rule-tests` 일 때만 실제로 실행한다.
#
# 원장 규약(위치·형식·작성자)은 references/correct-ledger.md 가 SSOT 다.
#
# NF-1 read-only — 원장도 원장 디렉터리도 쓰지 않고, git 상태를 바꾸지
# 않는다. 기본 동작은 테스트를 실행하지 않는다: 저장소 테스트 실행은 임의
# 코드 실행이라 read-only 계약 밖이다. `--run-rule-tests` 는 사용자의
# 명시적 opt-in 이고, 그때도 파일당 timeout 60s 와 실행 전후
# `git status --porcelain` 비교로 부수효과를 드러낸다.
#
# C-5 는 BLOCKED 를 만들지 않는다 — 원장도 실패한 테스트도 디스크에 남아
# 세션이 죽어도 복구할 수 있다(references/checks.md 의 단일 기준). 규칙 테스트
# 실패는 `NOTE: [RULE-FAIL] ...` 로 찍는다.
#
# Usage:
#   check-correct.sh [--run-rule-tests] <repo-path> [repo-path...]
#   check-correct.sh --ledger-path <repo-path>   # 원장 경로만 찍는다(작성자용)
# Exit 0 = 검사 완료, 2 = 검사 대상 0개(NF-6). BLOCKED 로 1 을 내는 일은 없다.

set -uo pipefail

_cc_lib_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "${_cc_lib_dir}/_repo_common.sh"

# git status 가 index 를 갱신(쓰기)하지 않게 한다 — read-only 강화.
export GIT_OPTIONAL_LOCKS=0

RULE_TEST_TIMEOUT=60
RUN_TESTS=0
NOTE_COUNT=0
WARN_COUNT=0
CHECKED_COUNT=0

usage() {
    cat <<'EOF'
check-correct.sh — session:close 의 C-5 반복 실수 원장 스윕 (read-only)

Usage:
  check-correct.sh [--run-rule-tests] <repo-path> [repo-path...]
  check-correct.sh --ledger-path <repo-path>

저장소마다 원장의 open 항목과, 마지막 스윕 이후 새 커밋에 대한 Correction
Rules 규칙 테스트를 보고한다. 기본은 테스트 명령만 찍고, --run-rule-tests
일 때만 bats 를 실행한다(파일당 timeout 60s).

Exit: 0 = 검사 완료, 2 = 검사 대상 0개. BLOCKED 는 만들지 않는다.
EOF
}

note() {
    printf 'NOTE: %s\n' "$1"
    NOTE_COUNT=$((NOTE_COUNT + 1))
}

warn() {
    printf 'WARN: %s\n' "$1"
    WARN_COUNT=$((WARN_COUNT + 1))
}

pass() {
    printf 'PASS: %s\n' "$1"
}

# ledger_path <repo> — 원장 파일 경로를 찍는다. slug 는 main worktree 경로에서
# 만든다(git-common-dir 의 부모) — 워크트리마다 원장이 갈라지면 "2회차 재발"
# 이 영영 세어지지 않는다. `%`→`%25`, `_`→`%5F` 를 먼저 이스케이프해 `/`→`_`
# 치환이 단사(injective)가 되게 한다.
ledger_path() {
    _lp_common=$(git -C "$1" rev-parse --git-common-dir 2>/dev/null) || return 1
    _lp_common=$(cd "$1" 2>/dev/null && cd "$_lp_common" 2>/dev/null && pwd -P) || return 1
    case "$_lp_common" in
        */.git) _lp_main=${_lp_common%/.git} ;;
        *) _lp_main=$_lp_common ;;
    esac
    _lp_slug=$(printf '%s' "${_lp_main#/}" | sed 's/%/%25/g; s/_/%5F/g; s#/#_#g')
    printf '%s/session-skills/correct-ledger/%s.md\n' \
        "${XDG_STATE_HOME:-$HOME/.local/state}" "$_lp_slug"
}

# parse_ledger <file> — 원장을 읽어 다음 줄들을 찍는다.
#   BAD <line-no>            파싱 불가 줄
#   MARK <ts> [<sha>]        마지막 swept: 마커
#   OPEN <count> <class>     마지막 마커 아래 항목, 첫 등장 순서
# 빈 줄과 `#` 헤딩 줄은 무시한다.
parse_ledger() {
    awk '
        /^[ \t]*$/ || /^#/ { next }
        /^swept: [^ \t]+([ \t]+[0-9a-fA-F]+)?[ \t]*$/ {
            mark = $2; msha = (NF >= 3 ? $3 : "")
            for (k in cnt) delete cnt[k]
            n = 0
            next
        }
        /^- \[[^]]+\] [A-Za-z0-9._-]+: ./ {
            s = $0
            sub(/^- \[[^]]+\] /, "", s)
            sub(/:.*$/, "", s)
            if (!(s in cnt)) order[++n] = s
            cnt[s]++
            next
        }
        { print "BAD " NR }
        END {
            if (mark != "") print "MARK " mark (msha != "" ? " " msha : "")
            for (i = 1; i <= n; i++) print "OPEN " cnt[order[i]] " " order[i]
        }
    ' "$1"
}

# rule_rows <file> — Correction Rules 섹션(어느 헤딩 레벨이든, 같거나 높은
# 레벨의 다음 헤딩까지) 안 표의 데이터 행만 찍는다. 헤더 행과 구분 행은 뺀다.
# 섹션이 없으면 1 을 돌려준다.
rule_rows() {
    awk '
        /^#+[ \t]/ {
            lvl = match($0, /[^#]/) - 1
            if (insec && lvl <= seclvl) insec = 0
            if (!insec && $0 ~ /Correction Rules/) { insec = 1; seclvl = lvl; found = 1 }
            intable = 0
            next
        }
        insec && /^[ \t]*\|/ {
            if (!intable) { intable = 1; next }          # 헤더 행
            if ($0 ~ /^[ \t]*\|[-:| \t]+$/) next          # 구분 행
            print
            next
        }
        { intable = 0 }
        END { exit(found ? 0 : 1) }
    ' "$1"
}

# commit_scope <repo> <label> <mark-ts> <mark-sha> — 스윕 범위 문구를 SCOPE 에
# 넣는다("새 커밋 N건" / "기준선 HEAD"). 새 커밋이 0건이면 SCOPE=0.
# 서브셸 없이 부른다 — 안에서 찍는 NOTE/WARN 이 카운터에 들어가야 한다.
commit_scope() {
    _cs_repo="$1"
    _cs_label="$2"
    _cs_ts="$3"
    _cs_sha="$4"

    if [ -z "$_cs_ts" ]; then
        note "${_cs_label}: 스윕 이력 없음 — 첫 실행, 기준선 HEAD 에서 규칙 테스트 확인"
        SCOPE='기준선 HEAD'
        return 0
    fi
    _cs_n=""
    if [ -n "$_cs_sha" ]; then
        if git -C "$_cs_repo" merge-base --is-ancestor "$_cs_sha" HEAD >/dev/null 2>&1; then
            _cs_n=$(git -C "$_cs_repo" rev-list --count "${_cs_sha}..HEAD" 2>/dev/null)
        else
            warn "${_cs_label}: 스윕 기준 커밋 ${_cs_sha} 에 도달할 수 없다 (rebase/force-push?) — --since 로 폴백"
        fi
    fi
    if [ -z "$_cs_n" ]; then
        _cs_n=$(git -C "$_cs_repo" rev-list --count --since="$_cs_ts" HEAD 2>/dev/null || printf '0')
    fi
    if [ "${_cs_n:-0}" -eq 0 ]; then
        SCOPE=0
    else
        SCOPE="새 커밋 ${_cs_n}건"
    fi
}

# sweep_rules <repo-top> <scope> — Correction Rules 규칙 테스트 확인/실행.
sweep_rules() {
    _sr_top="$1"
    _sr_scope="$2"

    _sr_file=""
    if [ -f "${_sr_top}/AGENTS.md" ]; then
        _sr_file="${_sr_top}/AGENTS.md"
    elif [ -f "${_sr_top}/CLAUDE.md" ]; then
        _sr_file="${_sr_top}/CLAUDE.md"
    fi
    _sr_rows=""
    [ -n "$_sr_file" ] && _sr_rows=$(rule_rows "$_sr_file")
    if [ -z "$_sr_rows" ]; then
        note "${_sr_top}: ${_sr_scope} — 규칙 테스트 정의 없음 (AGENTS.md/CLAUDE.md)"
        return 0
    fi

    # shellcheck disable=SC2016 # 백틱은 리터럴 패턴이다
    _sr_pat='`[^`]*\.bats`'
    _sr_k=$(printf '%s\n' "$_sr_rows" | grep -c '')
    _sr_l=$(printf '%s\n' "$_sr_rows" | grep -vc -- "$_sr_pat")
    if [ "$_sr_l" -gt 0 ]; then
        note "${_sr_top}: 규칙 ${_sr_k}개 중 ${_sr_l}개는 .bats 테스트 토큰이 없어 기계 검증 불가"
    fi

    # 토큰 해석: 경로가 들어 있으면 경로 일치, 아니면 basename 정확 일치.
    _sr_paths=""
    while IFS= read -r _sr_tok; do
        [ -n "$_sr_tok" ] || continue
        case "$_sr_tok" in
            */*) _sr_m=$(git -C "$_sr_top" ls-files -- ":(literal)${_sr_tok}" 2>/dev/null) ;;
            *) _sr_m=$(git -C "$_sr_top" ls-files -- ":(glob)**/${_sr_tok}" 2>/dev/null) ;;
        esac
        if [ -z "$_sr_m" ]; then
            warn "${_sr_top}: '${_sr_tok}' 해석 실패"
            continue
        fi
        _sr_paths="${_sr_paths}${_sr_m}
"
    done <<EOF
$(printf '%s\n' "$_sr_rows" | grep -o -- "$_sr_pat" | tr -d '`' | awk 'NF && !seen[$0]++')
EOF
    _sr_paths=$(printf '%s' "$_sr_paths" | awk 'NF && !seen[$0]++')
    [ -n "$_sr_paths" ] || return 0

    if [ "$RUN_TESTS" -eq 0 ]; then
        _sr_cmd=$(printf '%s\n' "$_sr_paths" | tr '\n' ' ')
        note "${_sr_top}: ${_sr_scope} — 규칙 테스트 확인: (cd ${_sr_top} && bats ${_sr_cmd% })"
        return 0
    fi

    if ! command -v bats >/dev/null 2>&1; then
        warn "${_sr_top}: bats 미설치 — 테스트 스윕 불가"
        return 0
    fi
    if ! command -v timeout >/dev/null 2>&1; then
        warn "${_sr_top}: timeout 미설치 — 테스트 스윕 불가"
        return 0
    fi

    _sr_before=$(git -C "$_sr_top" status --porcelain --untracked-files=all 2>/dev/null)
    _sr_ok=0
    _sr_bad=0
    while IFS= read -r _sr_p; do
        # </dev/null: 루프 stdin 은 경로 목록 heredoc 이라 테스트가 읽으면 나머지 경로가 사라진다
        (cd "$_sr_top" && timeout "$RULE_TEST_TIMEOUT" bats "$_sr_p") </dev/null >/dev/null 2>&1
        _sr_rc=$?
        if [ "$_sr_rc" -eq 0 ]; then
            _sr_ok=$((_sr_ok + 1))
        elif [ "$_sr_rc" -eq 124 ]; then
            warn "${_sr_top}: '${_sr_p}' 시간 초과 (${RULE_TEST_TIMEOUT}s)"
            _sr_bad=$((_sr_bad + 1))
        else
            note "[RULE-FAIL] ${_sr_top}: 규칙 테스트 실패 (${_sr_p}) — 위반 커밋이 이미 착지했을 수 있다. /correct 또는 revert 검토"
            _sr_bad=$((_sr_bad + 1))
        fi
    done <<EOF
$_sr_paths
EOF
    _sr_after=$(git -C "$_sr_top" status --porcelain --untracked-files=all 2>/dev/null)
    if [ "$_sr_before" != "$_sr_after" ]; then
        warn "${_sr_top}: 규칙 테스트가 작업 트리를 바꿨다 — git -C ${_sr_top} status 확인"
    fi
    if [ "$_sr_bad" -eq 0 ]; then
        pass "${_sr_top}: ${_sr_scope}, 규칙 테스트 ${_sr_ok}개 통과 (규칙 ${_sr_k}개 중 ${_sr_l}개 기계 검증 불가)"
    fi
}

check_repo() {
    _ck_repo="$1"

    if ! resolve_repo "$_ck_repo"; then
        return 0
    fi
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
    _ck_top="$_RC_TOP"
    printf 'REPO: %s\n' "$_ck_top"

    # --- 1. 원장 open 항목 ---------------------------------------------------
    _ck_ledger=$(ledger_path "$_ck_repo")
    _ck_ts=""
    _ck_sha=""
    if [ -z "$_ck_ledger" ] || [ ! -f "$_ck_ledger" ]; then
        pass "${_ck_top}: 원장 없음 — 기록된 실수 0건"
    else
        printf 'LEDGER: %s\n' "$_ck_ledger"
        _ck_open=0
        while read -r _ck_kind _ck_a _ck_b; do
            case "$_ck_kind" in
                BAD) warn "${_ck_top}: 원장 ${_ck_a}행 파싱 불가 — 제외" ;;
                MARK)
                    _ck_ts="$_ck_a"
                    _ck_sha="$_ck_b"
                    ;;
                OPEN)
                    _ck_open=$((_ck_open + 1))
                    if [ "$_ck_a" -ge 2 ]; then
                        note "${_ck_top}: '${_ck_b}' ${_ck_a}회 재발 — /correct 실행 후보"
                    else
                        note "${_ck_top}: '${_ck_b}' 1회 목격 — 단발, 버릴 후보"
                    fi
                    ;;
            esac
        done <<EOF
$(parse_ledger "$_ck_ledger")
EOF
        [ "$_ck_open" -gt 0 ] || pass "${_ck_top}: 원장 open 항목 0건"
    fi

    # --- 2. 커밋 스윕 --------------------------------------------------------
    if ! git -C "$_ck_repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        warn "${_ck_top}: 커밋이 하나도 없다 — 커밋 스윕 건너뜀"
        return 0
    fi
    commit_scope "$_ck_repo" "$_ck_top" "$_ck_ts" "$_ck_sha"
    _ck_scope="$SCOPE"
    if [ "$_ck_scope" = "0" ]; then
        pass "${_ck_top}: 새 커밋 0건"
        return 0
    fi

    if [ -n "$(git -C "$_ck_repo" status --porcelain --untracked-files=all 2>/dev/null)" ]; then
        warn "${_ck_top}: dirty tree — 규칙 테스트 스윕 건너뜀 (C-1 부터 해결)"
        return 0
    fi
    sweep_rules "$_ck_top" "$_ck_scope"
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
        --ledger-path)
            [ -n "${2:-}" ] || { usage >&2; return 2; }
            ledger_path "$2" || { printf 'git 저장소가 아니다: %s\n' "$2" >&2; return 2; }
            return 0
            ;;
        --run-rule-tests)
            RUN_TESTS=1
            shift
            ;;
    esac

    if [ "$#" -eq 0 ]; then
        printf '검사 대상 없음 — 감사할 저장소가 0개다 (NF-6)\n'
        printf '\nVERDICT: NO-TARGET\n'
        return 2
    fi

    for repo in "$@"; do
        check_repo "$repo"
    done

    if [ "$CHECKED_COUNT" -eq 0 ]; then
        printf '\n전달된 저장소 %d개 중 유효하게 검사된 저장소가 0개다 — 전부 경로 없음/git 아님 (위 WARN 참고)\n' "$#"
        printf '\nVERDICT: NO-TARGET\n'
        return 2
    fi

    printf '\nVERDICT: OK (NOTE %d, WARN %d)\n' "$NOTE_COUNT" "$WARN_COUNT"
    return 0
}

main "$@"
