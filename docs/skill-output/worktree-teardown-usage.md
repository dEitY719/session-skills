# worktree-teardown 사용 결과

> **한 줄 요약** — 워크트리 경로를 받아 워크트리 제거, main 동기화, 브랜치 삭제를 수행합니다.

```
워크트리 경로  ──▶  /session:worktree-teardown  ──▶  제거 + main 동기화 + 브랜치 삭제
```

## 1. 실행한 명령

범용 형식: `/session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]`

이번 예시 (2026-09-01 17:02) — `worktree-spawn-usage.md` 가 만든 워크트리를 대상으로
`--dry-run` 1회 + 실제 teardown 1회를 메인 저장소에서 실행.

## 2. 입력

- 대상 워크트리: `<scratchpad>/wt-demo-claude-1` (브랜치 `wt/claude/1`)
- 실행 위치: `<scratchpad>/wt-demo` (메인 저장소)

## 3. 결과

`--dry-run` — Step 0 게이트에서 정지, 파괴적 동작 없음:

```
[DRY-RUN] Plan:
  Actions:  preflight -> worktree remove -> sync main -> branch delete
No changes made.
```

실제 실행:

```
[OK] Teardown complete
  Removed:  <scratchpad>/wt-demo-claude-1
  Branch:   wt/claude/1 (deleted)
  Now on:   main (up to date with origin/main)
```

사전 점검은 `uncommitted: none` / `unpushed: none` 으로 통과 — 하나라도 있었다면 Step 3 에서
차단되고 정지했을 것이다. Step 6 은 `Deleted branch wt/claude/1 (was 513f9f1)`, 실행 후
`git worktree list` 에는 `wt-demo` 하나만 남았다.
