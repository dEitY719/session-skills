# session — harness support

Per-skill portability for the eight `session` skills, what each degraded cell
means in practice, and the two smaller gaps that apply everywhere outside
Claude Code. Summarised in [`README.md`](../README.md) under "Harness support".

This repo is more harness-coupled than most of its siblings, and the matrix says
so. Three of the eight skills exist only because Claude Code can schedule a
future agent turn; no other harness can, so those three do not run anywhere else
at all. Three more read the session TodoList, which most harnesses expose only
as a write-only tool, so they degrade. Only the two worktree skills are pure
`git` and behave identically everywhere.

| Skill | Claude Code | Codex | Kimi | Gemini / Antigravity | Hermes | OpenCode |
|-------|:-----------:|:-----:|:----:|:--------------------:|:------:|:--------:|
| `restart` | full | no TodoList | no TodoList | no TodoList | no TodoList | no TodoList |
| `close` | full | no TodoList (C-2) | no TodoList (C-2) | no TodoList (C-2) | no TodoList (C-2) | no TodoList (C-2) |
| `handoff` | full | no TodoList | no TodoList | no TodoList | no TodoList | no TodoList |
| `rate-limit-guard` | full | unavailable | unavailable | unavailable | unavailable | unavailable |
| `resume-after-limit` | full | unavailable | unavailable | unavailable | unavailable | unavailable |
| `schedule` | full | unavailable | unavailable | unavailable | unavailable | unavailable |
| `worktree-spawn` | full | full | full | full | full | full |
| `worktree-teardown` | full | full, confirm in chat | full | full | full, confirm in chat | full, confirm in chat |

*unavailable* — the skill declares `CronCreate` / `CronDelete`, tools that start
a fresh agent turn at a wall-clock time. No other harness has an equivalent, and
there is no workaround: a `sleep`, a backgrounded shell command, an `at` job, or
a promise to act later cannot wake an agent, so each of them reports success and
silently does nothing. The skill must say it cannot run here and stop. Refusing
is the correct behaviour, not a bug.

*no TodoList* — Claude Code's `TaskList` / `TaskUpdate` read and update the
session's todo list. Codex, Kimi, Gemini, Hermes, and OpenCode expose a
write-only todo tool at best. These three skills degrade rather than fail:
`restart` picks its resume target from the last completed tool result in the
conversation and still corroborates it with `git status --short`; `close`
reports C-2 as "TodoList unavailable on this harness" instead of passing
silently; `handoff` pulls remaining work from the conversation. Everything else
in all three — the chunking rules, the two `lib/` audits, the handoff comment,
the memory file — runs unchanged.

*confirm in chat* — `worktree-teardown` deletes a worktree and a branch. When
its pre-flight finds uncommitted changes or unpushed commits it stops and the
user decides. Kimi (`AskUserQuestion`) and Gemini (`ask_user`) have a structured
question tool; Codex, Hermes, Antigravity, and OpenCode do not, so ask in the
conversation and wait for a real reply. An auto-approve session setting is not
the user's answer, and `--force` is never the agent's shortcut past a block.

Two smaller gaps apply everywhere outside Claude Code. `handoff` may call
`Skill(gh-issue:create)` to open a tracking issue — read that skill's `SKILL.md`
inline, or just run `gh issue create`; the contract is an issue number. And
`handoff` Step 5 writes a Claude Code auto-memory file — write the equivalent
wherever the harness keeps agent memory, and if there is nowhere, emit one
`[WARN]` and let the issue comment carry the handoff. The memory step never
blocks.

Every gap and its workaround is documented per harness in
[`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references);
read the one file for the harness you are on.

The `lib/*.sh` helpers under `close/` are plain POSIX-friendly bash and run
identically on every harness. Call them; do not reimplement them.
