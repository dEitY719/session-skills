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

Real case (`wt/issue-17/1`): a `?? backend/.venv` symlink to the main repo's
venv, missed by a dir-only `.venv/` rule. See `references/artifact-patterns.md`.

## Step 1: List the blockers

```
git -C <checkout-path> status --short
git worktree list
```

Map each entry to the teardown pre-flight line it triggers (`Error: Uncommitted
changes detected` for modified or untracked files). Unpushed commits are the
other block (`Error: Unpushed commits detected`); Step 2 counts them.

## Step 2: Collect evidence

```
bash "${SKILL_DIR}/lib/audit.sh" <checkout-path>
```

Default: the current checkout. Non-destructive; runs from the main repo or the
worktree. Prints one `ARTIFACT:` line per entry (type, size, mtime, symlink
target, ignore rule, creation time vs branch commits, setup-doc mentions),
`HINT:` lines, and a closing `STATUS:` line with `unpushed=<n|none-upstream>`.
Field format and exit codes: `references/audit-contract.md`.

## Step 3: Judge each artifact (model judgment)

HINTs are suggestions. Weigh them with `references/artifact-patterns.md`:

| Verdict | Criterion | Action |
|---|---|---|
| commit | tracked source change / new work product | Out of scope: hand off to `gh-pr:commit` or `session:handoff`, then stop |
| gitignore gap | not ignored, but the repo documents it as ignorable | Never edit repo files: propose a follow-up issue |
| discard | untracked only: symlink (target confirmed), setup-regenerable, cache, lock | Remove safely now |
| preserve | unique data: eval results, logs, dumps | Ask the user, or archive first, then remove |

A gitignore-gap artifact that is also regenerable is discarded now **and** gets
the follow-up issue.

## MUST NOT

- Symlink: only `rm <link>` — never `-r`/`-rf` or a trailing slash, which walks
  into the **target**. Confirm `target_exists=yes` first, the target after.
- Real dir (discard verdict, untracked only): `rm -r <dir>`, no trailing
  slash, and only after `[ ! -L <dir> ]` confirms it is not a link.
- Never run `git worktree remove` directly — removal goes through
  `session:worktree-teardown`.
- Never pass `--force` on your own judgment; it is the user's word, relayed.
- Never edit `.gitignore` or any other repo file — propose an issue instead.
- Never commit; a "commit" verdict is handed off, not executed.

## Step 4: Chain or stop

If removal is the goal, every artifact is resolved, and `unpushed` is `0` or
`none-upstream`, run `session:worktree-teardown <worktree-path>` **from the main
repo** and carry its `[OK] Teardown complete` or `[FAIL]` verdict into the
report. `unpushed>0` is not resolved: hand off to `gh-pr:create` or `git push`
(never `--force`), then stop. If any artifact is left for commit or preserve,
or the user only asked for an audit, report and stop.

## Report

```
| Path | Identity | Creator / when | Evidence | Verdict | Action |
|---|---|---|---|---|---|
| backend/.venv | symlink -> <main>/backend/.venv (exists) | local-ci.sh setup, during branch | .venv/ dir-only, misses link | discard + gap | rm backend/.venv; target intact |

Teardown: [OK] Teardown complete (or: not run -- <reason>)
Follow-up issues: <proposed title + one-line body, or none>
```
