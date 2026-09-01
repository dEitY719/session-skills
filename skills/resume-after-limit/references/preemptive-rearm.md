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
- `prompt`: the inline template below, substituting `<PWD_NOW>` with
  the state file's `worktree`, `<BRANCH>` with `branch`, and `<command>`
  with `command`. Pass the substituted result to `CronCreate` verbatim —
  do not paraphrase or wrap.

Save the returned ID as `<NEXT_ID>`.

### Cron prompt template (inlined)

This template is intentionally inlined here (not referenced via a
cross-skill path) so `session:resume-after-limit` stays independent of
`session:rate-limit-guard`'s directory layout. The same template lives at
`rate-limit-guard/references/cron-prompt-template.md` for the
initial cycle 1 registration; both copies must stay in sync when edited.

```
[Auto-resume by /session:rate-limit-guard]
워크트리: <PWD_NOW>
브랜치: <BRANCH>
원본 명령: <command>

현재 워크트리·브랜치가 위와 같으면 `/session:resume-after-limit`을 호출하여
재개. 그 스킬이 state 파일에서 multi-cycle 정보(`cycles_remaining`,
`cycle_window_min`)를 읽어 다음 cycle을 자동 재무장한다. 워크트리/브랜치가
다르면 사용자에게 알리고 중단.

만약 `/session:resume-after-limit` 스킬이 없는 환경이라면, fallback으로 원본
명령을 직접 멱등 재실행 (단일 cycle 동작, PR #369 호환).
```

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
