# session:schedule — Help

## Synopsis

```
/session:schedule [--time M] "<command>"
/session:schedule [--time M] /skill-name [args...]
```

## Description

Schedule a skill or command to run after a specified delay using the
`CronCreate` tool. Claude Code only — Codex and Gemini CLIs lack a comparable
session-spawn scheduler.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `--time M` | Delay in minutes (positive integer). | `5` |
| `<command>` | Skill invocation or natural-language task to run after the delay. | — |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## When to invoke

Always invoke this skill whenever the user wants to defer **any** slash-command
or task to run after a time delay — "N분 후에 /skill 실행해", "M분 뒤에 [skill]
수행해", "[command] N분 후에 해줘", "schedule /skill in N minutes".

Not this skill: a recurring interval run is the built-in `/loop` skill, whose
own description says "Do NOT invoke for one-off tasks"; a rate-limit reset
safety net (state file + cleanup) is `session:rate-limit-guard`.

## Examples

```
/session:schedule --time 10 "/gh-pr:reply 350"
/session:schedule /gh-resolve:conflict 351
/session:schedule --time 3 "PR #200 리뷰 코멘트 처리해"
```

## Stop conditions

- `CronCreate` tool is unavailable (non-Claude-Code harness) — refuse and explain.
- `--time` is not a positive integer — fall back to default `5` and warn the user.
