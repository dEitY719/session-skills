# Claude Code native tools -- the `EnterWorktree` branch

Claude Code ships `EnterWorktree`, which creates a worktree and switches the
session into it. No other harness in this plugin's matrix (Codex, Gemini, Kimi,
opencode) has an equivalent, so this branch is Claude Code only; everywhere else
`lib/spawn.sh` is the whole skill and this file does not apply.

`EnterWorktree` replaces the `git worktree add` call and the cwd move. It does
**not** cover the four things this skill exists for, so they are layered on top
by hand.

## Tool

`EnterWorktree` takes `name` **or** `path`, never both:

- `name` -- optional name for a **new** worktree. `/`-separated segments of
  letters, digits, dots, underscores and dashes; 64 chars total. Omit it and the
  harness generates a random one.
- `path` -- an **existing** worktree from `git worktree list`, to switch into.

It returns `worktreePath`, `worktreeBranch` and `message`. The harness chooses
the directory, so the `../{project}-{agent}-{N}` directory convention is *not*
reproduced on this branch -- the index survives in the branch name instead.
Take `worktreePath` from the result rather than assuming a location.

Related: `Agent` accepts `isolation: "worktree"`, which gives a subagent its own
worktree with no skill involved. Use that when the isolated work is a delegated
task rather than this session's own workspace.

## Sequence

1. **Index and name (still this skill's).** Compute the agent name and the next
   free index exactly as `lib/spawn.sh` does -- `basename "$(git rev-parse
   --show-toplevel)"` for the project, `references/agent-detection.md` for the
   agent, then scan the parent directory for `{project}-{agent}-N` directories
   and take `max(N)+1`. Translate a Korean `--task` to an English slug first.
   The dry-run shortcut is `bash "${SKILL_DIR}/lib/spawn.sh" --dry-run`, which
   prints the agent, index, branch and base without creating anything.
2. **Create.** `EnterWorktree` with `name` set to the branch name from Step 1 --
   `wt/<agent>/<N>` or `wt/<agent>/<N>-<slug>`, both valid under the name rules.
   Pass an explicit `<branch>` argument through unchanged.
3. **git-crypt (still this skill's).** `EnterWorktree` knows nothing about
   git-crypt: an encrypted repo comes up with ciphertext in the working tree.
   Run the resolution and unlock from `references/options-and-errors.md` in the
   returned `worktreePath` -- resolve the key (`$GIT_CRYPT_KEY_FILE`,
   `~/.config/git-crypt/<project>.key`, `~/.config/git-crypt/default.key`), set
   the worktree-local bypass, `git-crypt unlock <key>`, then restore the filter
   to git-crypt. No key: leave the bypass in place and print the
   `gc-export-key` hint. The `git add <path>` caveat applies here identically.
4. **Audit trail (still this skill's).** Append the same `SPAWN` line
   `lib/spawn.sh` writes, to
   `$(git rev-parse --git-common-dir)/ai-worktree-spawn.log`, using the returned
   path and branch.
5. **Report.** Print the same `[OK] Worktree ready` block. Drop the trailing
   `cd` line -- `EnterWorktree` already moved the session.

## When to fall back to `lib/spawn.sh`

- The caller wants the `../{project}-{agent}-{N}` directory layout, which
  `EnterWorktree` does not let you choose.
- A base ref other than the current HEAD is required (`--base`); `EnterWorktree`
  exposes no base parameter.
- Concurrent spawns need the `ai-worktree-spawn.lock` serialization.

Nothing is lost by using the script on Claude Code -- it is the same skill.
