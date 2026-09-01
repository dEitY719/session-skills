# restart 사용 결과

> **한 줄 요약** — 끊긴 세션의 TodoList 를 받아 재개 대상과 잘게 쪼갠 실행 계획을 생성합니다.

```
죽은 턴 + TodoList  ──▶  /session:restart  ──▶  announce 1줄 + 청크 실행 + Next: 1줄
```

## 1. 실행한 명령

범용 형식:

```
/session:restart
```

## 2. 입력

- 현재 세션의 TodoList (`TaskList`) 에서 유일한 `in_progress` 항목
- 교차 확인용 `git status --short` 1회

## 3. 결과

**이 문서는 실제 실행 기록이 아니다 — 실행하지 않았다.**

사유: `restart` 는 "끊긴 작업을 이어서 재개" 하는 스킬이라, 지금 호출하면 진행 중인 이
문서화 작업 자체를 재개 대상으로 잡아 덮어쓴다. 더불어 이 repo 의 `CLAUDE.md` 와
`SKILL.md` 가 "user-triggered recovery, never a building block — 다른 스킬이나 흐름
안에서 호출 금지" 를 명시적 안전 계약으로 두고 있다. 사용자와 합의해 미실행으로 남긴다.

실행했다면 나왔을 출력의 형태는 `skills/restart/references/output-format.md` 의 success /
hard-stop 템플릿에 정의되어 있다 — 재개 대상을 밝히는 announce 줄로 시작해, 단계마다 한
줄씩 보고하고, 다음 구체 명령을 지목하는 `Next:` 줄로 끝난다. 재개 대상을 고를 수 없으면
hard-stop 템플릿을 내고 사용자에게 묻는다.

검증하려면 실제로 턴이 끊긴 세션에서 사용자가 직접 `/session:restart` 를 호출해야 한다.
