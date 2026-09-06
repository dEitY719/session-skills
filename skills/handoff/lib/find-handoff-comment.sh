#!/usr/bin/env bash
# skills/handoff/lib/find-handoff-comment.sh
#
# Step 2 중복 핸드오프 가드. 이슈 <issue-number> 에 달린 코멘트 중 **이번
# 세션이** 남긴 마지막 `<!-- session-handoff:<session-id> -->` 코멘트의 숫자
# comment id 를 한 줄로 출력한다. 없으면 아무것도 출력하지 않는다.
#
# 마커가 세션 식별자를 품기 때문에 다른 세션(그리고 다른 사람)의 핸드오프는
# 구조적으로 매칭되지 않는다 — 세션 판단을 호출자에게 미루지 않는다. 세션 id
# 를 모르거나 옛 무-식별자 마커만 있으면 아무것도 출력되지 않고, 호출자는 새
# 코멘트를 POST 한다(fail closed: 과거 기록을 덮어쓰는 일이 없다).
#
# REST 를 쓰는 이유: `gh issue view --json comments` 는 GraphQL node id 만
# 주는데, 코멘트를 수정하는 REST 엔드포인트는 그 id 를 받지 않는다.
#
# Usage: find-handoff-comment.sh <owner/repo> <issue-number> <session-id>
# Exit 0 = 정상(발견 여부와 무관), 1 = 인자 오류 또는 API 실패.

set -uo pipefail

repo="${1-}"
issue="${2-}"
SESSION_ID="${3-}"
case "$issue" in '' | 0 | *[!0-9]*) issue="" ;; esac
case "$SESSION_ID" in *[!a-zA-Z0-9_-]*) SESSION_ID="" ;; esac
if [ -z "$repo" ] || [ -z "$issue" ] || [ -z "$SESSION_ID" ]; then
    echo "usage: find-handoff-comment.sh <owner/repo> <issue-number> <session-id>" >&2
    exit 1
fi
export SESSION_ID

# per_page=100 은 롱런 이슈에서의 왕복을 줄인다. --paginate 는 페이지마다
# --jq 를 따로 적용하므로 페이지당 최대 한 줄이 나온다. 전체에서 마지막
# 일치를 고르는 것이 tail -n 1 의 몫이다. (이 엔드포인트는 역순 조회를
# 지원하지 않는다 — sort/direction 은 저장소 단위 목록에만 있다.)
ids=$(gh api --paginate "repos/${repo}/issues/${issue}/comments?per_page=100" \
    --jq '[.[] | select(.body | contains("<!-- session-handoff:" + $ENV.SESSION_ID + " -->"))
               | .id] | last // empty') || exit 1

[ -n "$ids" ] && printf '%s\n' "$ids" | tail -n 1
exit 0
