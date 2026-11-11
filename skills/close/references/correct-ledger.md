# 반복 실수 원장 규약 (C-5)

`/correct` 운용 규칙: 첫 실수 목격은 기록만, **같은 실수 2회차에 즉시
`/correct` 제안**, 세션 종료 시 미처리 기록 스윕. 이 파일은 그 기록을 담는
디스크 원장의 규약이다. close 는 원장을 **읽기만** 한다
(`lib/check-correct.sh`). 쓰는 쪽은 실수를 목격한 에이전트다.

## 위치 — 저장소 밖

```
${XDG_STATE_HOME:-$HOME/.local/state}/session-skills/correct-ledger/<slug>.md
```

경로는 손으로 만들지 말고 스크립트에 묻는다 (부수효과 없음):

```
bash "${SKILL_DIR}/lib/check-correct.sh" --ledger-path <repo>
```

- `<slug>` 는 **main worktree** 의 절대경로에서 만든다
  (`git rev-parse --git-common-dir` 의 부모). 같은 저장소의 워크트리는 모두
  같은 원장을 쓴다 — 워크트리마다 갈라지면 "2회차 재발" 이 세어지지 않고,
  `worktree-teardown` 뒤에 open 항목이 다시 보고될 경로도 사라진다.
- 선행 `/` 를 떼고 `%`→`%25`, `_`→`%5F` 를 먼저 이스케이프한 뒤 `/`→`_` 로
  바꾼다. 예: `/home/bwyoon/dotfiles` → `home_bwyoon_dotfiles.md`. 이스케이프
  덕분에 `/a_b/c` 와 `/a/b_c` 가 같은 slug 가 되지 않는다.
- **저장소 밖인 이유**: (a) C-1 은 untracked 파일을 BLOCKED 로 삼으므로 repo
  안 원장은 감사를 자기 무효화한다. (b) 감사 대상 저장소를 수정하지 않는
  NF-1 과 정합이다. (c) 실수 목격은 머신 로컬 사건이다.
- 원장 디렉터리가 없으면 감사 스크립트는 만들지 않는다. 첫 append 때 작성자가
  `mkdir -p` 한다.

## 형식 — append-only

```markdown
- [2026-11-11T14:30:00+09:00] gh-guard-adhoc-matcher: 새 guard 가 *github.com* 글롭을 인라인으로 다시 만듦
- [2026-11-11T16:02:00+09:00] bats-env-leak: bats 스위트가 machine-local env 를 per-file unset 함
swept: 2026-11-11T18:00:00+09:00 3f2c1a9e0b7d4c5a6f8e9d0c1b2a3f4e5d6c7b8a
```

- 항목 줄: `- [<ISO8601>] <class-slug>: <한 줄 설명>`. `<class-slug>` 는
  `[A-Za-z0-9._-]+` 인 재발 비교용 안정 식별자다. 같은 부류를 다시 목격하면
  같은 slug 로 새 줄을 append 한다 — 기존 줄은 고치지 않는다.
- 마커 줄: `swept: <ISO8601> <HEAD-sha>`. **마지막 마커 위는 처리 완료, 아래는
  open** 이다. sha 는 커밋 스윕의 기준선이다 — `git rev-list --count
  <sha>..HEAD` 로 센다. 커밋 날짜(`--since`)는 다른 PC 에서 만들어 나중에
  pull 한 커밋을 놓치므로 기준이 아니다. sha 에 도달할 수 없으면(rebase,
  force-push) WARN 한 줄과 함께 `--since <ts>` 로 폴백한다. sha 없는
  `swept: <ts>` 도 읽지만 `--since` 로만 센다.
- 빈 줄과 `#` 헤딩 줄은 무시한다. 마지막 마커 아래의 그 밖의 줄은 파싱 불가
  WARN 으로 보고되고 나머지 줄은 정상 처리된다(마커 위 줄은 처리 완료라 무시).
- **시크릿 금지** — 설명에 토큰·비밀값 자체를 적지 않는다.

## 작성자 규약 (모든 세션의 에이전트)

1. 실수를 목격하면 그 자리에서 원장에 append 한다.
2. 같은 class-slug 2회차 → 즉시 `/correct` 실행을 제안한다.
3. close 가 open 항목을 보고하면 사용자 결정(버림/실행/보류)에 따라 처리하고,
   전부 해소됐을 때 **호출 에이전트가** `swept: <now> <HEAD-sha>` 를 append
   한다. 처리를 미루면 마커를 찍지 않는다 — 다음 close 가 계속 다시 보고한다.
   이것이 안전망이다.
4. open 항목이 원래 0건이고 C-5 의 규칙 테스트 확인이 끝났을 때도 마커를
   찍는다(원장 파일이 없으면 `mkdir -p` 후 마커 한 줄만). 마커가 없으면 커밋
   스윕은 매번 "첫 실행 — 기준선 HEAD" 로 돈다.

close 자신은 이 규약의 어느 쓰기도 하지 않는다 (NF-1).

## 착지 위치 — 매 세션 로드

이 파일은 close 실행 때만 읽힌다. 규약은 매 세션 로드되는 dotfiles 전역
[`claude/AGENTS.md`](https://github.com/dEitY719/dotfiles/blob/main/claude/AGENTS.md)
(1순위 — 모든 하네스가 읽고 `/correct` 미설치 환경도 덮는다) 또는 `/correct`
스킬 본문에 아래 블록으로 착지한다. 착지 전에는 원장이 사람이 지시할 때만
채워진다 (dEitY719/session-skills#42).

```markdown
## 반복 실수 원장 (session:close C-5)

원장 경로는 손으로 만들지 말고 `bash <session:close 스킬 디렉터리>/lib/check-correct.sh --ledger-path <repo>` 로 얻는다. 디렉터리가 없으면 `mkdir -p`.
1. 실수를 목격하면 `- [<ISO8601>] <class-slug>: <한 줄 설명>` 을 append 한다. 기존 줄은 고치지 않는다. 설명에 토큰·비밀값을 적지 않는다.
2. 같은 class-slug 2회차 -> 즉시 `/correct` 실행을 제안한다.
3. `/session:close` 가 보고한 open 항목을 사용자 결정대로 전부 처리했거나 open 0건 + 규칙 테스트 확인이 끝났을 때만 `swept: <now> <HEAD-sha>` 를 append 한다.
```

## 커밋 스윕 — Correction Rules 테스트

대상 저장소 최상위의 `AGENTS.md`(없으면 `CLAUDE.md`)에서 `Correction Rules`
가 들어간 헤딩(레벨 무관)부터 같거나 높은 레벨의 다음 헤딩까지가 섹션이다.
그 안 표의 데이터 행(헤더·구분 행 제외)이 규칙 하나씩이다.

- 행마다 백틱 `*.bats` 토큰을 뽑는다. 토큰이 없는 행은 "기계 검증 불가" 로
  센다 — 3개 규칙 중 1개만 검증하고 "통과" 라고 말하지 않기 위해서다.
- 토큰은 중복 제거 후 해석한다. 경로(`/` 포함)면 `git ls-files` 경로 일치,
  아니면 basename 정확 일치(`:(glob)**/<token>`). 0 매치는 WARN, 2+ 매치는
  전부 대상이다. `T18-T25` 같은 범위 표기는 무시하고 파일 단위로 다룬다.
- 새 커밋은 스윕을 켜는 게이트일 뿐, 커밋이 건드린 파일로 대상을 좁히지 않는다.
- **기본은 실행하지 않는다.** `(cd <repo> && bats <path...>)` 명령(경로는 셸
  인용)을 NOTE 로 찍는다. 저장소 테스트 실행은 임의 코드 실행이라 read-only 계약
  밖이다. 이 모드는 dirty tree 여도 명령을 찍는다.
- `--run-rule-tests` (사용자 opt-in) 일 때만 실행한다. 파일당 `timeout 60`,
  dirty tree 면 건너뛰고(WARN), 실행 전후 `git status --porcelain
  --untracked-files=all` 을 비교해 달라졌으면 WARN. 실패는 `NOTE: [RULE-FAIL] ...`
  다. 해석 실패 토큰이 하나라도 있으면 PASS 줄을 찍지 않는다.
