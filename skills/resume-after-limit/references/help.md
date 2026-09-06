# session:resume-after-limit — Help

## Usage

```
/session:resume-after-limit              # read state file, resume
/session:resume-after-limit <command>    # explicit override (cron path)
```

| Option | Description | Default |
|---|---|---|
| `[command]` | 재개할 명령 (크론 경로에서 명시적으로 넘길 때) | state 파일의 `command` |
| `-h` / `--help` / `help` | 이 도움말 출력 후 정지 | — |

## What it does

Companion to `/session:rate-limit-guard`. When the scheduled cron fires after
the rate-limit reset, this skill:

1. Reads `.claude/.rate-limit-guard.json` to recover the original command,
   the worktree/branch the guard was registered in, and the multi-cycle
   bookkeeping (`max_cycles`, `cycles_remaining`, `cycle_window_min`).
2. Verifies `pwd` matches the recorded worktree (STOPS on mismatch).
3. Warns but continues if the branch has moved.
4. **(multi-cycle)** If `cycles_remaining > 1`, pre-emptively registers the
   next cycle's cron (fire = `now + cycle_window_min` minutes) **before**
   running the wrapped command. The next cron's prompt also calls
   `/session:resume-after-limit`, with `cycles_remaining` decremented in state.
5. Announces the resume to the user.
6. Re-runs the original command — relying on its idempotency to skip
   already-completed sub-steps.
7. On success, deletes the state file and `CronDelete`s the next-cycle cron
   (if Step 4 ran). The just-fired cron auto-deleted (`recurring: false`).

## When to invoke

- **Automatically**: by the cron prompt scheduled by `/session:rate-limit-guard`
  when token-limit reset (or a subsequent cycle window) arrives.
- **Manually**: if Claude was closed when the cron should have fired and
  you want to trigger the same recovery flow yourself in the worktree.

## Multi-cycle behavior

With `--max-cycles N` (where N > 1), each fire of this skill re-arms the
next cycle before running the wrapped command. This means:

- Even if the wrapped command rate-limits or crashes mid-cycle, the next
  cron is already in place — nothing to re-trigger manually.
- On success at any cycle, the state file + the *next* cron are cleared,
  so you don't get redundant fires.
- `cycles_remaining` decrements per fire; on `cycles_remaining <= 1`,
  Step 4 is skipped (no further cycles to schedule).

## Prerequisites

- Run from inside the same git worktree where `/session:rate-limit-guard`
  was originally invoked.
- `.claude/.rate-limit-guard.json` exists (auto-created by the guard).
  Without it, the only fallback is an explicit `<command>` argument.
- A state file with no multi-cycle fields is treated as `max_cycles=1`,
  `cycles_remaining=1`, `cycle_window_min=305` — single-cycle behavior.

## Constraints

- Stops on worktree mismatch — wrong directory = wrong work.
- Branch movement triggers a warning but does not stop execution
  (you may have rebased or moved HEAD between guard-time and resume-time).
- Pre-emptive re-arm only fires when `cycles_remaining > 1`.
- The wrapped command must be idempotent (`/gh-flow:issue` etc. are).
- On a second failure (resume itself fails), the state file **and** the
  next-cycle cron are preserved so the next fire (or a manual re-invoke)
  can pick up where this attempt left off.

## Pairs with

- `/session:rate-limit-guard` — the scheduler that creates the state and cron
  this skill consumes.
- `/session:restart` — same-session API-flake recovery (socket disconnect,
  OOM). Different problem; not a substitute.
