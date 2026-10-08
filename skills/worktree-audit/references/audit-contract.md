# `lib/audit.sh` -- interface contract

The evidence half of `session:worktree-audit`. It reads; it never deletes,
edits, stages, or commits anything in the checkout. The verdict is not its job.

```
bash "${SKILL_DIR}/lib/audit.sh" <checkout-path>
```

Runs from anywhere -- the main repo or the worktree itself.

## Exit codes

| Code | Meaning |
|---|---|
| 0 | Audit completed, including a clean checkout with zero artifacts. |
| 1 | Bad parameters: missing argument, extra arguments, path not a directory, or not a git checkout. The `Error:` line on stderr says which. |

## Output

One record per line: a `KIND:` tag, then TAB-separated `key=value` fields. Keys
are stable; add new keys at the end, never rename. Values never contain a TAB.
`-` means not applicable, `none` means looked and found nothing.

```
ARTIFACT:<TAB>path=<p><TAB>status=<XY><TAB>type=<t><TAB>size=<s><TAB>mtime=<m><TAB>mtime_epoch=<n><TAB>target=<l><TAB>target_exists=<yes|no|-><TAB>ignored_by=<rule|none><TAB>when=<w><TAB>documented_in=<files|none>
HINT:<TAB>path=<p|-><TAB>suggest=<commit|gitignore-gap|discard|preserve|review|push><TAB>reason=<text>
STATUS:<TAB>checkout=<abs><TAB>branch=<b><TAB>base=<ref|none><TAB>branch_first_commit=<date|none><TAB>branch_last_commit=<date|none><TAB>artifacts=<n><TAB>unpushed=<n|none-upstream>
```

| Field | Source |
|---|---|
| `path`, `status` | `git status --porcelain -z --untracked-files=normal`. A wholly untracked dir appears once, collapsed (`dir/` reported as `dir`); every symlink inside it (`find -type l`, not followed, `-maxdepth 4`, `node_modules`/`.git` pruned) gets its own `status=??` record after the dir's. |
| `type` | `symlink` (`[ -L ]`), `dir`, `file`, or `missing` (deleted tracked file). |
| `size` | `du -sh` of the entry itself, under `timeout 5` when available; `?` on timeout or failure. For a symlink this is the link, never the target (the target is not walked). |
| `target`, `target_exists` | Symlinks only: `readlink`, `[ -e ]`. |
| `mtime`, `mtime_epoch` | lstat mtime -- GNU `stat -c`, falling back to BSD `stat -f`. |
| `ignored_by` | `git check-ignore -v --no-index` rule as `<file>:<line>:<pattern>`. |
| `when` | mtime vs the merge-base with the first of `origin/main`, `main`, `master` that exists (worktree-spawn's order) and the last branch commit: `before-branch`, `during-branch`, `after-last-commit`, `unknown`. |
| `documented_in` | `grep -lwF` (whole word) of the relative path in the **tracked** `README*`, `setup.sh`, `run.sh`, `local-ci.sh`, `Makefile`, `scripts/*`, excluding the artifact itself and anything inside it. |
| `unpushed` | `git rev-list --count @{u}..HEAD`, the test worktree-teardown blocks on; `none-upstream` when no upstream is set (not a block). |

`ARTIFACT` is printed before its `HINT`s; `STATUS` is always last, once.
`artifacts` counts every `ARTIFACT` record, nested symlinks included.

HINT rules: a tracked entry (`status` other than `??`) only ever gets
`commit`; `discard` and `preserve` are for untracked entries. A `discard` from
a `documented_in` match or a `build`/`dist`/`out` name never suppresses the
`commit` hint for an untracked entry created on this branch -- both are
printed. When `unpushed>0`, one `HINT` with `path=-` and `suggest=push`
precedes `STATUS`.

## The dir-only gap probe

`git check-ignore <link>/` dies with "beyond a symbolic link", so for an
unignored symlink the script copies the checkout's `.gitignore` files into a
`mktemp -d` scratch tree and runs `check-ignore -v --no-index <path>/` there.
A match means a dir-only pattern (`.venv/`) would cover a real directory at
that path but misses the symlink; it is reported as a `gitignore-gap` HINT
naming the rule. The scratch dir is built once per run and removed by an
`EXIT` trap; the checkout is never written.

## Dependencies

bash, git, du, stat, grep, readlink, find, plus POSIX `cut`, `sed`, `tr`,
`basename`, `dirname`, `mktemp`, `mkdir`, `cp`. `timeout` is optional.

## Model judgment -- what the script cannot do

- **Pick the verdict.** HINTs come from name patterns and evidence; several can
  disagree on one path (a symlink is both `discard` and `gitignore-gap`). Weigh
  them against `artifact-patterns.md` and what the session actually did.
- **Name the creator.** `when` and `documented_in` are evidence for "the setup
  script made it during this branch"; the conclusion is yours.
- **Remove anything.** Disposal follows the SKILL.md MUST NOT list.
