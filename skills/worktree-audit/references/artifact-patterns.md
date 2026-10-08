# Leftover artifact catalog

Default verdicts for entries that commonly block a worktree teardown. A default
is a starting point; the evidence from `lib/audit.sh` can overrule it.

| Pattern | Usual origin | Default verdict | Before removing |
|---|---|---|---|
| `.venv`, `venv` as a **symlink** | Worktree setup linking to the main repo's venv | discard (+ gitignore gap if `.venv/` is dir-only) | `target_exists=yes`; `rm <link>`; re-check target |
| `.venv`, `venv` as a real dir | uv / venv / poetry | discard when a setup script recreates it | `documented_in` names the script |
| `node_modules/` | npm / pnpm / yarn install | discard | a lockfile is tracked |
| `dist/`, `out/`, `build/` | build output | discard | a build command exists |
| `__pycache__/`, `.pytest_cache/`, `.mypy_cache/`, `.ruff_cache/` | interpreter / tool caches | discard | none |
| `.setup.lock` and similar completion markers | setup scripts | discard | none |
| any symlink into another checkout | manual or scripted linking | discard the link only | target survives; never recurse |
| `logs/`, `*.log`, dumps, eval results | test or eval runs | preserve | ask the user, or archive |
| modified tracked file | the session's own work | commit (hand off) | none -- not this skill's to commit |
| new untracked source file | the session's own work | commit (hand off) | none |

## Real case: symlinked venv behind a dir-only ignore rule

`wt/issue-17/1`, 2026-10-08. `git status` showed `?? backend/.venv`, which
blocked both `git worktree remove` and the teardown pre-flight.

- **Identity.** `ls -ld` / `readlink`: a symlink to the main repo's
  `backend/.venv` (323M). The issue session created it following the repo's
  `local-ci.sh` pattern; the frontend test runner (`node tests/run.mjs`) spawns
  `backend/.venv/bin/python` per worker, so the link was needed for tests.
- **Why it was not ignored.** The root `.gitignore` has `.venv/`. A trailing
  slash makes a pattern match directories only, and git sees a symlink as a
  file, never a directory -- so the rule silently misses it.
  `git check-ignore -v backend/.venv` prints nothing; the audit's gap probe
  shows `.gitignore:N:.venv/` matching `backend/.venv/`.
- **Disposal.** `rm backend/.venv` (no `-r`, no trailing slash), confirm the
  main repo venv is intact, status clean, then `session:worktree-teardown`.
- **Follow-up.** Propose an issue to change the rule to `.venv` (no slash) so
  it covers both the directory and the link. Do not edit `.gitignore` here.

## Why `rm -rf <link>/` is dangerous

With a trailing slash the path resolves through the link, so `rm -rf
backend/.venv/` deletes the **contents of the target** -- the main repo's venv
-- and leaves the link behind. `rm backend/.venv` removes only the link.
