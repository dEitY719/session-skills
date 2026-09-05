# session:handoff — Help

## Usage

```
/session:handoff                    # auto-resolve tracking issue, post handoff
/session:handoff 1767               # explicit issue number
/session:handoff 1767 upstream      # explicit issue + remote
/session:handoff --memory-only      # skip the issue comment, memory only
/session:handoff --new-issue        # force a new tracking issue
/session:handoff -h                 # show this help
/session:handoff --help             # show this help
/session:handoff help               # show this help
```

## What it does

When a long task is about to outlive the current session (end of day, a
planned interruption, or a context window near its limit), this skill writes the
handoff so the next session can resume without re-explaining:

1. Resolves the tracking issue (arg → conversation → branch → gh activity;
   creates one via gh-issue:create when the work deserves it, or falls back
   to memory-only when it doesn't).
2. Composes a structured handoff comment — verified done / remaining work /
   resume environment / open decisions — and posts it on the issue.
3. Updates auto-memory with the same resume state (issue = team-visible,
   memory = agent-local).
4. Prints a one-line copy-paste resume sentence, e.g. `#1767 P5b 진행`.

## When to invoke

- You are stopping for the day but the work continues tomorrow.
- You want the next session (or a teammate) to pick up exactly where this
  one stopped.
- The context window is approaching its limit mid-task.

Do NOT invoke for:

- Recording a finished one-off task — that's gh-issue:create or
  gh-issue:discussion-create.
- Resuming after an API error or ESC in the SAME session — that's
  session:restart.
- Auto-resuming after a token-limit reset via cron — that's
  session:resume-after-limit (this skill writes the handoff those resumers
  consume).

## Honesty rules

- Only merged PRs and tests that ran green in this session are listed as
  "완료 (검증됨)".
- Unverified edits are labeled 미검증 — never rounded up to done.
- The resume sentence must map to the real tracking issue and its actual
  next step.

## Constraints

- Writes exactly two artifacts: one issue comment (skippable with
  `--memory-only`) and one memory file. No commits, pushes, code edits, or
  issue state changes.
- Duplicate guard: a handoff comment already posted from this session is
  updated in place, not appended.
