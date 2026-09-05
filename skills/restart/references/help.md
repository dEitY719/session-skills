# session:restart — Help

## Usage

```
/session:restart            # resume the current in_progress task in small steps
/session:restart -h         # show this help
/session:restart --help     # show this help
/session:restart help       # show this help
```

## What it does

Recovers from an interrupted turn — usually a Claude API flake
(`socket connection was closed unexpectedly`, gateway timeout, OOM,
`Not logged in · Please run /login`, etc.) —
without losing context. Picks up the previous in_progress TodoList item and
resumes it in single-tool-call chunks, with large outputs delegated to
subagents so the next failure costs less.

## When to invoke

- Your last turn died mid-action and the spinner stopped.
- The model produced an `API Error` and ended the turn.
- A long batch of edits got cut off and you don't want to re-explain it.
- The task was too large and you interrupted it with ESC to restart in smaller chunks.
- Your session was interrupted by an auth/login expiry
  (`Not logged in · Please run /login`) and you already re-authenticated.

Do NOT invoke for:

- A normal "what's next" question — just ask directly.
- Starting a brand-new task (use the relevant feature skill instead).
- Recovering from a logic bug — that's `superpowers:systematic-debugging`.

## Behavior summary

1. Reads the current TodoList; resumes from the `in_progress` item (or first
   `pending` if none, or asks the user if both are empty).
2. Announces one line: `재개: <task> — 작은 단위로 쪼개서 진행합니다.`
3. Splits the next action into 1-tool-call steps. Delegates broad reads /
   searches to `Agent(Explore)` or `Agent(general-purpose)`.
4. Updates TodoList status after each step. Hands control back to the
   originating flow (e.g. `gh-flow:issue`) when the resumed task is done.

## Constraints

- Will not re-invoke a process skill (brainstorming / TDD / debugging) that
  already produced output earlier in the conversation.
- Will not batch tool calls — the whole premise is that the previous batch
  died mid-way.
- Cannot be invoked programmatically by another skill — user-triggered only.
