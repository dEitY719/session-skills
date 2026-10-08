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
ARTIFACT:<TAB>path=<p><TAB>status=<XY><TAB>type=<t><TAB>size=<s><TAB>mtime=<m><TAB>mtime_epoch=<n><TAB>target=<l><TAB>target_exists=<yes|no|-><TAB>target_size=<s><TAB>ignored_by=<rule|none><TAB>when=<w><TAB>documented_in=<files|none>
HINT:<TAB>path=<p><TAB>suggest=<commit|gitignore-gap|discard|preserve|review><TAB>reason=<text>
STATUS:<TAB>checkout=<abs><TAB>branch=<b><TAB>base=<ref|none><TAB>branch_first_commit=<date|none><TAB>branch_last_commit=<date|none><TAB>artifacts=<n>
```

| Field | Source |
|---|---|
| `path`, `status` | `git status --porcelain -z --untracked-files=normal`. A wholly untracked dir appears once, collapsed (`dir/` reported as `dir`). |
| `type` | `symlink` (`[ -L ]`), `dir`, `file`, or `missing` (deleted tracked file). |
| `size` | `du -sh` of the entry itself. For a symlink this is the link, never the target. |
| `target`, `target_exists`, `target_size` | Symlinks only: `readlink`, `[ -e ]`, `du -shL`. |
| `mtime`, `mtime_epoch` | lstat mtime -- GNU `stat -c`, falling back to BSD `stat -f`. |
| `ignored_by` | `git check-ignore -v --no-index` rule as `<file>:<line>:<pattern>`. |
| `when` | mtime vs the merge-base with `main`/`master` (or `origin/` of either) and the last branch commit: `before-branch`, `during-branch`, `after-last-commit`, `unknown`. |
| `documented_in` | `grep -lF` of the path or its basename in `README*`, `setup.sh`, `run.sh`, `local-ci.sh`, `Makefile`, `scripts/*`. |

`ARTIFACT` is printed before its `HINT`s; `STATUS` is always last, once.

## The dir-only gap probe

`git check-ignore <link>/` dies with "beyond a symbolic link", so for an
unignored symlink the script copies the checkout's `.gitignore` files into a
`mktemp -d` scratch tree and runs `check-ignore -v --no-index <path>/` there.
A match means a dir-only pattern (`.venv/`) would cover a real directory at
that path but misses the symlink; it is reported as a `gitignore-gap` HINT
naming the rule. The scratch dir is removed; the checkout is never written.

## Dependencies

bash, git, du, stat, grep, readlink, plus POSIX `cut`, `sed`, `tr`, `head`,
`tail`, `basename`, `dirname`, `mktemp`, `mkdir`, `cp`.

## Model judgment -- what the script cannot do

- **Pick the verdict.** HINTs come from name patterns and evidence; several can
  disagree on one path (a symlink is both `discard` and `gitignore-gap`). Weigh
  them against `artifact-patterns.md` and what the session actually did.
- **Name the creator.** `when` and `documented_in` are evidence for "the setup
  script made it during this branch"; the conclusion is yours.
- **Remove anything.** Disposal follows the SKILL.md MUST NOT list.
