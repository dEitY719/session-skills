# session:worktree-teardown — Help

## Synopsis

```
/session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]
/session:worktree-teardown [-h | --help | help]
```

Run from the **main repo** (not from inside a worktree).

## Description

Clean up an AI worktree after work is done — remove the worktree, sync main,
and delete the branch. The reverse of `session:worktree-spawn`. The worktree path
is passed as an argument (e.g., `/session:worktree-teardown ~/dotfiles-claude-2`).

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<worktree-path>` | Path to the worktree to remove (required). | — |
| `--force` | Skip pre-flight checks, force-remove a dirty worktree, force-delete an unmerged branch. | `false` |
| `--keep-branch` | Don't delete the branch after removing the worktree. | `false` |
| `--dry-run` | Print the plan (worktree path, branch, intended actions) without executing anything. | `false` |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/session:worktree-teardown ~/dotfiles-claude-2
/session:worktree-teardown ~/dotfiles-claude-2 --dry-run
/session:worktree-teardown ~/dotfiles-claude-2 --force --keep-branch
/session:worktree-teardown -h
```

## Stop conditions

- Inside a worktree (not the main repo) → print error with a `cd` hint, stop.
- Missing `<worktree-path>` argument → list active worktrees, stop.
- Path is not a known worktree → print error, list active worktrees, stop.
- Uncommitted changes or unpushed commits in the worktree → warn, stop (unless `--force`).
