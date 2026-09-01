#!/usr/bin/env bash
# skills/close/lib/_repo_common.sh
#
# check-repos.sh 와 check-artifacts.sh 가 공유하는 저장소 확인 로직.
# 진입점이 아니다 — source 로만 쓴다. 호출자가 먼저 warn() 을 정의해야
# 한다(둘 다 이미 정의한다).

# resolve_repo <path> — <path> 가 디렉터리이자 git 저장소인지 확인하고
# _RC_TOP(toplevel) · _RC_GITDIR(absolute git dir) 를 채운다. 실패하면
# warn() 을 찍고 1 을 돌려준다 — 호출자는 그 저장소를 건너뛰면 된다.
#
# 흔한 경로(일반 작업 저장소)는 rev-parse 를 한 번만 불러
# --show-toplevel 과 --absolute-git-dir 을 같이 받는다. bare 저장소는
# 작업 트리가 없어 --show-toplevel 이 실패하므로 그때만 폴백으로
# --git-dir/--absolute-git-dir 을 따로 불러 원래 동작(경로 그대로를
# top 으로 씀)을 그대로 유지한다.
resolve_repo() {
    _rc_path="$1"
    _RC_TOP=""
    _RC_GITDIR=""

    if [ ! -d "$_rc_path" ]; then
        warn "${_rc_path}: 경로가 없다 — 건너뜀"
        return 1
    fi

    _rc_out=$(git -C "$_rc_path" rev-parse --show-toplevel --absolute-git-dir 2>/dev/null)
    if [ -n "$_rc_out" ]; then
        _RC_TOP=$(printf '%s\n' "$_rc_out" | sed -n '1p')
        _RC_GITDIR=$(printf '%s\n' "$_rc_out" | sed -n '2p')
        return 0
    fi

    # 위 결합 호출이 실패했다 — 저장소가 아예 아니거나, bare 저장소라
    # --show-toplevel 만 실패했을 수 있다. 후자는 --git-dir 로 구분한다.
    if ! git -C "$_rc_path" rev-parse --git-dir >/dev/null 2>&1; then
        warn "${_rc_path}: git 저장소가 아니다 — 건너뜀"
        return 1
    fi
    _RC_TOP="$_rc_path"
    _RC_GITDIR=$(git -C "$_rc_path" rev-parse --absolute-git-dir 2>/dev/null || printf '')
    return 0
}
