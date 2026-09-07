# Claude Code native tools -- the `ExitWorktree` branch

Claude Code ships `ExitWorktree`, which leaves the current worktree and can
delete it and its branch. No other harness in this plugin's matrix (Codex,
Gemini, Kimi, opencode) has an equivalent, so this branch is Claude Code only;
everywhere else `lib/teardown.sh` is the whole skill.

## Why this branch is worth taking

`ExitWorktree`'s `discard_changes` is Step 3's pre-flight, enforced by the
harness instead of by shell:

> Required true when action is "remove" and the worktree has uncommitted files
> or unmerged commits. The tool will refuse and list them otherwise.

That is the same contract as `lib/teardown.sh`'s `preflight_check` -- refuse,
name what would be lost, and make the override explicit -- except it cannot be
bypassed by a transcription slip. `discard_changes: true` is this skill's
`--force`: the user's explicit override, never the agent's shortcut past a
block. Report the refusal and stop.

## Tool

`ExitWorktree` takes:

- `action` -- `"keep"` leaves the worktree and branch on disk; `"remove"`
  deletes both.
- `discard_changes` -- as above.

It returns `action`, `originalCwd`, `worktreePath`, `worktreeBranch`,
`discardedFiles`, `discardedCommits` and `message`. Take the path and branch
for the log line from that result.

## Direction of travel differs

`lib/teardown.sh` runs **from the main repo** with the worktree as an argument.
`ExitWorktree` runs **from inside** the worktree it removes and returns the
session to `originalCwd`. So this branch applies when the session is already in
the worktree it is done with; tearing down some *other* worktree by path is the
script's job.

## Sequence

1. **Sync main first (still this skill's).** `ExitWorktree` deletes the branch
   as part of `action: "remove"`, with no merge check against an up-to-date
   main. Sync before the call so the delete is evaluated against real state:
   `git -C <main-repo> checkout main && git -C <main-repo> pull origin main`
   (`master` if there is no `main`). On a conflict, stop, report the
   conflicted files, and tell the user to resolve them by hand before
   removing anything -- see `bash-commands.md` for why this isn't a
   `gh-resolve:conflict` handoff.
2. **Remove.** `ExitWorktree` with `action: "remove"`. Omit `discard_changes` --
   let the tool run the guard. If it refuses, surface its list of uncommitted
   files and unmerged commits and stop. Only re-issue with
   `discard_changes: true` when the user has said so.
3. **Audit trail (still this skill's).** Append the same `TEARDOWN` line
   `lib/teardown.sh` writes, to
   `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`, using the returned
   `worktreePath` and `worktreeBranch`.
4. **Report.** Print the same `[OK] Teardown complete` block. Keep the `Note:`
   about the outer shell's cwd -- `ExitWorktree` moves this session, not the
   user's terminal.

## When to fall back to `lib/teardown.sh`

- Tearing down a worktree the session is not currently in (the normal case:
  the skill's documented contract is a `<worktree-path>` argument from the
  main repo).
- `--keep-branch`: `ExitWorktree`'s `"keep"` keeps the worktree too, so the
  "remove the worktree, keep the branch" combination has no native form.
- `--dry-run`: no native equivalent. `bash "${SKILL_DIR}/lib/teardown.sh"
  <path> --dry-run` prints the plan without touching anything.
