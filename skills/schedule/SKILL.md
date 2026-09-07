---
name: schedule
description: >-
  [Claude Code Only] 슬래시 명령/작업을 N분 뒤 실행되도록 예약(기본 5분). `CronCreate` 도구 필요 —
  Codex / Gemini CLI 에서는 동작하지 않는다. Use for /session:schedule, "N분 후에 /skill
  실행해", "schedule /skill in N minutes". 세션 로컬 지연 전용 — 반복 주기 실행은 내장 /loop 스킬.
allowed-tools: Bash, CronCreate
license: MIT
metadata:
  model_recommendation:
    tier: haiku
    reason: "simple cron registration"
    claude: prefer
    non_claude: advisory-only
---

# session:schedule — Deferred Skill Executor

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

> **Claude Code only** — requires the `CronCreate` tool, which is part of the
> Claude Code harness. Other CLIs (Codex, Gemini, etc.) lack a comparable
> session-spawn scheduler, so this skill cannot run there.
> See [issue #362](https://github.com/dEitY719/dotfiles/issues/362).

**Stop-on-error policy** — if `CronCreate` is unavailable or its call fails,
print the Step 4 `[FAIL]` line and stop. Never substitute `sleep`, a background
shell, an `at` job, or a promise to act later — none of them wake an agent, so
each reports success while nothing is scheduled. Soft-fail: a non-positive
`--time` falls back to 5 with a warning.

## Usage

```
/session:schedule [--time M] "<command>"
/session:schedule [--time M] /skill-name [args...]
```

Argument table and worked examples: `references/help.md`.

## Steps

### 1. Parse Arguments

Extract `--time M` (default 5) and the command/skill (everything after the flags).
If M is not a positive integer, default to 5 and warn the user.

| Input | M | command |
|-------|---|---------|
| `--time 10 "/gh-pr:reply 350"` | 10 | `/gh-pr:reply 350` |
| `/gh-resolve:conflict 351` | 5 | `/gh-resolve:conflict 351` |
| `--time 3 "PR 리뷰해"` | 3 | `PR 리뷰해` |

### 2. Calculate Fire Time

Run Bash with the shared fire-time helper (`SKILL_DIR` = this file's directory;
`session:rate-limit-guard` owns the script — its docstring is the SSOT):

```bash
python3 "${SKILL_DIR}/../rate-limit-guard/references/compute-fire-time.py" --in "$M"
```

Output: `<min> <hour> <dom> <month> <iso>`, local time. Step 1 already guarantees
`M` is positive; on a non-zero exit anyway, fall back to `--in 5` and warn.

### 3. Schedule with `CronCreate`

Call `CronCreate`:
- `cron`: `"<min> <hour> <dom> <month> *"` (values from step 2)
- `prompt`: the extracted command (verbatim — passed to Claude at fire time)
- `recurring`: `false` (one-shot — fires once then auto-deletes)

### 4. Confirm to User

Success, then failure (`<HH:MM>` comes from the helper's ISO field):

```
[OK] scheduled
  when:    <M>분 후 (<HH:MM>)
  command: <command>
  job:     <returned-id>

Next: 취소는 CronDelete(<returned-id>) — 예약 목록은 CronList
```

```
[FAIL] cannot schedule — <reason, e.g. CronCreate unavailable on this harness>
```

## Related Skills

`session:rate-limit-guard` is the rate-limit specialization of this skill
(reset-time cron + state file + cleanup). Built-in `/loop` covers recurring
interval runs — its own description says "Do NOT invoke for one-off tasks".
This skill is the session-local one-shot deferral, called by
`gh-verify:review-all` with `--defer-reply M` to postpone its `/gh-pr:reply` pass.
