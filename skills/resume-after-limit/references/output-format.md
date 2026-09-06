# Output Format — Steps 5 and 7 Detail

## Step 5 — Announce block

Print, substituting `<command>`, `<PWD_NOW>`, `<BRANCH>`, and the cycle
counter (`max_cycles - cycles_remaining + 1` of `max_cycles`):

```
[RESUME] [rate-limit-guard] 재개: <command>
  • 워크트리: <PWD_NOW>  • 브랜치: <BRANCH>
  • 사이클: <max_cycles - cycles_remaining + 1>/<max_cycles>
  • 멱등 실행 — 이미 완료된 sub-step은 스킵.
```

## Step 7 — Cleanup on success

```bash
[ -n "$NEXT_ID" ] && CronDelete <NEXT_ID>   # only if Step 4 ran
rm -f .claude/.rate-limit-guard.json
```

Then print:

```
[OK] 재개 완료 — 안전망 상태 파일 정리됨
Next: 남은 사이클 없음 — 새 장시간 실행은 /session:rate-limit-guard 로 다시 무장하세요
```

The just-fired cron auto-deleted (`recurring: false`); the Step 4 next-cycle
cron must be explicitly cancelled via `CronDelete`.

## Step 7 — On failure

Leave state + next cron in place (never delete before success), then print:

```
[FAIL] 재개 실패 — 상태 파일·다음 크론 보존됨
Next: 다음 크론 발화(<scheduled_for>)를 기다리거나 /session:resume-after-limit 로 수동 재시도
```

`<scheduled_for>` is the state file's field for the next fire (or the just-run
one if Step 4 was skipped) — read it back from the file before printing, since
Step 4 may have already rewritten it.
