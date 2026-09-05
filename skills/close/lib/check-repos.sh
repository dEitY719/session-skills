#!/usr/bin/env bash
# skills/close/lib/check-repos.sh
#
# C-1 (F-3) — 세션 종료 전 git 상태 감사. 인자로 받은 저장소 목록을
# 기계적으로 훑어 "세션이 죽으면 잃는 것"과 "남아서 이어받을 수 있는 것"을
# 가른다. 판단(어떤 저장소가 이번 세션 대상인가)은 SKILL.md 몫이고,
# 이 스크립트는 받은 목록만 결정적으로 검사한다 (F-2).
#
# 검사 항목
#   1. 진행중 merge / rebase / cherry-pick  (.git 상태 파일)
#   2. 미커밋 변경 (추적 파일)
#   3. untracked 파일
#   4. 원격에 미반영된 로컬 커밋 (@{u}..HEAD)
#   5. stash 잔재
#
# NF-1 read-only — 저장소를 읽기만 한다. 상태를 바꾸는 git 하위명령을
# 부르지 않고, 네트워크에도 접근하지 않는다(C-1 은 전부 로컬이다).
#
# NF-4 사내PC 오탐 방지 — `~/.dotfiles-setup-mode` 가 internal 이고
# origin 호스트가 github.com(GHES 가 아닌 common github)이면 미반영 커밋을
# BLOCKED 가 아니라 NOTE 로 강등한다. 그 조합에서 common github 은
# `dEitY719/dotfiles` 의 `docs/.ssot/pc-environment.md` §3 기준 pull only 이므로,
# 로컬에만 있는 커밋은 비상 상황이 아니라 정상 상태다.
#
# Usage:
#   check-repos.sh <repo-path> [repo-path...]
# Exit 0 = BLOCKED 없음, 1 = BLOCKED 있음, 2 = 검사 대상 0개(NF-6).

set -uo pipefail

# 임시 파일 패턴 등 다른 검사는 check-artifacts.sh 가 맡는다.

_cr_lib_dir="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"
. "${_cr_lib_dir}/_repo_common.sh"

BLOCKED_COUNT=0
NOTE_COUNT=0
WARN_COUNT=0
CHECKED_COUNT=0
SETUP_MODE=""

usage() {
    cat <<'EOF'
check-repos.sh — session:close 의 C-1 git 상태 감사 (read-only)

Usage:
  check-repos.sh <repo-path> [repo-path...]

저장소마다 진행중 merge/rebase/cherry-pick, 미커밋 변경, untracked 파일,
원격 미반영 커밋, stash 잔재를 검사해 BLOCKED / NOTE / WARN / PASS 줄을
찍고, 마지막에 VERDICT 줄 하나를 남긴다.

Exit: 0 = BLOCKED 없음, 1 = BLOCKED 있음, 2 = 검사 대상 0개.
EOF
}

blocked() {
    printf 'BLOCKED: %s\n' "$1"
    BLOCKED_COUNT=$((BLOCKED_COUNT + 1))
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

# read_setup_mode — `~/.dotfiles-setup-mode` 의 정규화된 값을 찍는다.
#
# `dEitY719/dotfiles` 의 shell-common/functions/gh_host.sh `_gh_resolve_host`
# 와 같은 규칙(레거시 숫자값 1/2/3 → public/internal/external)을 쓰되, 파일을
# 직접 읽는다 — 감사 도중 부수효과가 있는 파일을 source 하지 않기 위해서다.
read_setup_mode() {
    _rsm_file="$HOME/.dotfiles-setup-mode"
    _rsm_mode=""
    if [ -f "$_rsm_file" ]; then
        _rsm_mode=$(tr -d ' \t\n\r' <"$_rsm_file" 2>/dev/null)
        case "$_rsm_mode" in
            1) _rsm_mode="public" ;;
            2) _rsm_mode="internal" ;;
            3) _rsm_mode="external" ;;
        esac
    fi
    printf '%s' "$_rsm_mode"
}

# origin_host <repo> — origin 리모트 URL 에서 호스트만 뽑아 찍는다.
# https://host/o/r · git@host:o/r · ssh://git@host/o/r 세 형태를 받는다.
origin_host() {
    _oh_url=$(git -C "$1" remote get-url origin 2>/dev/null) || return 1
    [ -n "$_oh_url" ] || return 1
    printf '%s' "$_oh_url" |
        sed -E 's#^[a-zA-Z0-9+.-]+://##; s#^[^/@]*@##; s#[:/].*$##'
}

# count_lines — stdin 의 비어있지 않은 줄 수를 찍는다(빈 입력이면 0).
count_lines() {
    grep -c . 2>/dev/null || true
}

# in_progress_ops <git-dir> — 진행중인 작업 이름을 한 줄에 하나씩 찍는다.
in_progress_ops() {
    _ipo_dir="$1"
    [ -e "${_ipo_dir}/MERGE_HEAD" ] && printf '병합(merge)\n'
    [ -d "${_ipo_dir}/rebase-merge" ] && printf '리베이스(rebase)\n'
    [ -d "${_ipo_dir}/rebase-apply" ] && printf '리베이스(rebase-apply)\n'
    [ -e "${_ipo_dir}/CHERRY_PICK_HEAD" ] && printf 'cherry-pick\n'
    return 0
}

# check_unsynced <repo> <label> — @{u}..HEAD 검사 + NF-4 강등 판정.
check_unsynced() {
    _cu_repo="$1"
    _cu_label="$2"

    if ! git -C "$_cu_repo" rev-parse --verify --quiet HEAD >/dev/null 2>&1; then
        warn "${_cu_label}: 커밋이 하나도 없다 — 원격 반영 검사 건너뜀"
        return 0
    fi
    if ! git -C "$_cu_repo" rev-parse --abbrev-ref --symbolic-full-name '@{u}' \
        >/dev/null 2>&1; then
        warn "${_cu_label}: upstream 없음 — 원격 반영 검사 건너뜀"
        return 0
    fi

    _cu_ahead=$(git -C "$_cu_repo" rev-list --count '@{u}..HEAD' 2>/dev/null || printf '0')
    if [ "${_cu_ahead:-0}" -eq 0 ]; then
        pass "${_cu_label}: 원격에 모두 반영됨"
        return 0
    fi

    _cu_host=$(origin_host "$_cu_repo" 2>/dev/null || printf '')
    if [ "$SETUP_MODE" = "internal" ] && [ "$_cu_host" = "github.com" ]; then
        note "${_cu_label}: 원격 미반영 커밋 ${_cu_ahead}건 — 사내PC(internal) + github.com 원격은 pull only 라 정상 상태다 (NF-4 강등)"
        return 0
    fi
    blocked "${_cu_label}: 원격 미반영 커밋 ${_cu_ahead}건 (@{u}..HEAD)"
}

check_repo() {
    _cr_repo="$1"

    if ! resolve_repo "$_cr_repo"; then
        return 0
    fi
    CHECKED_COUNT=$((CHECKED_COUNT + 1))
    _cr_top="$_RC_TOP"
    _cr_git="$_RC_GITDIR"
    printf 'REPO: %s\n' "$_cr_top"

    # --- 1. 진행중 merge / rebase / cherry-pick -----------------------------
    _cr_ops=""
    [ -n "$_cr_git" ] && _cr_ops=$(in_progress_ops "$_cr_git")
    if [ -n "$_cr_ops" ]; then
        while IFS= read -r _cr_op; do
            [ -n "$_cr_op" ] || continue
            blocked "${_cr_top}: ${_cr_op} 진행중 — 세션이 끊기면 중간 상태가 남는다"
        done <<EOF
$_cr_ops
EOF
    else
        pass "${_cr_top}: 진행중인 merge/rebase/cherry-pick 없음"
    fi

    # --- 2/3. 미커밋 변경 + untracked 파일 -----------------------------------
    # git status 는 한 번만 부른다 — "??" 로 시작하는 줄이 untracked, 나머지
    # 비어있지 않은 줄이 추적 파일의 미커밋 변경이다.
    # --untracked-files=all — 디렉터리를 "?? newdir/" 로 뭉치지 않고 파일
    # 단위로 펼친다. 원래 untracked 검사가 쓰던 `ls-files --others` 와
    # 같은 단위여야 건수가 어긋나지 않는다.
    _cr_status=$(git -C "$_cr_repo" status --porcelain --untracked-files=all 2>/dev/null)
    _cr_dirty=$(printf '%s\n' "$_cr_status" | grep -v '^??' | count_lines)
    _cr_untracked=$(printf '%s\n' "$_cr_status" | grep '^??' | count_lines)

    if [ "${_cr_dirty:-0}" -gt 0 ]; then
        blocked "${_cr_top}: 미커밋 변경 ${_cr_dirty}건"
    else
        pass "${_cr_top}: 미커밋 변경 없음"
    fi

    if [ "${_cr_untracked:-0}" -gt 0 ]; then
        blocked "${_cr_top}: untracked 파일 ${_cr_untracked}건 — 추적되지 않아 다음 세션이 못 찾는다"
    else
        pass "${_cr_top}: untracked 파일 없음"
    fi

    # --- 4. 원격 미반영 커밋 (+ NF-4) ----------------------------------------
    check_unsynced "$_cr_repo" "$_cr_top"

    # --- 5. stash 잔재 -------------------------------------------------------
    _cr_stash=$(git -C "$_cr_repo" stash list 2>/dev/null | count_lines)
    if [ "${_cr_stash:-0}" -gt 0 ]; then
        note "${_cr_top}: stash ${_cr_stash}건 — 디스크에 남으므로 이어받을 수 있다"
    fi
}

main() {
    case "${1:-}" in
        -h | --help | help)
            usage
            return 0
            ;;
    esac

    if [ "$#" -eq 0 ]; then
        printf '검사 대상 없음 — 감사할 저장소가 0개다 (NF-6)\n'
        printf '대상 저장소를 인자로 넘기거나 --repos 로 보태라.\n'
        printf '\nVERDICT: NO-TARGET\n'
        return 2
    fi

    SETUP_MODE=$(read_setup_mode)
    printf 'MODE: %s\n' "${SETUP_MODE:-unknown}"

    for repo in "$@"; do
        check_repo "$repo"
    done

    # 넘겨받은 저장소가 전부 경로 없음/git 아님이면 CHECKED_COUNT 는 0인데
    # BLOCKED_COUNT 도 0 이라 "VERDICT: OK" 로 찍혀 왔다 — 실제로는 아무것도
    # 감사하지 못한 채 성공으로 오인시킨다 (PR dEitY719/dotfiles#1331 리뷰, codex). NF-6 취지대로
    # 이 경우도 "검사 대상 없음" 과 같은 층위로 명시한다.
    if [ "$CHECKED_COUNT" -eq 0 ]; then
        printf '\n전달된 저장소 %d개 중 유효하게 검사된 저장소가 0개다 — 전부 경로 없음/git 아님 (위 WARN 참고)\n' "$#"
        printf '\nVERDICT: NO-TARGET\n'
        return 2
    fi

    printf '\n'
    if [ "$BLOCKED_COUNT" -eq 0 ]; then
        printf 'VERDICT: OK (NOTE %d, WARN %d)\n' "$NOTE_COUNT" "$WARN_COUNT"
        return 0
    fi
    printf 'VERDICT: BLOCKED (%d) (NOTE %d, WARN %d)\n' \
        "$BLOCKED_COUNT" "$NOTE_COUNT" "$WARN_COUNT"
    return 1
}

main "$@"
