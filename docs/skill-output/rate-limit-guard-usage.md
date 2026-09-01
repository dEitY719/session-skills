# rate-limit-guard 사용 결과

> **한 줄 요약** — 리셋 시각과 감쌀 명령을 받아 durable 크론과 상태 파일을 생성합니다.

```
--reset HH:MM + 명령  ──▶  /session:rate-limit-guard  ──▶  durable 크론 + .rate-limit-guard.json
```

## 1. 실행한 명령

범용 형식:

```
/session:rate-limit-guard --reset HH:MM [--max-cycles N] [--cycle-window M] <command>
```

## 2. 입력

- `--reset HH:MM` — `/usage` 로 확인한 토큰 리밋 리셋 시각 (필수)
- `<command>` — 리밋에 걸려도 이어가야 할 장시간 명령

## 3. 결과

**이 문서는 실제 실행 기록이 아니다 — 실행하지 않았다.**

사유: 이 스킬은 `durable: true` 크론을 등록하고 워크트리 루트에
`.claude/.rate-limit-guard.json` 을 쓴다. 게다가 "transient 에러에서는 크론을 정리하지
않는다" 가 명시적 안전 계약이라, 데모로 걸어둔 안전망이 의도치 않게 살아남을 수 있다.
사용자와 합의해 미실행으로 남긴다.

실행했다면 `references/compute-fire-time.py HH MM 5` 가 `<min> <hour> <dom> <month> <iso>`
를 내고, 앞 네 필드가 크론 식이 된다 (5분 마진은 상수 — 구 `--buffer` 는 폐지). 확인 블록의
형식은 `references/state-and-confirm.md` 에 있다.

이 스킬은 짝인 `session:resume-after-limit` 없이는 반쪽이다 — 여기서 쓴 상태 파일을
그쪽이 읽는다. 크론 프롬프트 템플릿이 양쪽 `references/` 에 인라인으로 중복되어 있으므로
한쪽을 고치면 같은 커밋에서 다른 쪽도 고쳐야 한다.
