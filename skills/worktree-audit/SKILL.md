---
name: worktree-audit
description: >-
  Audit untracked or modified leftovers blocking a worktree removal — who made
  each, why, and whether to commit, gitignore, discard, or preserve it — then
  chain to session:worktree-teardown. Use for /session:worktree-audit, "워크트리
  삭제가 안 돼", "이거 누가 만들었어", "커밋해야 해?", "버려도 되나?", "cleanup
  worktree leftovers".
license: MIT
allowed-tools: Bash, Read, Grep, Glob
metadata:
  model_recommendation:
    tier: sonnet
    reason: "judgment is the core — four-way verdict on forensic evidence; haiku is not appropriate"
    claude: prefer
    non_claude: advisory-only
---

# session:worktree-audit — Leftover Forensics

## Help

If arg #1 is `-h`/`--help`/`help`, read `references/help.md` verbatim and stop.

Audit what is left in a worktree (or any checkout) before it can be removed:
identify each untracked or modified entry, judge it, dispose of it safely, and
hand off to `session:worktree-teardown` when removal is the goal. The script
collects evidence; **the verdict is yours**. `SKILL_DIR` = this file's directory.

Real case (`wt/issue-17/1`): `?? backend/.venv` blocked teardown. It was a
symlink to the main repo's 323M venv, created by the repo's documented
`local-ci.sh` setup, and the root `.venv/` ignore rule is dir-only, so it never
matched the symlink. Fix: `rm backend/.venv` (link only, target confirmed
intact). Detail in `references/artifact-patterns.md`.

## Step 1: List the blockers

```
git -C <checkout-path> status --short
git worktree list
```

Map each entry to the teardown pre-flight line it triggers (`Error: Uncommitted
changes detected` for modified or untracked files).

## Step 2: Collect evidence

```
bash "${SKILL_DIR}/lib/audit.sh" <checkout-path>
```

Use the current checkout when the user named none. Non-destructive; runs from
the main repo or the worktree. It prints one
`ARTIFACT:` line per entry (type, size, mtime, symlink target and whether it
exists, `git check-ignore -v` rule, creation time vs the branch commit range,
setup-doc mentions), `HINT:` lines, and a closing `STATUS:` line. Read
`references/audit-contract.md` for the field format and exit codes.

## Step 3: Judge each artifact (model judgment)

HINTs are suggestions. Weigh them with `references/artifact-patterns.md`:

| Verdict | Criterion | Action |
|---|---|---|
| commit | tracked source change / new work product | Out of scope: hand off to `gh-pr:commit` or `session:handoff`, then stop |
| gitignore gap | not ignored, but the repo documents it as ignorable | Never edit repo files: propose a follow-up issue |
| discard | symlink (target confirmed), setup-regenerable, cache, lock | Remove safely now |
| preserve | unique data: eval results, logs, dumps | Ask the user, or archive first, then remove |

A gitignore-gap artifact that is also regenerable is discarded now **and** gets
the follow-up issue.

## MUST NOT

- Never `rm -r`, `rm -rf`, or a trailing slash on a symlink — that walks into
  the **target**. Confirm `target_exists=yes`, run `rm <link>`, then verify the
  target still exists.
- Never run `git worktree remove` directly — removal goes through
  `session:worktree-teardown`.
- Never pass `--force` on your own judgment; it is the user's word, relayed.
- Never edit `.gitignore` or any other repo file — propose an issue instead.
- Never commit; a "commit" verdict is handed off, not executed.

## Step 4: Chain or stop

If removal is the goal and every blocker is resolved, run
`session:worktree-teardown <worktree-path>` **from the main repo** and carry its
`[OK] Teardown complete` or `[FAIL]` verdict into the report. If any artifact is
left for commit or preserve, or the user only asked for an audit, report and stop.

## Report

```
| Path | Identity | Creator / when | Evidence | Verdict | Action |
|---|---|---|---|---|---|
| backend/.venv | symlink -> <main>/backend/.venv (exists) | local-ci.sh setup, during branch | .venv/ dir-only, misses link | discard + gap | rm backend/.venv; target intact |

Teardown: [OK] Teardown complete (or: not run -- <reason>)
Follow-up issues: <proposed title + one-line body, or none>
```
