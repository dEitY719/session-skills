# Options and Error Handling — CLI reference

## Usage

```
/session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]
```

Run from the **main repo** (not from inside a worktree). See
`references/help.md` for the full options table and examples.

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
| Pull conflict | Script finishes teardown, flags it in the report; hand off to `gh-resolve:conflict` |
