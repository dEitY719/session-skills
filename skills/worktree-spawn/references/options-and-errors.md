# Options and Error Handling -- CLI reference

`references/help.md` is the single user-facing options table (it is what
`-h`/`--help`/`help` prints verbatim). This file covers only what help.md
doesn't: error handling and the git-crypt sequence.

There is no `--list` option. Run `git worktree list` in the main repo to see
the worktrees that already exist.

## Error Handling

| Situation | Action |
|---|---|
| Not a git repo | Print error, stop |
| Inside a worktree | Print error, stop (always use a new terminal on the main repo) |
| Base ref not found | Suggest `main`/`origin/main`, stop |
| Path already exists | Auto-increment to next index |
| Branch in use by another worktree | Print error, ask user for different name |
| Parent dir not writable | Print error, stop |
| Lock acquisition failed (3 retries) | Print error, stop |
| Stale lock (age > 10s) | Auto-remove lock, retry |
| git-crypt active + key file resolved | Auto-unlock 4-step: bypass-checkout → temp bypass config → `git-crypt unlock <key>` → restore filter to git-crypt (encrypted files decrypt normally) |
| git-crypt active + no key file | Bypass: create worktree with filter disabled (encrypted files stay as binary), print `gc-export-key` hint |
| git-crypt active + unlock fails | Stay on temp bypass config, log warning, encrypted files stay binary |

## git-crypt Key File Resolution

When the repo uses git-crypt, the spawn step searches for a symmetric key file in this order:

1. `$GIT_CRYPT_KEY_FILE` environment variable (if set and readable)
2. `~/.config/git-crypt/<project-name>.key` where `<project-name>` is `basename` of the repo
3. `~/.config/git-crypt/default.key`

To produce a key file from an unlocked main repo, use the helper that handles
the standard path and 0600 mode automatically:

```bash
gc-export-key                  # writes ~/.config/git-crypt/<project-name>.key
```

Or call git-crypt directly if you want a custom path:

```bash
git-crypt export-key /custom/path/keyfile
chmod 600 /custom/path/keyfile
```

Treat this key file like a private credential: never commit it, never share over insecure channels.

## Auto-Unlock Caveat: status appears dirty

After auto-unlock, `git status` in the new worktree may list every git-crypt
file as `M` (modified). `git diff` against those same files is empty (textconv
comparison sees identical plaintext). The discrepancy comes from git comparing
raw bytes: clean-filter output of the worktree's plaintext vs. the index's
ciphertext. They are functionally equivalent (same plaintext after decrypt) but
not byte-identical, likely due to a key-storage encoding difference between the
main repo's `git-crypt/keys/default` and the per-worktree GIT_DIR copy.

**Implication for AI agents and humans alike**: do NOT use `git add -A` /
`git add .` in an auto-unlocked worktree — git-crypt files would be staged with
re-encoded ciphertext that differs from the main repo's. Always use explicit
`git add <path>` for the files you actually changed.

If you accidentally stage a git-crypt file, run `git restore --staged <path>`
to unstage. The actual encrypted content has not changed — verify with
`git diff --cached` (textconv comparison shows no plaintext change).
