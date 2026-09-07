---
name: worktree-teardown
description: >-
  Remove an AI worktree, delete its branch, and sync main — the reverse of
  session:worktree-spawn. Run from the MAIN repo with the worktree path as
  an argument. Use for /session:worktree-teardown, "작업 끝", "워크트리 정리", "워크트리
  제거", "cleanup worktree".
license: MIT
allowed-tools: Bash, Read, Grep, Glob, ExitWorktree
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
`SKILL_DIR` = this file's directory.

## Step 1: Confirm the target (model judgment)

This is the destructive skill in this plugin. Before running anything, confirm
which worktree the user means — `git worktree list` in the main repo — and pass
it as `<worktree-path>`. Prefer `--dry-run` first when the target came from
inference rather than from the user naming a path.

`--force` is the user's explicit override of the work-loss guard, never a
shortcut past a block you hit. If the pre-flight refuses, report what would be
lost and stop.

## Step 2: Run the teardown

```
bash "${SKILL_DIR}/lib/teardown.sh" <worktree-path> [--force] [--keep-branch] [--dry-run]
```

The script validates that you are in the main repo and not inside a worktree,
resolves the path and branch, runs the pre-flight work-loss guard (uncommitted
changes, unpushed commits), removes and prunes the worktree, syncs main
**before** the branch delete so `git branch -d` can verify merge status, safe-
deletes the branch, appends the audit log, and prints the report.
`references/bash-commands.md` is its full contract: arguments, exit codes,
guards, output lines, and what stays model judgment.

**Claude Code only:** `ExitWorktree` enforces the same pre-flight in the
harness — it refuses `action: "remove"` on a worktree with uncommitted files or
unmerged commits unless `discard_changes` is true — but it runs from *inside*
the worktree and does not sync main first. Read `references/native-tools.md`
and follow it when the session is already in the worktree it is done with.
Every other harness (Codex, Gemini, Kimi, opencode) uses the script above.

## Step 3: Hand off a pull conflict — do not resolve it here

If the sync conflicts, the script prints `Conflict detected during pull.` and
the conflicting file list, then still finishes the branch delete and the
report below (the worktree teardown itself succeeded; only the main sync is
degraded — see the `Now on:` line). Do not attempt to resolve it yourself:
point the user at `gh-resolve:conflict`. Resolving merge conflicts needs more
reasoning than this skill's declared `haiku` tier budgets for.

## Step 4: Report

On success the script prints:

```
[OK] Teardown complete
  Removed:  ../my-app-gemini-1
  Branch:   wt/gemini/1 (deleted)
  Now on:   main (up to date with origin/main)

  Note: if your outer shell was cd'd inside the removed worktree, run
  `cd <main-repo>` there now to avoid `getcwd: cannot access parent
  directories` errors from zsh/pyenv/p10k.
```

The `Note:` block is unconditional — the outer shell's cwd is undetectable.

On a non-zero exit, emit a structured failure verdict instead, filled in from
the script's `Error:` line and surrounding output:

```
[FAIL] <reason>
  Step:    <step name where failure occurred>
  Detail:  <error message or exit code>
```
