---
name: rate-limit-guard
description: >-
  [Claude Code Only] 장시간 명령에 리셋 시각 크론 안전망을 건다 — `CronCreate` 필요. Use for
  /session:rate-limit-guard, "rate limit 걸려도 자동 재개", "퇴근하면서 작업 시키고 limit 풀리면
  이어가게", "auto-resume after my token limit resets". 재개 실행은
  session:resume-after-limit 몫.
allowed-tools: Bash, Read, Write, CronCreate, CronDelete
metadata:
  model_recommendation:
    tier: haiku
    reason: "scheduling wrapper (CronCreate); low reasoning; deterministic cron spec generation"
    claude: prefer
    non_claude: advisory-only
---

# session:rate-limit-guard — Rate-Limit Resume Safety Net

> **Claude Code only**. Requires this worktree's Claude Code session to stay
> open (or be reopened in this worktree) so the durable cron can fire.

If arg #1 is `-h`/`--help`/`help`, or when you need usage/examples, print `references/help.md` verbatim and stop.

## Steps

### 1. Parse Arguments

Extract `--reset HH:MM` (required), `--max-cycles` (positive int, default 1),
`--cycle-window` (positive int, default 305). If `--buffer` is present, emit
`[WARN] --buffer 폐지됨 (5분 마진 = 상수). 값 무시.` and continue. Remaining tokens
are the wrapped command (preserve quoting). On missing/malformed `--reset`:
`필수 인자 --reset HH:MM 누락. /usage로 리셋 시각 확인 후 재시도.` and stop.

### 2. Compute First-Fire Time + Capture Context

`SKILL_DIR` = this file's directory.

```bash
python3 "${SKILL_DIR}/references/compute-fire-time.py" HH MM 5
PWD_NOW=$(pwd); BRANCH=$(git branch --show-current 2>/dev/null || echo unknown)
```

`5` is the hardcoded margin (formerly `--buffer`). Output:
`<min> <hour> <dom> <month> <iso>` (first four = cron expression).

### 3. Schedule via `CronCreate`

- `cron`: `"<min> <hour> <dom> <month> *"` (from step 2)
- `prompt`: see `references/cron-prompt-template.md` — substitute
  `<PWD_NOW>`, `<BRANCH>`, `<command>` and pass verbatim
- `recurring`: `false`, `durable`: `true`

Save the returned job ID.

### 4. Persist Cleanup State + 5. Confirm

Write `.claude/.rate-limit-guard.json` at the worktree root, then print
the confirm block. Read `references/state-and-confirm.md` for the
schema (with field descriptions) and the verbatim output template.

### 6. Execute, then Cleanup on Success

Hand off to the wrapped command. On success:
`CronDelete(<id>)` → `rm -f .claude/.rate-limit-guard.json` →
`[OK] 안전망 해제 — 정상 완료`.

On transient errors (rate limit / network / timeout), **leave the cron in
place** — that is exactly when the safety net should fire.

## Constraints

- Never schedule without explicit `--reset HH:MM`.
- Never use `recurring: true` or `durable: false`.
- Never auto-cleanup on transient errors.
- Never invoke from inside another skill — user-triggered only.
- `--max-cycles 1` (default) preserves PR #369 behavior.

## Related Skills

`session:resume-after-limit` — the companion the cron prompt calls to actually
re-run the wrapped command · `session:schedule` — generic session-local deferral
without the state file or cleanup semantics · `session:restart` — same-session
recovery for non-rate-limit interruptions.
