# 출력 형식

리포트는 두 부분이다. 위쪽은 C-1~C-4 근거이고, 아래쪽 **마지막 두 줄**이
UX 전부다. 사용자는 대개 두 줄만 읽는다 — 그 두 줄만으로 다음 행동이
결정되어야 한다.

## 본문

항목 순서는 항상 C-1 → C-2 → C-3 → C-4 로 고정한다. 항목마다 결과가
없어도 줄을 지우지 말고 "없음" 을 찍는다 (NF-6).

```
## C-1 git 상태 (대상 3개)
[BLOCKED] /home/bwyoon/dotfiles: 미커밋 변경 3건
[BLOCKED] /home/bwyoon/dotfiles: 원격 미반영 커밋 2건 (@{u}..HEAD)
[NOTE]    /home/bwyoon/dotfiles-issue-1327-1: stash 1건
[WARN]    /home/bwyoon/scratch-repo: upstream 없음 — 원격 반영 검사 건너뜀
[OK]      /home/bwyoon/dotfiles-issue-1327-1: 진행중 merge/rebase/cherry-pick 없음

## C-2 TodoList
[BLOCKED] in_progress: check-artifacts.sh 테스트 작성
[NOTE]    pending: changelog 갱신

## C-3 임시 산출물
[NOTE]    버려진 예약 파일 2건 (0 바이트 untracked): notes/draft.md, lib/todo.sh
[NOTE]    scratchpad 잔재 5건: /tmp/claude-1000/.../scratchpad

## C-4 산출물 후속
[NOTE]    issue #1327 open — 아직 닫히지 않음
[WARN]    실행중인 백그라운드 작업·서브에이전트는 검사하지 못했다 — 열거 수단 미확정
```

검사 대상 저장소가 0개일 때는 C-1/C-3 자리에 다음을 찍는다. 아무것도
검사하지 않고 `[OK]` 를 내면 안 된다 (NF-6).

```
## C-1 git 상태 (대상 0개)
[WARN]    검사 대상 없음 — 감사할 저장소가 0개다
```

## 마지막 두 줄 (F-8)

BLOCKED 가 0건일 때:

```
[OK] 남은 작업 없음 — 세션을 닫아도 됩니다
Next: /exit
```

BLOCKED 가 1건 이상일 때 — 건수는 BLOCKED 항목 수이고, NOTE 와 WARN 은
세지 않는다:

```
[BLOCKED] 2건 — 아직 닫으면 안 됩니다
Next: git -C /home/bwyoon/dotfiles status   # 미커밋 3건 확인
```

### `Next:` 한 줄 규칙

- 정확히 한 줄, 하나의 행동만 담는다. 여러 건이 걸렸으면 **가장 위험한 것
  하나**만 가리킨다 — 나머지는 본문에 이미 있다.
- 위험 순서: 진행중 merge/rebase/cherry-pick > 미커밋 변경 > 원격 미반영
  커밋 > `in_progress` todo.
- 명령 뒤에 `#` 주석으로 무엇을 확인하라는 것인지 한 조각 붙인다.
- 조치 명령은 **출력만** 한다. 대신 실행하지 않는다 (NF-1).
- `[OK]` 일 때의 `Next:` 는 언제나 `/exit` 한 줄이다. 대신 실행하지 않는다
  — 안내 문자열일 뿐이다 (NF-2).

### F-9 handoff 연결

BLOCKED 의 원인이 저장소 상태가 아니라 **미완 작업**(`in_progress` todo,
또는 끝내지 못한 구현)이면 `Next:` 는 인계 스킬을 가리킨다.

```
[BLOCKED] 1건 — 아직 닫으면 안 됩니다
Next: /session:handoff   # 미완 작업을 다음 세션으로 넘기고 닫기
```

저장소 상태와 미완 작업이 동시에 걸렸으면 저장소 쪽이 먼저다 — 인계 문서를
써도 미커밋 변경은 그대로 남기 때문이다.
