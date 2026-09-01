# Options and Error Handling — CLI reference

## Usage

```
/session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]
```

Run from the **main repo** (not from inside a worktree).

## Options

| Option | Description | Default |
|---|---|---|
| `<worktree-path>` | Path to the worktree to remove (required) | — |
| `--force` | Skip pre-flight checks, force remove dirty worktree, force delete unmerged branch | `false` |
| `--keep-branch` | Don't delete the branch after removing worktree | `false` |
| `--dry-run` | Print plan without executing anything | `false` |

When `--dry-run` is specified, print the full plan (worktree path, branch,
actions to take) and stop without executing anything.

## Error Handling

| Situation | Action |
|---|---|
| Inside a worktree (not main repo) | Print error with `cd` hint, stop |
| Missing `<worktree-path>` argument | List active worktrees, stop |
| Path is not a known worktree | Print error, list active worktrees, stop |
| Uncommitted changes in worktree | Warn, stop (unless `--force`) |
| Unpushed commits in worktree | Warn, stop (unless `--force`) |
| Worktree remove fails | Try `--force` if opted in, else stop |
| Branch not fully merged | Warn, skip branch delete (unless `--force`) |
| Main branch not found | Try `master`, then error |
| Pull conflict | AI agent attempts resolution, reports to user |
