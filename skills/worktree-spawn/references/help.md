# session:worktree-spawn — Help

## Synopsis

```
/session:worktree-spawn [--ai <name>] [--task <slug>] [--base <ref>] [--dry-run] [<branch>]
```

## Description

Create an isolated git worktree workspace for the current AI coding agent so
it can work in parallel without interfering with other agents in the same
repository. Detects the active agent, picks the next free index, and creates
a worktree at `../<project>-<agent>-<N>` on a `wt/<agent>/<N>` branch.

## Arguments

| Option | Description | Default |
|--------|-------------|---------|
| `--ai <name>` | Override the detected AI agent name. | Auto-detect (`$AI_AGENT_NAME`, env vars, then `agent`) |
| `--task <slug>` | Append a task slug to the branch name (Korean is translated to English kebab-case). | — |
| `--base <ref>` | Base ref for the new branch. | `origin/main` > `main`/`master` > current HEAD |
| `--dry-run` | Print the plan (agent, path, branch, base, command) and stop without creating anything. | `false` |
| `<branch>` | Use this explicit branch name instead of `wt/<agent>/<N>`. | Auto-generated |
| `-h` / `--help` / `help` | Print this help and stop. | — |

## Examples

```
/session:worktree-spawn
/session:worktree-spawn --task "login feature"
/session:worktree-spawn --ai claude --base origin/develop
```

## Stop conditions

- Caller is already inside a worktree — refuse and ask the user to exit first.
- Parent directory is not writable.
- `git worktree add` fails — surface the error and do not log a partial creation.
