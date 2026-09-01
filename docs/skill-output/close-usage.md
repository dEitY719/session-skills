# close 사용 결과

> **한 줄 요약** — 세션이 건드린 저장소 목록을 받아 `[OK]`/`[BLOCKED]` 판정을 생성합니다.

```
저장소 경로  ──▶  /session:close  ──▶  4개 항목 감사 리포트 + 판정 1줄
```

## 1. 실행한 명령

범용 형식: `/session:close [--repos <path,...>]`

이번 예시 (2026-09-01 17:01) — 스킬 Step 3 / Step 5 를 `lib/` 스크립트로 직접 실행:

```bash
bash skills/close/lib/check-repos.sh <repo>
bash skills/close/lib/check-artifacts.sh --scratchpad <session scratchpad> <repo>
```

## 2. 입력

- 저장소: `/home/bwyoon/para/project/skills/session-skills-feat-1` (브랜치 `wt/feat/1`)
- scratchpad: 이 세션이 시스템 프롬프트로 받은 경로를 그대로 전달

## 3. 결과

C-1 (`check-repos.sh`):

```
MODE: external
PASS: 진행중인 merge/rebase/cherry-pick 없음
PASS: 미커밋 변경 없음
PASS: untracked 파일 없음
PASS: 원격에 모두 반영됨
VERDICT: OK (NOTE 0, WARN 0)
```

C-3 (`check-artifacts.sh`): `PASS` 3줄, `VERDICT: OK`.
C-2 는 이 하네스에 `TaskList` 가 없어 degrade — 문서화된 대로 조용히 건너뛰지 않고 명시.
C-4 는 이번 세션이 만든 이슈/PR 번호가 없어 호출하지 않음. 저장소는 실행 전후로 **전혀
변경되지 않았다** (read-only 계약).
