# session:close — Help

## Usage

```
/session:close                          # 세션 종료 전 잔여 작업 감사
/session:close --repos /path/a,/path/b  # 자동 수집이 놓친 저장소를 보탠다
/session:close -h                       # show this help
/session:close --help                   # show this help
/session:close help                     # show this help
```

| Option | Description | Default |
|---|---|---|
| `--repos <path,...>` | 자동 수집이 놓친 저장소를 보탠다(치환 아님) | 없음 — 대화에서 자동 수집 |
| `-h`/`--help`/`help` | 이 help 를 출력하고 정지 | — |

## What it does

세션을 닫기 전에 "지금 닫으면 잃어버리는 것" 이 있는지 고정된 4개 항목으로
감사하고, 마지막 두 줄에 판정과 다음 행동만 남긴다. 저장소는 전혀 바뀌지
않는다 — 읽기만 한다.

| 항목 | 내용 |
|---|---|
| C-1 | git 상태: 미커밋 변경 · untracked · 원격 미반영 커밋 · 진행중 merge/rebase/cherry-pick · stash |
| C-2 | TodoList 의 `in_progress` / `pending` 항목 |
| C-3 | 임시 산출물: scratchpad 잔재 · 0 바이트 untracked(버려진 예약 파일) · 미정리 임시 파일 |
| C-4 | 이번 세션이 만든 이슈/PR 상태, 백그라운드 작업(현재는 검사 불가) |

판정 기준은 하나다 — **세션이 죽으면 복구 불가능한가**. 복구 불가능하면
BLOCKED, 디스크나 GitHub 에 남아 이어받을 수 있으면 NOTE 다.

## When to invoke

- 오늘 작업을 끝내고 세션을 닫으려 할 때.
- 워크트리를 여러 개 띄운 세션이라 어디에 뭐가 남았는지 헷갈릴 때.
- 컨텍스트가 아니라 **작업**이 끝났는지 확인하고 싶을 때.

Do NOT invoke for:

- 컨텍스트 한계로 다음 세션에 넘겨야 할 때 — 그건 `session:handoff`
  다(이 스킬은 BLOCKED 면 그쪽으로 안내만 한다).
- 중단된 작업을 이어서 하고 싶을 때 — 그건 `session:restart` 다.
- 세션 기록을 남기고 싶을 때 — `notes:task-history` 나
  `pkm:obsidian-session-clip` 이다.
- 잔여 작업을 정리해 달라는 요청 — 이 스킬은 감사만 한다.

## Behavior summary

1. 이번 세션이 건드린 저장소 목록을 대화에서 모은다(`--repos` 로 보탤 수
   있다). cwd 하나만 보지 않는다.
2. `lib/check-repos.sh` 로 C-1 을, `lib/check-artifacts.sh` 로 C-3 을
   기계적으로 검사한다. 둘 다 로컬 전용이다.
3. `TaskList` 로 C-2 를, 대화에 등장한 이슈/PR 번호로 C-4 를 확인한다.
4. C-1~C-4 리포트를 찍고 마지막 두 줄로 끝낸다:
   `[OK] ...` + `Next: /exit`, 또는 `[BLOCKED] N건 ...` + 해결 명령 한 줄.

## Constraints

- read-only 전용 — 파일을 만들거나 고치거나 지우지 않고, git 상태를 바꾸지
  않으며, 원격에 아무것도 보내지 않는다. 조치 명령은 출력만 한다.
- `/exit` 를 대신 실행하지 않는다. `/exit` 는 CLI 내장 명령이라 스킬에서
  부를 경로가 없고, 프로세스를 강제로 끝내면 transcript 정리를 건너뛴다.
  안내 문자열만 찍는다.
- 검사 대상이 0개면 조용히 통과하지 않고 "검사 대상 없음" 을 명시한다.
- 실행중인 백그라운드 작업·서브에이전트는 지금 검사하지 못한다 — 경고 한
  줄로 남긴다. 자세한 사정은 `references/checks.md` 의 Open Question 참고.
