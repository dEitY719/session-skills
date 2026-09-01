# session-skills

Eight skills for the boundaries of a coding session — resume a turn that died,
audit or hand off a session that is ending, carry an unattended run across a
token-limit reset, defer a command by N minutes, and create or remove the
isolated git worktree the work happens in. Packaged as a single plugin named
`session`, installable on six coding-agent harnesses.

They are grouped by *when* they fire rather than by what they touch. That is the
whole organising idea: `restart` and `handoff` have nothing in common
technically, but you reach for one or the other at the same moment — the session
is in trouble and you have to decide whether to resume or write it down.

Unlike its sibling [`harness-skills`](https://github.com/dEitY719/harness-skills),
this repo owns no shared assets — it links out for the
[per-harness tool mappings and the CI workflow](#shared-assets).

## Skills

| Skill | Invoke | What it does |
|-------|--------|--------------|
| `restart` | `/session:restart` | Resumes a turn that died to an API error, an OOM, an auth expiry, or an ESC — same session, no cron. Picks the resume target off the TodoList, corroborates it against `git status`, then works in single-tool-call chunks with big reads delegated to subagents. |
| `close` | `/session:close [--repos <path,...>]` | Audits four categories of leftover work across every repo the session touched and prints `[OK]` or `[BLOCKED]` plus one `Next:` line. **Strictly read-only** — it never changes a file, a git state, or a remote, and never runs `/exit` for you. |
| `handoff` | `/session:handoff [issue] [remote] [--memory-only] [--new-issue]` | Writes *unfinished* work into a tracking-issue comment and an agent-local memory file, then prints a copy-paste resume sentence. Exactly two writes; nothing is committed or pushed. |
| `rate-limit-guard` | `/session:rate-limit-guard --reset HH:MM [--max-cycles N] [--cycle-window M] <command>` | **[Claude Code only]** Arms a durable one-shot cron for `reset + 5min`, persists `.claude/.rate-limit-guard.json`, runs the wrapped command, and tears the safety net down on success. |
| `resume-after-limit` | `/session:resume-after-limit [<command>]` | **[Claude Code only]** What that cron invokes. Reads the state file, stops hard on a worktree mismatch, pre-arms the next cycle, re-runs the wrapped command, cleans up on success. |
| `schedule` | `/session:schedule [--time M] "<command>"` | **[Claude Code only]** Generic session-local deferral: run any slash command or task in M minutes (default 5). One-shot; the built-in `/schedule` is for recurring cloud routines. |
| `worktree-spawn` | `/session:worktree-spawn [--ai <name>] [--task <slug>] [--base <ref>] [<branch>]` | Creates `../<project>-<agent>-<N>` on a `wt/<agent>/<N>` branch so parallel agents do not collide. Detects the agent, picks the next free index, resolves the base ref, and handles `git-crypt` repos. |
| `worktree-teardown` | `/session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]` | Removes the worktree, syncs main, deletes the branch. **The destructive one** — blocks on uncommitted or unpushed work unless you pass `--force`. |

### Visual guides and worked examples (GitHub Pages)

- `restart` — [visual guide](https://deity719.github.io/session-skills/skill-guides/restart.html) · [usage example](https://deity719.github.io/session-skills/skill-output/restart-usage.html) (dead turn to resumed work in the same session)
- `close` — [visual guide](https://deity719.github.io/session-skills/skill-guides/close.html) · [usage example](https://deity719.github.io/session-skills/skill-output/close-usage.html) (session state to an OK/BLOCKED verdict)
- `handoff` — [visual guide](https://deity719.github.io/session-skills/skill-guides/handoff.html) · [usage example](https://deity719.github.io/session-skills/skill-output/handoff-usage.html) (unfinished work to an issue comment and a resume sentence)
- `rate-limit-guard` — [visual guide](https://deity719.github.io/session-skills/skill-guides/rate-limit-guard.html) · [usage example](https://deity719.github.io/session-skills/skill-output/rate-limit-guard-usage.html) (a reset time to a durable cron and a state file)
- `resume-after-limit` — [visual guide](https://deity719.github.io/session-skills/skill-guides/resume-after-limit.html) · [usage example](https://deity719.github.io/session-skills/skill-output/resume-after-limit-usage.html) (that state file to the re-run command)
- `schedule` — [visual guide](https://deity719.github.io/session-skills/skill-guides/schedule.html) · [usage example](https://deity719.github.io/session-skills/skill-output/schedule-usage.html) (a command plus a delay to a one-shot cron)
- `worktree-spawn` — [visual guide](https://deity719.github.io/session-skills/skill-guides/worktree-spawn.html) · [usage example](https://deity719.github.io/session-skills/skill-output/worktree-spawn-usage.html) (a main repo to an isolated worktree and branch)
- `worktree-teardown` — [visual guide](https://deity719.github.io/session-skills/skill-guides/worktree-teardown.html) · [usage example](https://deity719.github.io/session-skills/skill-output/worktree-teardown-usage.html) (a worktree path to a removed worktree and a synced main)

Each page is generated from a Markdown source under
[`docs/skill-guides/`](docs/skill-guides) and [`docs/skill-output/`](docs/skill-output).

### Two pairs worth knowing

`rate-limit-guard` and `resume-after-limit` are one mechanism split across two
fires. The guard computes `reset + 5min`, arms the cron, and writes the state
file; the resumer is what that cron calls — it verifies it woke up in the right
worktree and re-runs the wrapped command, pre-arming the next cycle first when
`--max-cycles > 1`. Neither is useful alone, which is why they ship together.

`close` and `handoff` sit at the same moment and answer different questions.
Close means the session finished cleanly: audit, verdict, no writes. Handoff
means the session is running out of context with work unfinished: write that
work into a tracking issue so the next session starts from one sentence instead
of an archaeology exercise. When `close` returns `[BLOCKED]` on unfinished work,
its `Next:` line points at `handoff`.

## Requirements

| Skill | Needs |
|-------|-------|
| `restart` | Claude Code's `TaskList` / `TaskUpdate` (the session TodoList) and a subagent dispatch tool. Degrades elsewhere — see [Harness support](#harness-support). |
| `close` | `bash` for its two `lib/` scripts; `git` in each audited repo; optionally `gh` for the C-4 issue/PR status check and `TaskList` for C-2. |
| `handoff` | `gh`, authenticated against the tracking issue's repo; a writable agent-memory location. `TaskList` is used when present. |
| `rate-limit-guard` | Claude Code's `CronCreate` / `CronDelete`, `python3`, and a session left open (or reopened) in the same worktree so the durable cron can fire. Run `/usage` first to learn your reset time. |
| `resume-after-limit` | The same, plus `.claude/.rate-limit-guard.json` written by the guard — or an explicit `<command>` argument. |
| `schedule` | Claude Code's `CronCreate` and `python3`. |
| `worktree-spawn` | `git`, a writable parent directory, and the main repo as the working directory. Optional: a `git-crypt` key at `~/.config/git-crypt/<repo>.key` for auto-unlock. |
| `worktree-teardown` | `git`, run from the main repo with the worktree path as an argument. |

## Install

### Claude Code

```
/plugin marketplace add dEitY719/session-skills
/plugin install session@session-skills
```

### Codex

```
codex plugin install dEitY719/session-skills
```

### Kimi CLI

```
kimi plugin install dEitY719/session-skills
```

### Hermes Agent

```
hermes plugins install dEitY719/session-skills
```

### OpenCode

See [`.opencode/INSTALL.md`](.opencode/INSTALL.md).

### Gemini CLI / Antigravity

```
gemini extensions install https://github.com/dEitY719/session-skills
```

Antigravity (`agy`) shares `~/.gemini`, so it inherits the install.

## Harness support

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
`Skill(gh:issue-create)` to open a tracking issue — read that skill's `SKILL.md`
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

## Shared assets

This repo owns none — deliberately.

- **Per-harness tool mappings** live in
  [`harness-skills/references/`](https://github.com/dEitY719/harness-skills/tree/main/references)
  (`{codex,kimi,gemini,antigravity,hermes,opencode}-tools.md`). That repo is
  their sole owner; the other fourteen `*-skills` repos link there rather than
  carrying copies, so one tool rename is one edit, not fifteen
  (dotfiles #1410 F-5 / NF-2). The only condensed mirror here is
  `.kimi-plugin/plugin.json`'s `skillInstructions`, because Kimi CLI cannot read
  a reference file at load time — it points back to the canonical file.
- **The reusable CI workflow** is
  [`harness-skills/.github/workflows/skill-check.yml`](https://github.com/dEitY719/harness-skills/blob/main/.github/workflows/skill-check.yml)
  (#1410 D-10). See [CI](#ci).

## Layout

Manifests live at the repo root and all point at one flat `skills/` directory:

```
.
├── skills/{restart,close,handoff,rate-limit-guard,
│           resume-after-limit,schedule,
│           worktree-spawn,worktree-teardown}/
│   ├── SKILL.md
│   ├── references/
│   ├── lib/                                    (close only)
│   └── evals/                                  (restart only)
├── .claude-plugin/{marketplace,plugin}.json    Claude Code
├── .codex-plugin/plugin.json                   Codex
├── .kimi-plugin/plugin.json                    Kimi CLI
├── .hermes-plugin/{plugin.yaml,__init__.py}    Hermes Agent
├── .opencode/plugins/session.js + INSTALL.md   OpenCode
├── .agents/plugins/marketplace.json            Antigravity
├── gemini-extension.json + GEMINI.md           Gemini CLI
├── package.json
├── CLAUDE.md · AGENTS.md -> CLAUDE.md
└── LICENSE
```

Only Claude Code understands a nested `plugins/<name>/skills/` layout. The other
five harnesses resolve manifests at the repo root and a skills tree at
`./skills/`, so this repo keeps everything flat. See [`CLAUDE.md`](CLAUDE.md) for
the full rationale and contribution rules.

Skill directory names dropped their old prefixes. In dotfiles these were
`devx-restart`, `devx-session-close`, `ai-worktree-spawn` and so on; here the
plugin name already carries that meaning, so `/session:devx-restart` would
stutter where `/session:restart` reads cleanly (#1410 F-4). Contrast
`pkm-skills`, which *keeps* `obsidian-` and `karakeep-` because those name two
different external services inside one plugin.

The `.kimi-plugin/` manifest is pre-provisioned: Kimi CLI is not installed on the
maintainer's machines yet, and shipping the manifest now costs nothing and saves
a migration later.

## CI

[`.github/workflows/validate.yml`](.github/workflows/validate.yml) calls the
reusable workflow owned by `harness-skills`:

```yaml
jobs:
  validate:
    uses: dEitY719/harness-skills/.github/workflows/skill-check.yml@main
    with:
      plugin-name: session
```

It validates manifests, skill frontmatter (the `name:` must be bare and match
the directory), progressive-disclosure line limits, the Codex description
budget, version agreement across all seven manifests, shell scripts, and the
no-emoji rule. There is no local copy to keep in sync; a check added upstream
applies here on the next run.

## Provenance

These skills were extracted from
[`dEitY719/dotfiles`](https://github.com/dEitY719/dotfiles)
(`claude/skills/{devx-restart,devx-session-close,devx-session-handoff,devx-rate-limit-guard,devx-resume-after-limit,devx-schedule,ai-worktree-spawn,ai-worktree-teardown}`)
as a content snapshot at source commit `b5f7fd1347e56c9a70e9b67ba15e7c5b7f1cf9ac`
— no history rewriting. The dotfiles copies remain in place; they are removed in
Phase 4 of that repo's migration. Behaviour is unchanged from the snapshot; only
the namespace moved, from `devx:` and `ai-worktree:` to `session:`.

This is Phase 2 of the dotfiles #1410 migration. `packaging-skills` was Phase 0,
and `harness-skills` (Phase 1) is the sibling that owns the shared assets this
repo links to.

## License

MIT. See [LICENSE](LICENSE).
