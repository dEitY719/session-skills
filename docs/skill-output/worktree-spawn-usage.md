# worktree-spawn 사용 결과

> **한 줄 요약** — 메인 저장소를 받아 격리된 워크트리와 전용 브랜치를 생성합니다.

```
메인 저장소  ──▶  /session:worktree-spawn  ──▶  ../<project>-<agent>-<N> + wt/<agent>/<N>
```

## 1. 실행한 명령

범용 형식: `/session:worktree-spawn [--ai <name>] [--task <slug>] [--base <ref>] [<branch>]`

이번 예시 (2026-09-01 17:02, 인자 없이 기본 경로). 이 repo 자체는 이미 워크트리 안이라
스킬이 차단하므로, scratchpad 의 독립 테스트 저장소에서 Step 1~8 을 그대로 실행했다.

## 2. 입력

- 메인 저장소: `<scratchpad>/wt-demo` (브랜치 `main`, 커밋 `513f9f1`, bare origin 연결)
- 환경: `CLAUDECODE=1`, `AI_AGENT_NAME` 미설정

## 3. 결과

```
[OK] Worktree ready
  Path:   <scratchpad>/wt-demo-claude-1
  Branch: wt/claude/1
  Base:   origin/main
```

단계별 실제 해석값:

| 단계 | 결과 |
|---|---|
| Step 1 | `git-dir == git-common-dir` -> 워크트리 아님, 통과 |
| Step 2 | `AGENT=claude` (우선순위 3, `$CLAUDECODE=1`) |
| Step 3 | `NEXT_INDEX=1` (기존 `wt-demo-claude-*` 없음) |
| Step 5 | `BASE_REF=origin/main` (우선순위 2) |

Step 7 로그: `[2026-09-01T17:02:31+0900] SPAWN project=wt-demo agent=claude index=1
branch=wt/claude/1 base=origin/main`
