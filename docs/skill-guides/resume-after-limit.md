# session:resume-after-limit — 리밋 리셋 후 재개

> **한 줄 요약** — `session:rate-limit-guard` 가 남긴 상태 파일을 읽어, 옳은 워크트리인지 확인한 뒤 감싼 명령을 다시 실행하고, 다음 사이클을 미리 무장한 결과를 산출한다.

> **[Claude Code 전용]** `CronCreate` / `CronDelete` 가 필요하다. 이 스킬은 보통 사용자가
> 아니라 guard 가 건 크론이 부른다.

## 언제 쓰나

- 토큰 리밋 리셋 시각이 되어 guard 의 크론이 발화했을 때 (정상 경로)
- 같은 워크트리에서 수동으로 "리밋 풀렸으니 이어서" 하고 싶을 때

## 언제 안 쓰나

| 상황 | 대신 쓸 것 |
|---|---|
| 안전망을 *설치* 하는 쪽 | `session:rate-limit-guard` |
| API 에러·OOM·ESC 로 끊긴 같은 세션 복구 (크론 없음) | `session:restart` |
| 미완 작업을 다음 세션에 넘기기 | `session:handoff` |

## 호출 형식

```
/session:resume-after-limit                # 상태 파일을 읽어 재개
/session:resume-after-limit <command>      # 명시 override (크론 경로)
/session:resume-after-limit -h
```

## 동작 단계

1. **상태 로드** — `.claude/.rate-limit-guard.json` 에서 `command`, `worktree`,
   `branch`, `max_cycles`, `cycles_remaining`, `cycle_window_min` 파싱. 다중 사이클
   필드가 없으면 `max_cycles=1`, `cycles_remaining=1`, `cycle_window_min=305` 로 기본값.
2. **명령 결정** — 상태 파일의 `command` → `<command>` 인자 → 둘 다 없으면 정지.
3. **컨텍스트 sanity check** — `pwd != worktree` 면 **STOP**
   (`[FAIL] 워크트리 불일치`). 브랜치만 다르면 `[WARN]` 후 계속.
4. **선제적 재무장** — `cycles_remaining > 1` 이면 감싼 명령을 돌리기 **전에**
   다음 사이클 크론을 등록하고 `<NEXT_ID>` 를 저장한다.
5. **announce** — `[RESUME]` 블록에 워크트리·브랜치·사이클 번호를 찍는다.
6. **명령 실행** — 멱등 실행. 이미 끝난 sub-step 은 감싼 워크플로 자신의 멱등성이 건너뛴다.
7. **성공 시 정리** — 같은 턴에서 Step 4 크론을 `CronDelete` 하고 상태 파일을 지운다.
   발화한 크론 자신은 `recurring: false` 라 자동 삭제된다.

## 주의사항 / 제약

- **워크트리 불일치에서 Step 3 를 넘어가지 않는다.** 잘못된 디렉터리는 곧 잘못된 작업이다.
- **감싼 명령이 성공하기 전에는 상태 파일도, 다음 크론도 지우지 않는다.** 실패(transient
  이든 아니든) 시 둘 다 그대로 두어야 다음 발화가 이 스킬을 다시 트리거한다.
- 다른 스킬 안에서 호출하지 않는다 — 크론 또는 사용자 트리거 전용.
- `references/preemptive-rearm.md` 의 크론 프롬프트 템플릿은
  `rate-limit-guard/references/cron-prompt-template.md` 와 동기화되어야 한다.
