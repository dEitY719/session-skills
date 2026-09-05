# session-skills — Contributor Guidelines

This file is the AI context document for this repo. `AGENTS.md` is a symlink to
it, so Claude Code, Codex, Gemini CLI, and every other harness read the same
text. Edit `CLAUDE.md`; never replace the symlink with a second copy.

## What this repo is

A single-plugin skill marketplace. The plugin is named `session` and it bundles
eight skills grouped by **when they fire** rather than by what they touch — the
moments a session stalls, ends, or needs a workspace of its own:

| Skill | Fires when | Role |
|-------|-----------|------|
| `restart` | A turn died and the session is still alive | Picks the resume target off the TodoList, corroborates it against `git status`, and resumes in single-tool-call chunks with big reads pushed to subagents. |
| `close` | The user wants to stop | Read-only audit of four categories of leftover work; prints `[OK]` or `[BLOCKED]` and one `Next:` line. Changes nothing. |
| `handoff` | Context is nearly full, work is unfinished | Resolves the tracking issue, posts a structured handoff comment, writes an agent-local memory file, prints a copy-paste resume sentence. |
| `rate-limit-guard` | Before a long unattended run | Arms a durable one-shot cron at the token-limit reset time and persists `.claude/.rate-limit-guard.json`. |
| `resume-after-limit` | The reset arrives | What that cron invokes: reads the state file, verifies the worktree, pre-arms the next cycle, re-runs the wrapped command. |
| `schedule` | Something should happen in N minutes | Generic session-local one-shot deferral of any slash command or task. |
| `worktree-spawn` | Parallel work starts | Creates `../<project>-<agent>-<N>` on `wt/<agent>/<N>`, handling agent detection, index collision, base-ref resolution, and `git-crypt`. |
| `worktree-teardown` | Parallel work ends | Removes the worktree, syncs main, deletes the branch. The destructive one. |

Two of these are pairs, and the pairing is load-bearing:

- **`rate-limit-guard` + `resume-after-limit`** are one mechanism split across
  two fires. The guard writes the state file and the cron; the resumer is the
  cron's callee. They reference each other by name and live in the same repo
  precisely so that relationship cannot rot. If you rename one, fix the other
  in the same commit — including the inlined cron-prompt template that exists
  in both `rate-limit-guard/references/cron-prompt-template.md` and
  `resume-after-limit/references/preemptive-rearm.md` and must stay in sync.
- **`close` vs `handoff`** answer different questions at the same moment. Close
  means the session finished cleanly: audit, verdict, no writes. Handoff means
  the session is running out of context with work unfinished: write that work
  into a tracking issue. Do not let either grow into the other — a `close` that
  starts writing, or a `handoff` that starts auditing, is a bug.

The skills were extracted from `dEitY719/dotfiles`
(`claude/skills/{devx-restart,devx-session-close,devx-session-handoff,devx-rate-limit-guard,devx-resume-after-limit,devx-schedule,ai-worktree-spawn,ai-worktree-teardown}`)
as a content snapshot at source commit
`b5f7fd1347e56c9a70e9b67ba15e7c5b7f1cf9ac` — no history rewriting. The dotfiles
copies remain in place; they are removed in Phase 4 of that repo's migration
plan. This is Phase 2 of dotfiles #1410; `packaging-skills` was Phase 0 and
`harness-skills` (Phase 1) owns the shared assets this repo links to. Behaviour
is unchanged from the snapshot; only the namespace moved, from `devx:` and
`ai-worktree:` to `session:`.

## Layout: root manifests, one flat `skills/`

This repo deliberately does **not** use the nested `plugins/<name>/skills/`
"mono" layout. Every harness manifest sits at the repo root and points at a
single flat `./skills/` directory:

```
.claude-plugin/{marketplace,plugin}.json   Claude Code
.codex-plugin/plugin.json                  Codex
.kimi-plugin/plugin.json                   Kimi CLI
.hermes-plugin/{plugin.yaml,__init__.py}   Hermes Agent
.opencode/plugins/session.js               OpenCode
.agents/plugins/marketplace.json           Antigravity
gemini-extension.json + GEMINI.md          Gemini CLI
skills/<name>/SKILL.md                     the skills themselves
```

Only Claude Code understands the nested mono layout. The other five harnesses
resolve manifests at the repo root and a skills tree at `./skills/`, so nesting
would silently cut this plugin down to Claude-Code-only. **Do not move the
manifests under a `plugins/` directory.**

## Shared assets live elsewhere — link, never copy

This repo owns none. Both belong to `dEitY719/harness-skills`:

**1. Per-harness tool mappings** (`references/*-tools.md` there, dotfiles #1410
F-5). Do not create a `references/` directory at this repo's root. If a doc here
needs a mapping, link to
`https://github.com/dEitY719/harness-skills/blob/main/references/<harness>-tools.md`.
One tool rename must stay one edit, not fifteen (NF-2). The single sanctioned
mirror is the condensed summary inside `.kimi-plugin/plugin.json`'s
`skillInstructions`, because Kimi CLI cannot read a reference file at load time;
keep it short and keep it pointing upstream.

**2. The reusable CI workflow** (`.github/workflows/skill-check.yml` there,
D-10). This repo's `validate.yml` calls it with `plugin-name: session` and
nothing else. Do not fork it into a standalone workflow — a check added upstream
should apply here on the next run, which is the whole point.

## Rules for changing skills

- **Skill directory name is the identity.** `skills/<name>/` must match the
  `name:` field in that skill's `SKILL.md` frontmatter, and that field is the
  **bare** name (`worktree-spawn`), never namespaced (`session:worktree-spawn`).
  CI fails on a `:` in the name. The harness supplies the `session:` prefix at
  invocation time.
- **Prefixes were dropped here.** Unlike `pkm-skills`, which keeps `obsidian-`
  and `karakeep-` because they name two different external services, the old
  `devx-` and `ai-worktree-` prefixes were redundant with the plugin name
  (dEitY719/dotfiles#1410 F-4 / §4). `/session:devx-restart` stutters;
  `/session:restart` does not. The forms are `/session:close`,
  `/session:handoff`, `/session:worktree-spawn`, and so on. Do not reintroduce
  a prefix.
- **Invocation form in prose is namespaced.** Body text referring to a skill as
  a command writes `/session:restart`. The old dash-form aliases
  (`/devx-restart`, `/ai-worktree-spawn`) were dropped in the migration — do not
  reintroduce them, in descriptions or anywhere else.
- **Cross-repo references use the owning repo's current namespace.**
  `gh-issue:create`, `gh-issue:read`, `gh-flow:issue`, `gh-pr:reply`,
  `notes:task-history`, `pkm:obsidian-session-clip` and the `superpowers:*`
  process skills live in other repos of this family. Never rewrite them to
  `session:` — only siblings inside `skills/` take that prefix — and never
  freeze them either: when a sibling repo renames a skill, sweep every hit here
  in the same commit, checking the new name against that repo's
  `.claude-plugin/plugin.json` `name` and its `skills/<dir>/`.
- **The on-disk worktree log keeps its old filename.** `worktree-spawn` and
  `worktree-teardown` append to `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`
  and `worktree-spawn` locks on `ai-worktree-spawn.lock`. Those are runtime data
  paths, not command names: renaming them would orphan every existing log and
  split the lock during the Phase 2-to-4 window when a repo may still have the
  dotfiles copy installed alongside this one. Leave them.
- **Progressive disclosure.** `SKILL.md` stays at 100 lines or fewer (CI fails
  above 100, so exactly 100 passes) and names which `references/` file to read
  and when. Detail lives in `references/`; executable steps live in `lib/`. Do
  not inline either back into `SKILL.md` — most of these are within a dozen
  lines of the limit, and `restart` was over it before the migration split
  Step 1 out into `references/resume-target.md`.
- **Description budget.** CI sums every skill description and fails past 5,440
  characters — Codex's context budget — and rejects any single description over
  1,024. The eight here total roughly 1,850, so there is room; spend it on
  trigger phrases, not prose.
- **`lib/*.sh` is the contract, not a suggestion.** `check-repos.sh`,
  `check-artifacts.sh`, and `_repo_common.sh` hold the deterministic half of
  `session:close`. Call them and surface their `BLOCKED:` / `NOTE:` / `WARN:`
  lines verbatim. Never reimplement their logic in prose, and never swallow a
  warning to keep an exit code clean. CI shellchecks them at
  `--severity=warning`.

## Safety contracts

These are acceptance criteria carried over from dotfiles, not advice:

- **`session:close` is strictly read-only.** It creates, edits, and deletes
  nothing, changes no git state, and sends nothing to a remote — its only
  network call is the optional `gh issue view` / `gh pr view` in C-4, and a
  failure there degrades to one `[WARN]` line rather than flipping the verdict.
  It prints remediation commands; the user decides whether to run them. It never
  calls `/exit` on the user's behalf: there is no path from a skill to that
  built-in, and force-killing the process would skip transcript cleanup. Print
  the suggestion and stop.
- **`session:handoff` writes exactly two artifacts**: one issue comment
  (skippable with `--memory-only`) and one memory file. No commits, no pushes,
  no code edits, no issue state changes. Only merged PRs and tests that ran
  green in this session may be listed as done; everything else is labeled
  unverified. The resume sentence must map to the real tracking issue and its
  actual next step — a fabricated one is worse than none, because the next
  session will act on it.
- **`session:worktree-teardown` is the destructive skill here.** It must run
  from the main repo, never from inside the worktree being removed. Its
  pre-flight blocks on uncommitted changes or unpushed commits: report and stop.
  `--force` is the user's explicit override, never the agent's shortcut past a
  block. Sync main *before* deleting the branch so `git branch -d` can verify
  merge status.
- **`session:worktree-spawn` refuses to run from inside a worktree**, and in a
  `git-crypt` repo it stages with explicit `git add <path>` — never `-A` or
  `.` — because auto-unlocked files can show as modified from a raw-byte versus
  textconv mismatch. When no key file resolves it falls back to the bypass path
  (filters disabled, encrypted files stay binary) rather than guessing.
- **`session:restart` is user-triggered recovery, never a building block.** No
  other skill may invoke it. It never re-runs a process skill whose output is
  already in the conversation, never batches tool calls (the premise is that the
  last batch died mid-way), and never rewrites a TodoList task subject — status
  only.
- **`session:rate-limit-guard` never schedules without an explicit
  `--reset HH:MM`**, never uses `recurring: true` or `durable: false`, and never
  cleans up on a transient error — that is exactly when the safety net should
  survive. `session:resume-after-limit` stops hard on a worktree mismatch: wrong
  directory means wrong work.

## Harness gaps are documented, not worked around silently

Three of these eight skills cannot run outside Claude Code, and pretending
otherwise is the failure mode to guard against:

- **`rate-limit-guard`, `resume-after-limit`, and `schedule` need `CronCreate` /
  `CronDelete`** — tools that start a fresh agent turn at a wall-clock time. No
  other harness has an equivalent. The correct behaviour elsewhere is to say the
  skill is unavailable and stop. A `sleep`, a backgrounded shell command, an
  `at` job, or a promise to act later are **not** substitutes: none of them can
  wake an agent, so each one reports success and silently does nothing. That is
  strictly worse than refusing.
- **`restart` needs `TaskList` / `TaskUpdate`** to read and update the session
  TodoList. Most harnesses expose a write-only todo tool, so `restart` degrades
  rather than failing: pick the resume target from the last completed tool
  result in the conversation, corroborate with `git status --short`, and keep
  the chunking and delegation rules unchanged. `close` (C-2) and `handoff`
  degrade the same way and must say so in their output rather than skipping the
  check silently.
- **`close`, `handoff`, `worktree-spawn`, and `worktree-teardown` are otherwise
  shell, `git`, `gh`, and file writes** — they port cleanly.

When you add a step that depends on a Claude-Code-only capability, say so in
`README.md`'s harness-support matrix, in `GEMINI.md` and `.opencode/INSTALL.md`,
and open an issue against `harness-skills` so its `references/*-tools.md` gain
the fallback.

## Version bumps

The version appears in seven manifests: `.claude-plugin/marketplace.json`,
`.claude-plugin/plugin.json`, `.codex-plugin/plugin.json`,
`.kimi-plugin/plugin.json`, `.hermes-plugin/plugin.yaml`,
`gemini-extension.json`, and `package.json`. CI checks that they agree — bump
all of them together. Versioning is independent per repo
(dEitY719/dotfiles#1410 D-9); this repo does not move in lockstep with its
siblings.

## No emojis

Anywhere in this repo. Token efficiency, and CI rejects them.
