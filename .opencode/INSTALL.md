# Installing session for OpenCode

## Prerequisites

- [OpenCode.ai](https://opencode.ai) installed
- `git` (every skill here uses it; the two worktree skills are little else)
- `gh`, authenticated, for `handoff` and for `close`'s optional issue/PR check
- Nothing for `rate-limit-guard`, `resume-after-limit`, or `schedule` — they
  cannot run on OpenCode at all. See [Capability gaps](#capability-gaps).

## Installation

Add the plugin to the `plugin` array in your `opencode.json` (global or
project-level):

```json
{
  "plugin": ["session-skills@git+https://github.com/dEitY719/session-skills.git"]
}
```

Restart OpenCode. The plugin installs through OpenCode's plugin manager and
registers all eight skills.

OpenCode uses its own plugin install. If you also use Claude Code, Codex, or
another harness, install this plugin separately for each one.

## Usage

Use OpenCode's native `skill` tool:

```
use skill tool to list skills
use skill tool to load worktree-spawn
```

## Tool mapping

The authoritative OpenCode tool mapping for every `dEitY719/*-skills` repo lives
in the sibling repo `harness-skills`, at
[`references/opencode-tools.md`](https://github.com/dEitY719/harness-skills/blob/main/references/opencode-tools.md).
This repo owns no copy — one tool rename must stay one edit. Read it when a
skill names a tool you do not recognise. Short version:

- "Read a file" -> `read`
- "Create a file" / "edit a file" -> `apply_patch`
- "Run a shell command" -> `bash`
- "Search file contents" / "find files by name" -> `grep`, `glob`
- "Create a todo" -> `todowrite`
- "Dispatch a subagent" -> `task` with `subagent_type: "general"` (or
  `"explore"` for read-only exploration)
- "Invoke a skill" -> OpenCode's native `skill` tool

## Capability gaps

Three gaps matter here, and one of them is disqualifying:

- **No cron — three skills cannot run.** `rate-limit-guard`,
  `resume-after-limit`, and `schedule` declare Claude Code's `CronCreate` /
  `CronDelete`, which start a fresh agent turn at a wall-clock time. OpenCode
  has no equivalent. Say the skill is unavailable and stop. A `sleep`, a
  backgrounded `bash` call, an `at` job, or "I will do it in ten minutes" are
  not substitutes — none of them can wake an agent, so all of them look like
  they worked and quietly do nothing.
- **No readable TodoList.** `todowrite` writes a list; it does not replay one.
  Claude Code's `TaskList` / `TaskUpdate` have no OpenCode equivalent, so
  `restart` picks its resume target from the last completed tool result in the
  conversation (then corroborates it with `git status --short`), `close`
  reports its C-2 check as "TodoList unavailable on this harness" instead of
  passing silently, and `handoff` pulls remaining work from the conversation.
- **No `Skill()` invocation.** `handoff` may hand off to `gh:issue-create` to
  open a tracking issue. Load that skill with OpenCode's `skill` tool if the
  `gh-*` plugin is installed, or just run `gh issue create`. The contract is an
  issue number.

The `lib/*.sh` helpers under `skills/close/` are plain bash. Run them with
`bash` and pass their `BLOCKED:` / `NOTE:` / `WARN:` lines through verbatim —
do not reimplement them. The two worktree skills are pure `git` CLI and behave
identically here and on Claude Code.

## Safety contracts

- `close` is read-only: nothing created, edited, or deleted, no git state
  changed, nothing sent to a remote. It prints remediation commands and lets
  the user decide, and it never runs `/exit` on their behalf.
- `handoff` writes exactly two artifacts — one issue comment, one memory file.
  No commits, no pushes, no code edits, no issue state changes. Unverified work
  is never listed as done.
- `worktree-teardown` removes a worktree and deletes a branch. Run it from the
  main repo, never from inside the target worktree. It blocks on uncommitted
  changes or unpushed commits; `--force` is the user's explicit override.
  OpenCode has no structured question tool — ask in the conversation and wait
  for a real answer before forcing anything.
- `worktree-spawn` refuses to run from inside an existing worktree, and stages
  with explicit `git add <path>` in `git-crypt` repos.
- `restart` is user-triggered recovery. No other skill may invoke it, it never
  re-runs a process skill whose output is already in context, and it never
  batches tool calls.

## Troubleshooting

### Plugin not loading

1. Check logs: `opencode run --print-logs "hello" 2>&1 | grep -i session`
2. Verify the plugin line in your `opencode.json`
3. Make sure you are running a recent version of OpenCode

### Skills not found

1. Use the `skill` tool to list what was discovered
2. Check that the plugin is loading (see above)

### A scheduling skill "succeeded" but nothing ever ran

It did not succeed. `rate-limit-guard`, `resume-after-limit`, and `schedule`
cannot work on OpenCode; if one of them reported a scheduled job, the agent
improvised a substitute it should have refused. Re-read
[Capability gaps](#capability-gaps).

## Getting Help

Report issues: https://github.com/dEitY719/session-skills/issues
