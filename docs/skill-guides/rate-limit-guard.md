# session:rate-limit-guard — 리밋 리셋 안전망 설치

> **한 줄 요약** — 장시간 무인 실행 전에, 토큰 리밋 리셋 시각 +5분에 한 번 발화하는 durable 크론과 `.claude/.rate-limit-guard.json` 상태 파일을 산출한다.

> **[Claude Code 전용]** `CronCreate` / `CronDelete` 가 필요하다 — 벽시계 시각에 새 에이전트
> 턴을 시작하는 도구. 다른 하네스에는 대응물이 없다. 그곳에서의 올바른 동작은 "사용 불가"
> 를 말하고 멈추는 것이다. `sleep`, 백그라운드 셸, `at` 잡, "나중에 하겠다" 는 약속은
> **대체재가 아니다** — 어느 것도 에이전트를 깨우지 못하면서 성공을 보고하고 아무것도 하지
> 않는다. 그건 거절보다 나쁘다.

## 언제 쓰나

- 퇴근하면서 긴 작업을 걸어두고, 리밋에 걸려도 리셋 후 자동으로 이어지게 하고 싶을 때
- 여러 사이클에 걸칠 만큼 긴 무인 실행을 시작하기 직전

## 언제 안 쓰나

| 상황 | 대신 쓸 것 |
|---|---|
| 리셋 후 실제로 재개하는 실행 주체 | `session:resume-after-limit` (이 크론이 부르는 쪽) |
| 상태 파일·정리 의미 없이 그냥 N분 뒤 실행 | `session:schedule` |
| 리밋이 아닌 API 에러·ESC 로 끊긴 복구 | `session:restart` |

## 호출 형식

```
/session:rate-limit-guard --reset HH:MM [--max-cycles N] [--cycle-window M] <command>
/session:rate-limit-guard -h
```

| 인자 | 설명 | 기본값 |
|---|---|---|
| `--reset HH:MM` | **필수.** 토큰 리밋 리셋 시각. `/usage` 로 확인 | 없음 |
| `--max-cycles N` | 최대 재개 사이클 수 (양의 정수) | 1 |
| `--cycle-window M` | 사이클 간격(분) | 305 |
| `<command>` | 감쌀 명령 (따옴표 보존) | 없음 |
| `--buffer` | **폐지됨.** 5분 마진은 상수. `[WARN]` 후 값 무시 | — |

## 동작 단계

1. **인자 파싱** — `--reset` 누락/오형식이면 `/usage` 안내 후 정지.
2. **첫 발화 시각 계산 + 컨텍스트 캡처** — `references/compute-fire-time.py HH MM 5`
   가 `<min> <hour> <dom> <month> <iso>` 를 낸다. 앞 네 개가 크론 식. 현재 `pwd` 와
   브랜치도 함께 잡는다.
3. **`CronCreate` 로 예약** — `recurring: false`, `durable: true`. 프롬프트는
   `references/cron-prompt-template.md` 를 그대로 치환해 넘긴다. 반환된 job ID 저장.
4. **상태 파일 기록** — 워크트리 루트에 `.claude/.rate-limit-guard.json`.
5. **확인 블록 출력.**
6. **감싼 명령 실행 후 성공 시 정리** — `CronDelete(<id>)` → 상태 파일 삭제 →
   `[OK] 안전망 해제 — 정상 완료`.

## 주의사항 / 제약

- **명시적 `--reset HH:MM` 없이는 절대 예약하지 않는다.**
- **`recurring: true` 나 `durable: false` 를 쓰지 않는다.**
- **transient 에러(리밋/네트워크/타임아웃)에서는 크론을 그대로 둔다.** 바로 그때가 안전망이
  발화해야 할 때다. 정리는 성공했을 때만 한다.
- 다른 스킬 안에서 호출하지 않는다 — 사용자 트리거 전용.
- durable 크론이 발화하려면 이 워크트리의 Claude Code 세션이 열려 있거나 같은 워크트리에서
  다시 열려야 한다.
- `--max-cycles 1` (기본) 이 기존 단일 사이클 동작을 보존한다.
- 크론 프롬프트 템플릿은 `resume-after-limit/references/preemptive-rearm.md` 에도 인라인
  사본이 있다. 한쪽을 바꾸면 같은 커밋에서 다른 쪽도 고쳐야 한다.
