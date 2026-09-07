# `lib/teardown.sh` -- interface contract

The whole destructive sequence lives in `lib/teardown.sh`, including the Step 3
work-loss guard. Call it; never re-transcribe it and never substitute a bare
`git worktree remove` -- a hand-run removal skips the pre-flight entirely.

```
bash "${SKILL_DIR}/lib/teardown.sh" <worktree-path> [--force] [--keep-branch] [--dry-run]
```

Run from the **main repo**. The script refuses to run from inside a worktree.

## Arguments

| Argument | Effect |
|---|---|
| `<worktree-path>` | Required. Resolved with `realpath` and matched against `git worktree list --porcelain`. |
| `--force` | The user's explicit override of the pre-flight: discards uncommitted changes and unpushed commits, force-removes the worktree, force-deletes an unmerged branch. Never the agent's shortcut past a block. |
| `--keep-branch` | Remove the worktree, keep the branch. |
| `--dry-run` | Print the resolved path, branch and action list, then stop. Validation and resolution still run, so a bad path still errors. |
| `-h` / `--help` | Script usage. The skill's user-facing help is `references/help.md`. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Teardown complete, or `--dry-run` plan printed. |
| 1 | Inside a worktree, missing/unknown `<worktree-path>`, unknown option, pre-flight block, removal failure, or no `main`/`master`. |

Any non-zero exit is what SKILL.md Step 4 turns into the `[FAIL]` verdict: the
`Error:` line is the reason, the surrounding output is the detail.

## Guards -- the reason this is a script

Pre-flight blocks before anything is removed, unless `--force`:

```
Error: Uncommitted changes detected in <path>.
  Commit, stash, or use --force to discard.
Error: Unpushed commits detected.
  Push first, or use --force to discard.
```

Uncommitted covers both the unstaged and the staged diff. Unpushed is
`@{u}..HEAD`; a branch with no upstream configured is not a block.

Main is synced **before** the branch delete so `git branch -d` can verify merge
status. `git branch -d` stays safe-delete: an unmerged branch is kept with a
warning, and only `--force` escalates to `-D`.

## Output

```
Worktree removed: <path>
Branch deleted: <branch>
[OK] Teardown complete
  Removed:  <path>
  Branch:   <branch> (deleted | kept | kept (not fully merged) | force-deleted)
  Now on:   <main> (up to date with origin/<main> | pull failed -- ...)

  Note: if your outer shell was cd'd inside the removed worktree, run
  `cd <main-repo>` there now to avoid `getcwd: cannot access parent
  directories` errors from zsh/pyenv/p10k.
```

The `Note:` block is unconditional -- the outer shell's cwd is undetectable
from inside the script.

## Model judgment -- what the script cannot do

- **Hand off a pull conflict.** On a failed `git pull` the script prints
  `Conflict detected during pull.` and the `--diff-filter=U` file list, sets
  `Now on: <main> (pull failed ...)`, and continues to the safe branch delete.
  Point the user at `gh-resolve:conflict` -- resolving it here would need more
  reasoning than this skill's declared `haiku` tier budgets for.
- **Decide `--force`.** It is the user's word, relayed. A pre-flight block is
  reported and the run stops; it is not re-run with `--force` on your judgment.
- **Pick the worktree.** The path is an argument; the script only verifies it.
