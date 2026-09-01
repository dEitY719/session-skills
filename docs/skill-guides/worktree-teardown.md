# session:worktree-teardown — 워크트리 제거

> **한 줄 요약** — `session:worktree-spawn` 의 역방향. 워크트리를 제거하고 main 을 동기화한 뒤 브랜치를 삭제한 결과를 산출한다. 이 저장소에서 **유일하게 파괴적인** 스킬이다.

## 언제 쓰나

- 병렬 작업이 끝났을 때 ("작업 끝", "워크트리 정리", "워크트리 제거")

## 언제 안 쓰나

| 상황 | 대신 쓸 것 |
|---|---|
| 워크트리를 만든다 | `session:worktree-spawn` |
| 지우기 전에 남은 작업을 확인만 하고 싶다 | `session:close` (read-only 감사) |
| 미완 작업을 넘겨야 한다 | `session:handoff` — 지우기 **전에** |

## 호출 형식

```
/session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]
/session:worktree-teardown -h
```

| 인자 | 설명 | 기본값 |
|---|---|---|
| `<worktree-path>` | **필수.** 제거할 워크트리 경로 | 없음 |
| `--dry-run` | 계획만 출력하고 정지 (파괴적 동작 없음) | off |
| `--force` | 미커밋/미푸시 차단을 무시 | off |
| `--keep-branch` | 브랜치는 남긴다 | off |

## 동작 단계

0. **dry-run 게이트** — `--dry-run` 이면 해석된 경로·브랜치·예정 동작만 찍고 정지.
1. **검증** — `git-dir == git-common-dir` 확인. **워크트리 안이면 에러 후 정지.**
   경로 인자가 없으면 현재 워크트리 목록을 보여주고 정지.
2. **워크트리 정보 해석** — 절대경로, `git worktree list --porcelain` 에서 브랜치,
   basename. 알려진 워크트리가 아니면 정지.
3. **사전 점검** — `git -C <path>` 로 미커밋 변경과 미푸시 커밋 확인. 있으면 **차단**한다.
   `--force` 를 주면 건너뛴다.
4. **워크트리 제거** — `git worktree remove` 후 `git worktree prune`.
5. **main 동기화** — `git checkout main && git pull origin main`.
   **브랜치 삭제 전에** 돌아야 `git branch -d` 가 머지 여부를 확인할 수 있다.
6. **브랜치 삭제** — `git branch -d` (안전 삭제). `--keep-branch` 면 건너뛴다.
   완전 머지가 아니면 경고한다.
7. **로그** — spawn 과 같은 파일에 `TEARDOWN` 항목 append.
8. **리포트** — `[OK]` 블록 + 바깥 셸 cwd 안내(`Note:`), 실패 시 `[FAIL]` 구조화 판정.

## 주의사항 / 제약

- **반드시 메인 저장소에서 실행한다.** 제거 대상 워크트리 안에서는 절대 실행하지 않는다.
- **사전 점검은 작업 유실 방지 장치다.** 미커밋 변경이나 미푸시 커밋이 있으면 보고하고
  멈춘다.
- **`--force` 는 사용자의 명시적 override 이지, 에이전트가 차단을 우회하는 지름길이
  아니다.**
- main 동기화를 브랜치 삭제보다 **먼저** 한다.
- `[OK]` 에는 `Note:` 블록을 무조건 포함한다 — 바깥 셸의 cwd 는 탐지할 수 없어서,
  제거된 워크트리 안에 있었다면 `getcwd: cannot access parent directories` 가 난다.
