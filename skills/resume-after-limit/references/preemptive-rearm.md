# Pre-emptive Re-arm — Step 4 Detail

When the state file's `cycles_remaining > 1`, register the next cycle's
cron **before** running the wrapped command. This guarantees a fresh
safety net even if the wrapped command rate-limits or crashes mid-run.

## Compute fire time

```bash
python3 -c "from datetime import datetime,timedelta as td; t=datetime.now()+td(minutes=$cycle_window_min); print(t.strftime('%M %H %d %m'),t.isoformat())"
```

Output: `<min> <hour> <dom> <month> <iso>` — first four = cron expression
(no DoW), `<iso>` = state-file timestamp.

## CronCreate parameters

- `cron`: the four fields above followed by `*` (e.g. `"05 23 06 05 *"`)
- `recurring`: `false`
- `durable`: `true`
- `prompt`: the template referenced below, substituting `<PWD_NOW>` with
  the state file's `worktree`, `<BRANCH>` with `branch`, and `<command>`
  with `command`. Pass the substituted result to `CronCreate` verbatim —
  do not paraphrase or wrap.

Save the returned ID as `<NEXT_ID>`.

### Cron prompt template

Use the template at
`../../rate-limit-guard/references/cron-prompt-template.md` (SSOT) — the
same one cycle 1 is registered with. Both skills ship in the `session`
plugin, so the path always resolves.

## Update state file

Overwrite `.claude/.rate-limit-guard.json` using the schema defined in
`../../rate-limit-guard/references/state-and-confirm.md` (SSOT).
Set `cron_id = <NEXT_ID>`, `scheduled_for = <new ISO>`, decrement
`cycles_remaining` by 1; preserve `command`, `worktree`, `branch`,
`max_cycles`, `cycle_window_min` from the loaded state.

## Drift behavior

The next fire is `now + cycle_window_min`, **not** `original_reset +
cycles_so_far * cycle_window_min`. This naturally absorbs any drift from
session-start delays — if cycle 1 fired 5 minutes late, cycle 2 will
also be 5 minutes late, matching real session-window timing.

Example (305-minute window, original reset 18:00, max-cycles 3):
- Cycle 1 fires 18:05 (reset + 5min margin)
- Cycle 2 fires `18:05 + 305min = 23:10`
- Cycle 3 fires `23:10 + 305min = 04:15` next day
