# session:restart — Output Format

Two terminal-facing templates. Step 2 emits the announce line; Step 4 emits
the per-step progress lines and the closing `Next:`. A hard stop in Step 1
or Step 2 emits the failure template instead.

## Success (resume + execute)

```
[OK] resumed: <task subject> — 작은 단위로 쪼개서 진행합니다.
step 1/N: <what just landed>
step 2/N: <what just landed>
...
Next: <concrete command, e.g. /gh:issue-flow continue, /gh:pr-reply, /gh:pr>
```

Rules:

- The `[OK] resumed:` line is the announce line from Step 2 — print it
  before any tool call so the user can stop you cheaply if the picked
  target is wrong.
- One `step N/M:` line per chunk completed. No batched summaries.
- `Next:` MUST name a concrete command. Never silently return to idle.

## Hard stop (no resume target, no re-invoke, user-correction needed)

```
[FAIL] cannot resume: <reason>
Next: <one concrete recovery step>
```

Rules:

- `<reason>` is one short clause — e.g. `no in_progress or pending task`,
  `last action was a process skill (brainstorming) — its output is in
  context, re-invocation forbidden`.
- `Next:` proposes the single most likely recovery, not a menu.
