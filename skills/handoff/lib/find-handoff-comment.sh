#!/usr/bin/env bash
# skills/handoff/lib/find-handoff-comment.sh
#
# Step 2 중복 핸드오프 가드. 이슈 <issue-number> 에 이미 달린 코멘트 중
# 현재 사용자가 쓴 마지막 `<!-- session-handoff -->` 코멘트의 숫자 comment
# id 를 한 줄로 출력한다. 그런 코멘트가 없으면 아무것도 출력하지 않는다.
#
# 세션을 구분하지 못한다 — API 에 그런 정보가 없다. 나온 id 가 이번 세션이
# 남긴 것인지는 호출자가 판단한다(`references/issue-resolution.md`).
#
# REST 를 쓰는 이유: `gh issue view --json comments` 는 GraphQL node id 만
# 주는데, 코멘트를 수정하는 REST 엔드포인트는 그 id 를 받지 않는다.
#
# Usage: find-handoff-comment.sh <owner/repo> <issue-number>
# Exit 0 = 정상(발견 여부와 무관), 1 = 인자 오류 또는 API 실패.

set -uo pipefail

repo="${1-}"
issue="${2-}"
if [ -z "$repo" ] || [ -z "$issue" ]; then
    echo "usage: find-handoff-comment.sh <owner/repo> <issue-number>" >&2
    exit 1
fi

ME=$(gh api user --jq '.login') || exit 1
export ME

# per_page=100 은 롱런 이슈에서의 왕복을 줄인다. --paginate 는 페이지마다
# --jq 를 따로 적용하므로 페이지당 최대 한 줄이 나온다. 전체에서 마지막
# 일치를 고르는 것이 tail -n 1 의 몫이다. (이 엔드포인트는 역순 조회를
# 지원하지 않는다 — sort/direction 은 저장소 단위 목록에만 있다.)
ids=$(gh api --paginate "repos/${repo}/issues/${issue}/comments?per_page=100" \
    --jq '[.[] | select(.user.login == $ENV.ME)
               | select(.body | contains("<!-- session-handoff -->"))
               | .id] | last // empty') || exit 1

[ -n "$ids" ] && printf '%s\n' "$ids" | tail -n 1
exit 0
