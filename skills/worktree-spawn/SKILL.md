---
name: worktree-spawn
description: >-
  Create an isolated git worktree so this AI agent works in parallel without
  colliding with other agents in the repo. Use for /session:worktree-spawn,
  "새로운 작업 시작", "격리된 작업 공간 만들어줘", "spawn a worktree", "start isolated work".
  Cleanup is session:worktree-teardown.
allowed-tools: Bash, Read, Grep, Glob
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

## Execution Steps

Run these steps in order. Stop immediately on any error.
Read `references/bash-commands.md` for exact bash implementations per step.

### Step 1: Validate Preconditions

Verify: git repo, NOT inside a worktree (block if so), warn on dirty state,
check parent directory write permission.

### Step 2: Detect AI Agent

Read `references/agent-detection.md` for the full priority chain and env var table.
Priority: `--ai` arg > `$AI_AGENT_NAME` > agent-specific env vars > `agent`.

### Step 3: Compute Project Name and Index

Extract project name via `basename "$(git rev-parse --show-toplevel)"`.
Scan parent directory for `{project}-{agent}-N` pattern, assign max(N)+1.

### Step 4: Determine Branch Name

| Input | Branch Name |
|---|---|
| No arguments | `wt/{agent}/{N}` |
| `--task "slug"` | `wt/{agent}/{N}-{slug}` |
| Explicit branch name | Use as-is |

If `--task` is given in Korean, translate to English slug first (lowercase,
hyphens, max 30 chars). Example: "로그인 기능" -> `login-feature`.

### Step 5: Determine Base Ref

Priority: `--base` arg > `origin/main` > `main`/`master` > current HEAD.

### Step 6: Create Worktree

git-crypt detection happens in Step 1.5. The full key-resolution priority and
unlock sequence live in `references/bash-commands.md` (Step 1.5 / Step 6). Two paths:

- **Key found (auto-unlock)**: decrypt `.env` / `.secrets/` normally. Caveat:
  use explicit `git add <path>`, never `-A` / `.`, in auto-unlocked worktrees
  (git-crypt files may show as `M` from a raw-byte vs. textconv mismatch).
- **Key not found (bypass, backward-compatible)**: filters disabled, encrypted
  files stay binary; print the `gc-export-key` hint for the next spawn.

Branch exists: `git worktree add <path> <branch>`. New branch:
`git worktree add -b <branch> <path> <base_ref>`.

### Step 7: Log the Creation

Append structured log to `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`.

### Step 8: Report and Move

Print result, then `cd` into the new worktree:

```
[OK] Worktree ready
  Path:   ../my-app-claude-1
  Branch: wt/claude/1
  Base:   origin/main
  git-crypt: unlocked via ~/.config/git-crypt/my-app.key
  Teardown: git push -u origin <branch> && git worktree remove <path> && git branch -d <branch>
```

The `git-crypt` line only appears when the repo uses git-crypt — `unlocked via
<key path>` (auto-unlock) or `disabled (no key file)` (bypass, also prints the
`git-crypt export-key` hint).

The script cannot change the caller's cwd. Print the `cd` command as guidance,
then execute it yourself as the AI agent.
