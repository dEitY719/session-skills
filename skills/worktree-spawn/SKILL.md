---
name: worktree-spawn
description: >-
  Create an isolated git worktree so this AI agent works in parallel without
  colliding with other agents in the repo. Use for /session:worktree-spawn,
  "새로운 작업 시작", "격리된 작업 공간 만들어줘", "spawn a worktree", "start isolated work".
  Cleanup is session:worktree-teardown.
license: MIT
allowed-tools: Bash, Read, Grep, Glob, EnterWorktree
metadata:
  model_recommendation:
    tier: haiku
    reason: "structured git-worktree CLI orchestration; deterministic bash sequence, low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# session:worktree-spawn — Isolated Git Worktree

## Help

If args is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

Create an isolated git worktree so this AI agent can work without interfering
with other agents running in the same repository.

Read `references/options-and-errors.md` for CLI options and error handling.

## Step 1: Decide the branch name (model judgment)

| Input | Branch name |
|---|---|
| No arguments | `wt/{agent}/{N}` |
| `--task "slug"` | `wt/{agent}/{N}-{slug}` |
| Explicit branch name | Use as-is |

`{agent}` is auto-detected and `{N}` is `max(existing index) + 1`; the script
does both. Read `references/agent-detection.md` only when overriding with
`--ai`. A Korean `--task` must be translated to an English slug first
(lowercase, hyphens, max 30 chars) — "로그인 기능" becomes
`--task "login feature"`. The script normalizes but cannot translate.

## Step 2: Create the worktree

```
bash "${SKILL_DIR}/lib/spawn.sh" [--ai <name>] [--task <slug>] [--base <ref>] [--dry-run] [<branch>]
```

The script validates preconditions (git repo, not already inside a worktree,
writable parent), detects the agent, takes the spawn lock, computes the index,
resolves the base ref (`--base` > `origin/main` > `main`/`master` > `HEAD`),
creates the worktree with git-crypt auto-unlock or bypass, appends the audit
log, and prints the report. Stop and surface stderr on any non-zero exit.
`references/bash-commands.md` is its full contract: arguments, exit codes,
output lines, and what stays model judgment.

**Claude Code only:** `EnterWorktree` creates and enters the worktree natively;
this skill still owns the index scan, the git-crypt unlock and the audit log.
Read `references/native-tools.md` and follow it in place of this step. Every
other harness (Codex, Gemini, Kimi, opencode) has no such tool and uses the
script above.

## Step 3: Report and move

The script prints:

```
[OK] Worktree ready
  Path:   ../my-app-claude-1
  Branch: wt/claude/1
  Base:   origin/main
  git-crypt: unlocked via ~/.config/git-crypt/my-app.key
  Teardown: git push -u origin wt/claude/1 && git worktree remove ../my-app-claude-1 && git branch -d wt/claude/1
  cd ../my-app-claude-1
```

The `git-crypt` line only appears when the repo uses git-crypt;
`references/bash-commands.md` lists its three exact forms.

In an auto-unlocked worktree use explicit `git add <path>`, never `-A` or `.`:
git-crypt files can show as `M` from a raw-byte vs. textconv mismatch.

The script cannot change the caller's cwd. Relay the `cd` command it prints as
guidance, then execute it yourself as the AI agent.
