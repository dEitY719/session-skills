# resume-after-limit 사용 결과

> **한 줄 요약** — guard 가 남긴 상태 파일을 받아 감싼 명령의 재실행과 다음 사이클 무장을 수행합니다.

```
.rate-limit-guard.json  ──▶  /session:resume-after-limit  ──▶  [RESUME] 블록 + 명령 재실행
```

## 1. 실행한 명령

범용 형식: `/session:resume-after-limit [<command>]`

보통 사용자가 아니라 `session:rate-limit-guard` 가 건 크론이 발화 시점에 호출한다.

## 2. 입력

- `.claude/.rate-limit-guard.json` — `command`, `worktree`, `branch`, `max_cycles`,
  `cycles_remaining`, `cycle_window_min`
- 또는 명시 `<command>` 인자 (크론 경로)

## 3. 결과

**이 문서는 실제 실행 기록이 아니다 — 실행하지 않았다.**

사유: 입력인 상태 파일이 `rate-limit-guard` 의 산출물인데 그쪽을 미실행으로 두었고, 이
스킬은 상태 파일의 `command` 를 **실제로 재실행**한다. 임의 명령 재실행과 다음 사이클 크론
등록이라는 부작용이 있어 사용자와 합의해 미실행으로 남긴다.

`SKILL.md` Step 5 가 정의하는 announce 형식:

```
[RESUME] [rate-limit-guard] 재개: <command>
  • 워크트리: <PWD_NOW>  • 브랜치: <BRANCH>
  • 사이클: <n>/<max_cycles>
```

가장 중요한 안전 동작은 Step 3 이다 — `pwd` 가 상태 파일의 `worktree` 와 다르면
`[FAIL] 워크트리 불일치` 로 **하드 정지**한다. 잘못된 디렉터리는 곧 잘못된 작업이기 때문이다.
