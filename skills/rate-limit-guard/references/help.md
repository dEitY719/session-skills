# session:rate-limit-guard — Help

## Usage

```
/session:rate-limit-guard --reset HH:MM [--max-cycles N] [--cycle-window M] <command>
/session:rate-limit-guard -h            # show this help
/session:rate-limit-guard --help        # show this help
/session:rate-limit-guard help          # show this help
```

## Examples

```
# 1-shot safety net (default — single cycle)
/session:rate-limit-guard --reset 18:00 /gh-flow:issue 399

# Multi-cycle: re-arm up to 3 times, 305 min apart (5h05m default window)
/session:rate-limit-guard --reset 18:00 --max-cycles 3 /gh-flow:issue 399

# Custom cycle window (e.g. 4h = 240 min)
/session:rate-limit-guard --reset 18:00 --max-cycles 4 --cycle-window 240 /gh-flow:issue 399

# Wrap a natural-language task
/session:rate-limit-guard --reset 18:00 --max-cycles 2 "PR 200 리뷰 코멘트 처리해"
```

## Arguments

| Option | Description | Default |
|---|---|---|
| `--reset HH:MM` | 토큰 리밋 리셋 시각, 24h local (필수 — `/usage` 로 확인) | — |
| `--max-cycles N` | 재무장할 최대 사이클 수 | `1` |
| `--cycle-window M` | 사이클 2..N 간 간격(분). 누적 — cycle 2 = `cycle 1 fire + M`, cycle 3 = `cycle 2 fire + M`, … | `305` (5h05m) |
| `<command>` | 감쌀 명령 (따옴표 보존) | — |
| `--buffer M` | 폐지됨 — `--reset` 뒤 5분 마진은 상수. `[WARN]` 후 값 무시 | — |
| `-h` / `--help` / `help` | 이 도움말 출력 후 정지 | — |

## What it does

Wraps a long-running task with a rate-limit safety net so work resumes
automatically when your token limit resets, even if you walked away.

1. Schedules a `CronCreate(durable=true)` for `<reset + 5min>` whose prompt
   re-runs the wrapped command (with worktree/branch context).
2. Persists state (including `max_cycles`/`cycles_remaining`/`cycle_window_min`)
   to `.claude/.rate-limit-guard.json` (per worktree).
3. Runs the wrapped command in the current session.
4. On normal completion, removes the cron job and state file.
5. If rate-limit hits mid-task, the cron fires later in the (still-idle) REPL.
   `/session:resume-after-limit` then handles re-arming subsequent cycles.

## Multi-cycle scenarios

A single Anthropic 5h reset window often isn't enough for an overnight
`/gh-flow:issue`. With `--max-cycles 3 --cycle-window 305`:

- Cycle 1: fires at `--reset + 5min` (e.g. 18:05)
- Cycle 2: fires at cycle-1-fire + 305min (e.g. 23:10)
- Cycle 3: fires at cycle-2-fire + 305min (e.g. 04:15 next day)

Each cycle re-runs the wrapped command. Idempotent workflows
(`/gh-flow:issue`) detect already-done sub-steps and skip them. Successful
completion at any cycle clears all remaining crons + the state file.

## Prerequisites

- Run `/usage` first to learn your reset time
  (e.g. `Resets 6pm (Asia/Seoul)` → `--reset 18:00`).
- Pass `--reset` in 24h local format.
- Keep this worktree's Claude Code session open (or reopen Claude Code in
  this worktree) — durable crons only fire while a REPL is idle.

## When to invoke

- Long workflows that may rate-limit (`/gh-flow:issue`, `/loop`).
- Overnight runs where one 5h reset isn't enough — use `--max-cycles N`.
- Any task you'd otherwise have to manually retrigger 2–3 hours later.

## Constraints

- Claude Code only — `CronCreate` is not available on Codex/Gemini CLIs.
- The worktree's Claude Code session must be open or be reopened in this
  worktree for the cron to fire.
- The wrapped command must be idempotent; re-running should detect and skip
  already-completed sub-steps (e.g. `/gh-flow:issue` won't re-create an
  existing PR or duplicate a commit).
- 5-min margin after `--reset` is hardcoded; `--buffer` is deprecated.
- Cleanup runs only on definitive success — transient errors leave the
  safety net in place so it can still fire.

## Pairs with

- `/session:resume-after-limit` — companion the cron prompt prefers. Verifies
  worktree/branch sanity, pre-emptively re-arms the next cycle when
  `cycles_remaining > 1`, then re-runs the original command.
- `/session:restart` — same-session recovery for non-rate-limit API flakes
  (socket disconnect, OOM). Different problem; not a substitute.
- `/session:schedule` — generic deferred execution; this skill is a
  specialization for the rate-limit case with cleanup semantics.
