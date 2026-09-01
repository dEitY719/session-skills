# session:schedule — N분 뒤 실행 예약

> **한 줄 요약** — 슬래시 명령이나 자연어 작업 하나를 M분(기본 5) 뒤 한 번만 실행하는 세션 로컬 one-shot 크론을 산출한다.

> **[Claude Code 전용]** `CronCreate` 도구가 필요하다. Codex / Gemini CLI 등에는 세션을
> 깨우는 대응 스케줄러가 없어 이 스킬은 그곳에서 동작하지 않는다
> ([dotfiles #362](https://github.com/dEitY719/dotfiles/issues/362)). 그럴 때는 "사용
> 불가" 를 말하고 멈춰야 한다 — `sleep` 이나 백그라운드 셸로 흉내내면 성공을 보고하고
> 아무 일도 일어나지 않는다.

## 언제 쓰나

- "N분 후에 /skill 실행해" 처럼 단순 지연이 필요할 때
- CI 나 리뷰 봇이 결과를 낼 시간을 벌어야 할 때
- `gh:issue-flow` 처럼 흐름 중간에 대기 단계가 필요한 스킬의 구성 요소로

## 언제 안 쓰나

| 상황 | 대신 쓸 것 |
|---|---|
| 토큰 리밋 리셋 특화 (상태 파일 + 정리 의미까지) | `session:rate-limit-guard` |
| 반복 실행되는 클라우드 정기 루틴 | 내장 `/schedule` 스킬 |

이 스킬은 **세션 로컬 one-shot 지연** 전용이다.

## 호출 형식

```
/session:schedule [--time M] "<command>"
/session:schedule [--time M] /skill-name [args...]
/session:schedule -h
```

| 인자 | 설명 | 기본값 |
|---|---|---|
| `--time M` | 지연 시간(분, 양의 정수) | 5 |
| `<command>` | 지연 후 실행할 스킬 호출 또는 자연어 작업 | 없음 |

M 이 양의 정수가 아니면 5로 되돌리고 경고한다.

### 예시

```
/session:schedule --time 10 "/gh-pr-reply 350"
/session:schedule /gh-pr-resolve-conflict 351
/session:schedule --time 3 "PR #200 리뷰 코멘트 처리해"
```

## 동작 단계

1. **인자 파싱** — `--time M` 과 그 뒤 전부를 명령으로 분리.
2. **발화 시각 계산** — 로컬 시간 기준으로 `<min> <hour> <dom> <month>` 산출.
3. **`CronCreate` 예약** — `cron` 은 위 네 필드 + `*`, `prompt` 는 추출한 명령
   **그대로**(발화 시점에 Claude 에게 전달), `recurring: false`.
4. **확인 한 줄** — `[SCHEDULED] [M]분 후에 실행됩니다: <command>  (job: <id>)`.

## 주의사항 / 제약

- `recurring: false` — 한 번 발화하고 자동 삭제된다.
- 프롬프트는 발화 시점의 새 턴에 그대로 전달되므로, 그 시점에 해석 가능한 명령이어야 한다.
- 세션 로컬이다. 세션이 닫히면 이 크론에 의존한 흐름도 함께 끝난다고 보아야 한다.
