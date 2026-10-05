---
name: resume-after-limit
description: >-
  [Claude Code Only] 토큰 한계(rate limit) 리셋 후 session:rate-limit-guard 가 건 크론이
  호출하는 재개 스킬 — `CronCreate` 필요. Use for /session:resume-after-limit, "리밋 풀리면
  이어서", "resume after my token limit resets". API 에러·ESC 재개는
  session:restart.
allowed-tools: Bash, Read, Write, CronCreate, CronDelete
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "cron-driven re-run wrapper, low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# session:resume-after-limit — Resume After Rate-Limit Reset

> **Claude Code only**. Companion to `/session:rate-limit-guard`. Triggered by
> that skill's scheduled cron, or invoked manually in the same worktree.

If arg #1 is `-h`/`--help`/`help`, print `references/help.md` verbatim and stop.

## Usage

```
/session:resume-after-limit                # read state file, resume
/session:resume-after-limit <command>      # explicit override (cron path)
```

## Steps

### 1. Load State

`SKILL_DIR` = this file's directory.

```bash
STATE=$(python3 "$SKILL_DIR/lib/load-state.py") || exit 1; eval "$STATE"
```

Sets `COMMAND`, `WORKTREE`, `BRANCH`, `MAX_CYCLES`, `CYCLES_REMAINING`,
`CYCLE_WINDOW_MIN` (missing multi-cycle fields default to `1`/`1`/`305`); no
state file sets nothing. Surface its `[FAIL]` line verbatim and stop.

### 2. Resolve the Command

State file's `command` → `<command>` arg → stop with
`재개할 명령을 알 수 없습니다 (state 파일·인자 모두 없음).`

### 3. Sanity Check Context

```bash
python3 "$SKILL_DIR/lib/load-state.py" --check-context || exit 1
```

Worktree mismatch prints `[FAIL] 워크트리 불일치 — 예상: <worktree>, 현재: <PWD_NOW>.`
and exits 1: STOP. Branch mismatch prints `[WARN] 브랜치 이동`: continue.

### 4. Pre-emptive Re-arm

If `cycles_remaining > 1`, register the next cycle's cron **before** running
the wrapped command per `references/preemptive-rearm.md` (fire-time arithmetic,
`CronCreate` args, state-file rewrite). Save `<NEXT_ID>` for Step 7. Else skip.

### 5. Announce

Print the announce block in `references/output-format.md` verbatim.

### 6. Execute the Command

Hand off to the wrapped command. The wrapped workflow's own idempotency handles already-done sub-steps.

### 7. Cleanup on Success

In the same turn after success, run the cleanup sequence and print the
terminal line in `references/output-format.md`. On failure (transient or
otherwise), **leave state + next cron** in place and print that file's failure
terminal line instead — the next fire re-triggers this skill, or the user
re-invokes manually.

## Constraints

- If `CronCreate` is unavailable or the Step 4 re-arm call fails, stop and
  report `[FAIL] CronCreate 사용 불가 — 재개 크론 재등록 실패, 명령 미실행.` —
  never substitute `sleep`, a background shell, an `at` job, or a promise to
  act later; none of them can open a fresh agent turn, so each reports
  success without actually resuming the agent.
- Never proceed past Step 3 on worktree mismatch — wrong dir = wrong work.
- Never delete state or the next cron before the wrapped command succeeds.
- Never invoke from inside another skill — cron- or user-triggered only.

## Related Skills

`session:rate-limit-guard` — the scheduler that writes the state file and cron this
skill consumes · `session:restart` — same-session recovery from an API flake / OOM /
ESC, no cron · `session:handoff` — hands unfinished work to the next session.
