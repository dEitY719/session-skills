# State File Schema + Confirm Output Template

Single source of truth for `.claude/.rate-limit-guard.json` and the
Step 5 user-facing confirm block. Both `session:rate-limit-guard` (Steps
4–5) and `session:resume-after-limit` (`../../resume-after-limit/references/preemptive-rearm.md`) read from
this file — change the schema here and only here.

## State file: `.claude/.rate-limit-guard.json`

Location: worktree root. One JSON object per line — written compact so
it round-trips through `cat | jq` without reformat noise.

```json
{"cron_id":"<id>","command":"<command>","worktree":"<PWD_NOW>","branch":"<BRANCH>","scheduled_for":"<ISO>","max_cycles":<N>,"cycles_remaining":<N>,"cycle_window_min":<M>}
```

| Field | Type | Meaning |
|-------|------|---------|
| `cron_id` | string | ID returned by the most recent `CronCreate`. Used by Step 6 cleanup and by `resume-after-limit` re-arm. |
| `command` | string | Original wrapped command (verbatim, quoting preserved). Replayed unchanged on every cycle. |
| `worktree` | string | Absolute path captured at registration (`PWD_NOW`). `resume-after-limit` refuses to fire from a different worktree. |
| `branch` | string | Feature branch captured at registration. Sanity check only. |
| `scheduled_for` | string (ISO 8601) | Local fire time of the *current* cron — updated each re-arm. |
| `max_cycles` | int ≥ 1 | Total cycles requested via `--max-cycles N` (default 1). Constant for the lifetime of the state file. |
| `cycles_remaining` | int 0..N | Starts at `max_cycles`; `resume-after-limit` decrements by 1 every time it pre-emptively re-arms. |
| `cycle_window_min` | int ≥ 1 | Minutes between fires for cycles 2..N (`--cycle-window M`, default 305). |

Invariants: `0 ≤ cycles_remaining ≤ max_cycles`; the state file exists
iff a guard cron is currently scheduled. Step 6 deletes the file on
clean completion.

## Step 5 confirm output template

Printed verbatim after Step 4 succeeds. The `<HH:MM + 5min>` shows the
reset time plus the constant 5-minute margin.

```
[GUARD] Rate-limit 안전망 등록 (사이클 1/<N>, 간격 <M>분)
  • 원본 명령: <command>
  • 자동 재개 시각: <HH:MM + 5min> (job: <id>)
이제 원본 명령을 실행합니다 ↓
Next: 취소하려면 CronDelete(<id>) → rm -f .claude/.rate-limit-guard.json (순서대로 둘 다)
```

Both, in that order. The invariant above is that the state file exists *iff* a
guard cron is scheduled — removing only the file leaves the durable cron armed
and orphaned, and it will still fire.

## Step 6 teardown output template

Printed verbatim after the cron and state file are removed on success.

```
[OK] 안전망 해제 — 정상 완료
Next: 다음 장시간 실행 전에 /usage 로 리셋 시각을 다시 확인하세요
```
