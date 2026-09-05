---
name: schedule
description: >-
  [Claude Code Only] 슬래시 명령/작업을 N분 뒤 실행되도록 예약(기본 5분). `CronCreate` 도구 필요 —
  Codex / Gemini CLI 에서는 동작하지 않는다. Use for /session:schedule, "N분 후에 /skill
  실행해", "schedule /skill in N minutes". 세션 로컬 지연 전용 — 반복 주기 실행은 내장 /loop 스킬.
allowed-tools: [CronCreate]
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

## Usage

```
/session:schedule [--time M] "<command>"
/session:schedule [--time M] /skill-name [args...]
```

- `--time M` — delay in **minutes** (positive integer, default: **5**)
- `<command>` — skill invocation or natural-language task to run after the delay

## Examples

```
/session:schedule --time 10 "/gh-pr:reply 350"      # /gh-pr:reply in 10 min
/session:schedule /gh-resolve:conflict 351          # run in 5 min (default)
/session:schedule --time 3 "PR #200 리뷰 코멘트 처리해"
```

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

Run Bash to get the target cron fields in local time:

```bash
python3 -c "from datetime import datetime, timedelta; print((datetime.now() + timedelta(minutes=M)).strftime('%M %H %d %m'))"
```

Replace `M` with the parsed minute value. Output: `<min> <hour> <dom> <month>`.

### 3. Schedule with `CronCreate`

Call `CronCreate`:
- `cron`: `"<min> <hour> <dom> <month> *"` (values from step 2)
- `prompt`: the extracted command (verbatim — passed to Claude at fire time)
- `recurring`: `false` (one-shot — fires once then auto-deletes)

### 4. Confirm to User

Print one line after scheduling:

```
[SCHEDULED] [M]분 후에 실행됩니다: <command>  (job: <returned-id>)
```

## Related Skills

`session:rate-limit-guard` — the rate-limit specialization of this skill (reset-time
cron + state file + cleanup) · built-in `/loop` — recurring interval runs, and
its own description says "Do NOT invoke for one-off tasks"; this skill is the
session-local one-shot deferral, used by `gh-flow:issue` for its in-flow delay
steps.
