---
name: worktree-teardown
description: >-
  Remove an AI worktree, delete its branch, and sync main — the reverse of
  session:worktree-spawn. Run from the MAIN repo with the worktree path as
  an argument. Use for /session:worktree-teardown, "작업 끝", "워크트리 정리", "워크트리
  제거", "cleanup worktree".
allowed-tools: Bash, Read, Grep, Glob
metadata:
  model_recommendation:
    tier: haiku
    reason: "structured CLI wrapper — git worktree cleanup; low reasoning"
    claude: prefer
    non_claude: advisory-only
---

# session:worktree-teardown — Worktree Cleanup

## Help

If arg #1 is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

Remove an AI worktree and sync main after work is complete — the reverse of
`session:worktree-spawn`. **Must run from the main repo**, not inside the worktree.
The worktree path is an argument (e.g., `/session:worktree-teardown ~/dotfiles-claude-2`).

Read `references/options-and-errors.md` for CLI options and error handling.

## Execution Steps

Run these steps in order. Stop immediately on any error.
Read `references/bash-commands.md` for exact bash implementations per step.

### Step 0: Dry-run Gate

If `--dry-run`, print the plan (resolved worktree path, branch, intended
actions) and stop. No destructive action.

### Step 1: Validate — Must Be in Main Repo, NOT a Worktree

Check `git-dir == git-common-dir`. If INSIDE a worktree, print error and stop
(same check as spawn — both run from the main repo).

Require a `<worktree-path>` argument. If missing, list existing worktrees and stop.

### Step 2: Resolve Worktree Info

From `<worktree-path>`, resolve `WORKTREE_PATH` (absolute), `BRANCH` (checked
out there, via `git worktree list`), and `WORKTREE_NAME` (basename). Verify it
is a known worktree; if not, print error and stop.

### Step 3: Pre-flight Checks

Use `git -C <worktree-path>` to check for uncommitted changes or unpushed
commits. Block to prevent work loss. Skip these checks if `--force` is given.

### Step 4: Remove Worktree

`git worktree remove <path>`. On failure, try `--force` if user opted in.

### Step 5: Sync Main

`git checkout main && git pull origin main`.
Must run BEFORE branch delete so `git branch -d` can verify merge status.
If pull conflicts, the AI agent attempts to resolve them and reports.

### Step 6: Delete Branch

`git branch -d <branch>` (safe delete — verifies merge status).
Skip if `--keep-branch` is given. Warn if branch is not fully merged.

### Step 7: Log

Append `TEARDOWN` entry to `ai-worktree-spawn.log` (same file as spawn).

### Step 8: Report

```
[OK] Teardown complete
  Removed:  ../my-app-gemini-1
  Branch:   wt/gemini/1 (deleted)
  Now on:   main (up to date with origin/main)

  Note: if your outer shell was cd'd inside the removed worktree, run
  `cd <main-repo>` there now to avoid `getcwd: cannot access parent
  directories` errors from zsh/pyenv/p10k.
```

On failure, emit a structured failure verdict instead:

```
[FAIL] <reason>
  Step:    <step name where failure occurred>
  Detail:  <error message or exit code>
```

Always include the `Note:` block on `[OK]` — the outer shell's cwd is
undetectable, so the hint is unconditional. Substitute `<main-repo>` with
`git rev-parse --show-toplevel`.
