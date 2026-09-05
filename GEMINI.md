# session — skill index

Eight skills for the boundaries of a coding session, grouped by *when* they
fire rather than by what they touch. Each lives in this extension's `skills/`
directory. They are explicitly invoked, never ambient: load the one that
matches the request by reading its `SKILL.md`, then follow it. Do not load all
eight.

| Skill | Read | Use when |
|-------|------|----------|
| `restart` | `@./skills/restart/SKILL.md` | The last turn died mid-action — API error, OOM, auth expiry, or the user pressed ESC — and the same session is still alive. Resumes in small chunks. |
| `close` | `@./skills/close/SKILL.md` | The user is about to end the session and wants to know whether anything would be lost. Read-only audit, `[OK]` or `[BLOCKED]` verdict. |
| `handoff` | `@./skills/handoff/SKILL.md` | The context window is nearly full and work is *unfinished*. Writes the handoff into a tracking-issue comment plus a memory file. |
| `rate-limit-guard` | `@./skills/rate-limit-guard/SKILL.md` | **Cannot run on Gemini CLI** — needs `CronCreate`. Read it only to explain the gap. |
| `resume-after-limit` | `@./skills/resume-after-limit/SKILL.md` | **Cannot run on Gemini CLI** — it is what `rate-limit-guard`'s cron invokes. |
| `schedule` | `@./skills/schedule/SKILL.md` | **Cannot run on Gemini CLI** — needs `CronCreate`. |
| `worktree-spawn` | `@./skills/worktree-spawn/SKILL.md` | Starting isolated work: create `../<project>-<agent>-<N>` on a `wt/<agent>/<N>` branch so parallel agents do not collide. |
| `worktree-teardown` | `@./skills/worktree-teardown/SKILL.md` | The work in a worktree is done: remove the worktree, sync main, delete the branch. Destructive — read the safety rules. |

Each skill's `references/` directory holds the detail it loads on demand, and
`session:close` keeps its deterministic checks in `lib/*.sh`. `SKILL.md` says
which file to read and which script to run, and when. Do not read `references/`
up front, and do not reimplement `lib/` in prose.

## The two pairs

- **`rate-limit-guard` + `resume-after-limit`** are one mechanism split across
  two fires. The guard computes the reset time, arms a durable one-shot cron,
  and writes `.claude/.rate-limit-guard.json`; the resumer is what that cron
  invokes — it reads the state file, verifies it is in the right worktree, and
  re-runs the wrapped command. Neither is useful without the other, and neither
  runs on Gemini CLI.
- **`close` vs `handoff`** answer different questions at the same moment. Close
  means the session finished cleanly: audit, print a verdict, change nothing.
  Handoff means the session is running out of context with work unfinished:
  write that work down where the next session can find it.

## What each skill needs

- **`restart`, `close`, `handoff`** read the session TodoList through Claude
  Code's `TaskList`. Gemini CLI's `write_todos` writes but does not replay a
  list, so see the gaps below.
- **`handoff`** needs `gh` authenticated against the tracking issue's repo, and
  a writable agent-memory location.
- **`close`** needs `bash` for its two `lib/` scripts and, optionally, `gh` to
  check the state of issues and PRs this session created.
- **`rate-limit-guard`, `resume-after-limit`, `schedule`** need Claude Code's
  `CronCreate` / `CronDelete`. There is no Gemini equivalent.
- **`worktree-spawn`, `worktree-teardown`** need only `git` and a writable
  parent directory. `worktree-spawn` additionally handles `git-crypt` repos.

## Tool mapping for Gemini CLI

The skills speak in actions. On Gemini CLI these resolve to:

- "Read a file" -> `read_file` / `read_many_files`
- "Create a file" / "edit a file" -> `write_file`, `replace`
- "Run a shell command" -> `run_shell_command` (this is how every `git`,
  `gh`, and `lib/*.sh` call is made)
- "Search file contents" -> `grep_search`
- "Find files by name" -> `glob`
- "Create a todo" -> `write_todos`
- "Ask the user" -> `ask_user`
- "Dispatch a subagent" -> `invoke_agent` with `agent_name: "generalist"`

The full mapping, including every capability gap and its workaround, lives in
the sibling repo: `https://github.com/dEitY719/harness-skills/blob/main/references/gemini-tools.md`.
This repo owns no copy. Read it when a skill names a tool you do not recognise.
On Antigravity read `antigravity-tools.md` in that same directory instead —
`agy` shares `~/.gemini` but not Gemini CLI's tool names.

## Capability gaps on Gemini CLI

- **No cron.** `rate-limit-guard`, `resume-after-limit`, and `schedule` declare
  `CronCreate` / `CronDelete`. Gemini CLI has no session-spawning scheduler.
  Say the skill cannot run here and stop. Do **not** substitute a `sleep`, a
  backgrounded `run_shell_command`, an `at` job, or a promise to act later —
  none of them can start a new agent turn, so all of them silently do nothing.
- **No readable TodoList.** `TaskList` / `TaskUpdate` have no Gemini
  equivalent. `restart` therefore picks its resume target from the last
  completed tool result in the conversation instead of from the `in_progress`
  item, and still runs `git status --short` to corroborate it. `close` reports
  C-2 as "TodoList unavailable on this harness" rather than passing it
  silently. `handoff` pulls remaining work from the conversation.
- **No `Skill()` invocation.** `handoff` may call `Skill(gh-issue:create)` to
  open a tracking issue. Read that skill's `SKILL.md` from the `gh-*` plugin
  and follow it inline, or run `gh issue create` directly. The contract is just
  an issue number.
- **Agent-local memory.** `handoff` Step 5 writes a Claude Code auto-memory
  file. Write the equivalent note wherever Gemini keeps agent memory; if there
  is nowhere, say so in one `[WARN]` line and let the issue comment carry the
  handoff. Never let the memory step block the handoff.
- Nothing else is Claude-Code-specific. `lib/*.sh` is plain bash and runs
  unchanged under `run_shell_command`; pass its `BLOCKED:` / `NOTE:` / `WARN:`
  lines through verbatim rather than summarising them.
- On Antigravity, `ask_user` does not exist — ask in the conversation and wait
  for a real reply before any confirmation step below.

## Safety rules

- **`close` is read-only.** It creates, edits, and deletes nothing, changes no
  git state, and sends nothing to a remote. It prints remediation commands; the
  user decides whether to run them. It never calls `/exit` on the user's
  behalf — it prints the suggestion and stops.
- **`handoff` writes exactly two artifacts**: one issue comment and one memory
  file. No commits, no pushes, no code edits, no issue state changes. Only
  merged PRs and tests that ran green in this session may be listed as done;
  everything else is labeled unverified. The resume sentence must map to the
  real tracking issue and its actual next step — never invent one.
- **`worktree-teardown` is the destructive skill here.** Run it from the main
  repo, never from inside the worktree being removed. Its pre-flight blocks on
  uncommitted changes or unpushed commits: report and stop. `--force` is the
  user's explicit override, not yours, and on Antigravity you must get that
  answer in the conversation. Sync main before deleting the branch so
  `git branch -d` can verify merge status.
- **`worktree-spawn` refuses to run from inside a worktree.** In a `git-crypt`
  repo it stages with explicit `git add <path>` — never `-A` or `.` — because
  auto-unlocked files can show as modified from a raw-byte versus textconv
  mismatch.
- **`restart` is user-triggered recovery, never a building block.** No other
  skill may invoke it. It never re-runs a process skill whose output is already
  in the conversation, and it never batches tool calls — the premise is that
  the last batch died mid-way.
