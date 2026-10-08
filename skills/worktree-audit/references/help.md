# session:worktree-audit — Help

## Synopsis

```
/session:worktree-audit [<checkout-path>]
/session:worktree-audit [-h | --help | help]
```

Defaults to the current checkout. The audit itself is read-only and runs from
the main repo or from inside the worktree.

## Description

Explain every untracked or modified entry that blocks a worktree removal: what
it is, who created it and when, and whether to commit it, close a `.gitignore`
gap for it, discard it, or preserve it. Disposes of the safe cases (symlinks
with a surviving target, caches, setup-regenerable artifacts), then chains to
`session:worktree-teardown` from the main repo when removal is the goal.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `<checkout-path>` | Worktree or checkout to audit. | current directory |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/session:worktree-audit ../my-app-claude-1
/session:worktree-audit
/session:worktree-audit -h
```

## Stop conditions

- Path missing or not a git checkout → print the error, stop.
- Any artifact judged "commit" → hand off to `gh-pr:commit` / `session:handoff`, stop.
- Any artifact judged "preserve" without the user's go-ahead → report, stop.
- `unpushed>0` → hand off to `gh-pr:create` / `git push` (never `--force`), stop.
- Teardown pre-flight still refuses → report its `Error:` line, stop. Never
  retry with `--force` unless the user says so.

## Never

- Recursive or trailing-slash `rm` on a symlink; `rm -r` on a real dir before
  `[ ! -L <dir> ]`, or on anything tracked or judged preserve.
- `git worktree remove` by hand.
- Editing `.gitignore` or other repo files (a follow-up issue is proposed instead).
