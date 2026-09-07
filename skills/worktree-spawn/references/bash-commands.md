# `lib/spawn.sh` -- interface contract

The whole deterministic sequence lives in `lib/spawn.sh`. Call it; do not
re-transcribe it, and do not run the individual `git worktree add` commands by
hand -- the lock, the index scan and the git-crypt sequencing only hold when
they run together.

```
bash "${SKILL_DIR}/lib/spawn.sh" [--ai <name>] [--task <slug>] [--base <ref>] [--dry-run] [<branch>]
```

## Arguments

| Argument | Effect |
|---|---|
| `--ai <name>` | Skips detection and uses `<name>` as the agent. |
| `--task <slug>` | Branch becomes `wt/<agent>/<N>-<slug>`. The script normalizes (lowercase, non-alnum to hyphens, 30 chars); it does **not** translate -- see "Model judgment" below. |
| `--base <ref>` | Base ref. Unresolvable ref is a hard error, not a fallback. |
| `--dry-run` | Prints agent, path, branch, base and the exact `git worktree add` line, then stops. Nothing is created and nothing is logged. |
| `<branch>` | Explicit branch name, used verbatim instead of `wt/<agent>/<N>`. |
| `-h` / `--help` | Prints the script's own usage. The skill's user-facing help is `references/help.md`. |

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Worktree created, or `--dry-run` plan printed. |
| 1 | Precondition failure (not a git repo, called from inside a worktree, parent not writable), unknown option, unresolvable `--base`, or a failing `git worktree add`. |
| 2 | Lock acquisition failed after 3 retries. Another spawn is mid-flight. |

Stop on any non-zero exit and surface stderr. Never retry a failed spawn
without reading the error first -- exit 2 in particular means a concurrent
spawn, not a transient glitch.

Any non-zero exit is what SKILL.md's report step turns into the `[FAIL]`
verdict: the `Error:` line is the reason, the numbered step below where it
failed (validate, detect agent, acquire lock, scan index, resolve base ref,
`git worktree add`, log, report) is the `Step`, and the exit code is the
`Detail`.

## Output

On success, exactly this block on stdout (git's own `Preparing worktree` chatter
precedes it):

```
[OK] Worktree ready
  Path:   <absolute worktree path>
  Branch: <branch>
  Base:   <base ref>
  git-crypt: <report>          # only when the repo uses git-crypt
  Teardown: git push -u origin <branch> && git worktree remove <path> && git branch -d <branch>
  cd <absolute worktree path>
```

The `git-crypt:` line is one of:

- `unlocked via <key path>` -- auto-unlock succeeded.
- `disabled (no key; run from main repo: gc-export-key)` -- bypass path.
- `disabled (unlock failed; encrypted files stay binary)` -- key found but
  `git-crypt unlock` failed; the temporary bypass config stays in place.

## What the script does, in order

1. Validate: git repo, `git-dir == git-common-dir` (refuse from inside a
   worktree), warn on a dirty tree, parent directory writable.
2. Detect the agent (`references/agent-detection.md` for the chain).
   1.5 Detect git-crypt and resolve the key file
   (`references/options-and-errors.md` for the priority chain).
   3.5 Acquire `$(git rev-parse --git-common-dir)/ai-worktree-spawn.lock` via
   `mkdir`; a lock older than 10s is treated as stale and removed.
3. Scan the parent for `{project}-{agent}-N` and take `max(N)+1`.
4. Branch name. 5. Base ref: `--base` > `origin/main` > `main`/`master` > `HEAD`.
6. `git worktree add`, on the auto-unlock or the bypass path.
7. Append one `SPAWN` line to
   `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`.
8. Print the report above.

## Model judgment -- what the script cannot do

- **Translate a Korean `--task`.** `normalize_slug` strips non-ASCII, so
  `--task "로그인 기능"` yields an empty slug. Translate first and pass
  `--task "login feature"`.
- **Decide `--ai`.** Detection covers the common harnesses; override only when
  it guesses wrong.
- **Stage files afterwards.** In an auto-unlocked worktree use explicit
  `git add <path>`, never `-A` or `.`.
- **Change the caller's cwd.** The script prints `cd <path>`; you execute it.
