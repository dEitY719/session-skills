# 검사 항목 C-1 ~ C-4 와 판정 규칙

## 판정의 단일 기준

> 세션이 지금 죽으면 이것을 복구할 수 있는가?

- 복구 불가능 → **BLOCKED**. 세션을 닫으면 안 된다.
- 디스크나 GitHub 에 남아 다음 세션이 이어받을 수 있음 → **NOTE**. 알려만
  주고 판정을 뒤집지 않는다.
- 검사 자체를 수행하지 못한 경우 → **WARN**. 판정에 넣지 않되 감춘다는
  뜻은 아니다. 반드시 한 줄로 드러낸다.

| 판정 | 대상 |
|---|---|
| BLOCKED | 진행중 merge/rebase/cherry-pick · 실행중 백그라운드 작업 · 미커밋 변경 · 원격 미반영 커밋 · `in_progress` todo |
| NOTE | 미착수 이슈 · 열린 PR · scratchpad 잔재 · stash · 버려진 예약 파일 · 미정리 임시 파일 · `pending` todo |

## C-1 git 상태 — `lib/check-repos.sh`

대상 저장소 **전부**에 대해 다섯 가지를 본다. 전부 로컬 검사라 네트워크가
끊겨도 결과가 같다.

| 검사 | 방법 | 판정 |
|---|---|---|
| 진행중 merge | `.git/MERGE_HEAD` 존재 | BLOCKED |
| 진행중 rebase | `.git/rebase-merge/` 또는 `.git/rebase-apply/` 존재 | BLOCKED |
| 진행중 cherry-pick | `.git/CHERRY_PICK_HEAD` 존재 | BLOCKED |
| 미커밋 변경 | `git status --porcelain --untracked-files=no` | BLOCKED |
| untracked 파일 | `git ls-files --others --exclude-standard` | BLOCKED |
| 원격 미반영 커밋 | `git rev-list --count @{u}..HEAD` | BLOCKED (NF-4 예외) |
| stash 잔재 | `git stash list` | NOTE |

untracked 를 BLOCKED 로 두는 이유: 추적되지 않는 파일은 `git log` 에도
`git diff` 에도 안 잡혀 다음 세션이 존재 자체를 모른다. 미커밋 변경보다
찾기 어렵다. 다만 0 바이트 파일과 편집 부산물은 C-3 이 별도 분류로 다시
설명하므로, 두 리포트를 함께 읽으면 무엇을 지우고 무엇을 남길지 갈린다.

upstream 이 설정되지 않은 브랜치는 `@{u}` 가 없으므로 "upstream 없음" WARN
한 줄로 끝낸다 — BLOCKED 가 아니다. 아직 원격에 올린 적이 없는 브랜치는
정상 상태이고, 여기서 BLOCKED 를 내면 새 워크트리마다 오탐이 난다.

### NF-4 사내PC 강등 규칙

`~/.dotfiles-setup-mode` 가 `internal` 이고 origin 호스트가 `github.com`
(GHES 가 아닌 common github)이면 **원격 미반영 커밋을 BLOCKED 가 아니라
NOTE 로 강등한다**.

근거는 `docs/.ssot/pc-environment.md` §3 이다. `internal` 모드에서 common
github 은 **pull only — 원격 반영 절대 금지**다. 그 조합에서 로컬에만 있는
커밋은 사고가 아니라 설계상 정상 상태이므로, BLOCKED 로 두면 사내PC 세션이
영원히 닫히지 않는다. GHES origin 은 read/write 이므로 강등 대상이 아니다.

모드 판정은 `shell-common/functions/gh_host.sh` 의 `_gh_resolve_host` 와 같은
규칙(레거시 숫자값 `1`/`2`/`3` → `public`/`internal`/`external`)을 쓰되,
`$HOME/.dotfiles-setup-mode` 를 직접 읽는다. 감사 도중 부수효과가 있는
파일을 source 하지 않기 위해서다.

## C-2 TodoList

`TaskList` 로 현재 todo 를 읽는다. `in_progress` 는 BLOCKED — 손대다 만
작업이고, 세션이 죽으면 어디까지 했는지가 대화와 함께 사라진다. `pending`
은 NOTE — 아직 시작하지 않았으니 다음 세션이 그대로 집어 들면 된다.

todo 가 하나도 없으면 "TodoList 없음" 을 명시한다. 아무 줄도 찍지 않고
넘어가면 검사했다는 사실 자체가 리포트에서 사라진다 (NF-6).

## C-3 임시 산출물 — `lib/check-artifacts.sh`

| 갈래 | 방법 | 판정 |
|---|---|---|
| scratchpad 잔재 | `--scratchpad <dir>` 아래 파일 수 | NOTE |
| 버려진 예약 파일 | 0 바이트 untracked 파일 | NOTE |
| 미정리 임시 파일 | untracked `*.tmp` `*.bak` `*.orig` `*.rej` `*.swp` `*~` | NOTE |

**버려진 예약 파일**은 단순 나열이 아니라 별도 분류로 제시한다. 0 바이트
untracked 파일은 이름만 잡아두고 내용을 채우기 전에 턴이 끊긴 흔적이라는
신호이므로, "채울 것인가 정리할 것인가" 라는 결정을 사람에게 넘겨야 한다.
크기가 있는 임시 파일과 같은 줄에 섞으면 그 신호가 묻힌다.

세 갈래 모두 디스크에 남으므로 BLOCKED 를 만들지 않는다. 스크립트는 찾기만
하고 아무것도 정리하지 않는다 (NF-1).

## C-4 산출물 후속

이번 세션이 만든 이슈/PR 번호가 대화에 있을 때만
`gh issue view <N> --json state,title` / `gh pr view <N> --json state,title`
로 상태를 확인한다. 미착수 이슈와 열린 PR 은 NOTE 다 — GitHub 에 남아
있으므로 세션이 죽어도 사라지지 않는다.

이 스킬에서 네트워크를 쓰는 곳은 여기뿐이다. `gh` 가 없거나 인증이
만료됐거나 사내망이 끊겨 실패하면 `[WARN]` 한 줄로 낮추고 판정은 그대로
둔다 (NF-3). C-4 실패가 `[OK]` 를 `[BLOCKED]` 로 뒤집는 일은 없다.

### Open Question — 백그라운드 작업 열거

F-6 은 "실행중인 백그라운드 작업·서브에이전트" 도 C-4 에 넣으라고 하고,
F-7 은 그것을 BLOCKED 로 분류한다. 그러나 **스킬 안에서 그것들을 열거하는
확인된 표준 수단이 없다.** 이슈 본문의 Open Questions 도 같은 사실을 인정
한다.

따라서 이 하위 검사는 지금 **건너뛰고 경고 한 줄만 남긴다**:

```
[WARN] C-4: 실행중인 백그라운드 작업·서브에이전트는 검사하지 못했다 — 열거 수단 미확정
```

추측으로 도구 이름을 지어내 부르지 않는다. 존재하지 않는 도구를 부르면
매 실행이 실패하고, 더 나쁘게는 "검사했는데 없었다" 는 잘못된 확신을 준다.
열거 수단이 확정되면 이 절과 `SKILL.md` Step 6 을 함께 고치면 된다.
