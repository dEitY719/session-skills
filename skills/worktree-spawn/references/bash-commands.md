# Bash Commands -- implementation details for each execution step

## Step 1: Validate Preconditions

```bash
# Must be inside a git repo
git rev-parse --show-toplevel

# Must NOT be inside an existing worktree -- block if so
GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_DIR="$(git rev-parse --git-dir)"
if [[ "$GIT_DIR" != "$GIT_COMMON" ]]; then
  echo "Error: Cannot spawn from inside a worktree. Run from the main repository."
  exit 1
fi

# Warn on dirty state (do not block)
git diff --quiet || echo "Warning: uncommitted changes in working directory"

# Check parent directory is writable
PARENT="$(dirname "$(git rev-parse --show-toplevel)")"
test -w "$PARENT" || { echo "Error: Permission denied: $PARENT"; exit 1; }
```

## Step 2: Detect AI Agent

```bash
detect_ai_agent() {
  # Priority 1: --ai argument (passed as $1)
  if [[ -n "${1:-}" ]]; then
    echo "$1"
    return
  fi

  # Priority 2: AI_AGENT_NAME env var
  if [[ -n "${AI_AGENT_NAME:-}" ]]; then
    echo "$AI_AGENT_NAME"
    return
  fi

  # Priority 3: Agent-specific env vars
  if [[ "${CLAUDECODE:-}" == "1" ]]; then echo "claude"; return; fi
  if [[ "${AGY_CLI:-}" == "1" ]]; then echo "agy"; return; fi
  if [[ "${CODEX_CLI:-}" == "1" ]]; then echo "codex"; return; fi
  if [[ "${OPENCODE:-}" == "1" ]]; then echo "opencode"; return; fi
  if [[ "${CURSOR:-}" == "1" || "${TERM_PROGRAM:-}" == "cursor" ]]; then echo "cursor"; return; fi
  if [[ "${GITHUB_COPILOT:-}" == "1" ]]; then echo "copilot"; return; fi

  # Priority 4: Fallback
  echo "agent"
}

AGENT="$(detect_ai_agent "${AGENT_OVERRIDE:-}")"
```

## Step 1.5: Detect git-crypt and resolve key file

```bash
# Check if repo uses git-crypt
GIT_CRYPT_ACTIVE=false
if git config --get filter.git-crypt.smudge >/dev/null 2>&1; then
  GIT_CRYPT_ACTIVE=true
fi

# Resolve git-crypt key file via priority chain
# 1) $GIT_CRYPT_KEY_FILE  2) ~/.config/git-crypt/<project>.key  3) ~/.config/git-crypt/default.key
GIT_CRYPT_KEY=""
PROJECT_NAME="$(basename "$(git rev-parse --show-toplevel)")"
if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
  for candidate in \
    "${GIT_CRYPT_KEY_FILE:-}" \
    "${HOME}/.config/git-crypt/${PROJECT_NAME}.key" \
    "${HOME}/.config/git-crypt/default.key"; do
    if [[ -n "$candidate" && -r "$candidate" ]]; then
      GIT_CRYPT_KEY="$candidate"
      break
    fi
  done
fi

# Bypass flags ONLY when git-crypt is active AND no key file resolved.
# When a key is found, auto-unlock path runs in Step 6 instead.
GIT_CRYPT_FLAGS=()
if [[ "$GIT_CRYPT_ACTIVE" == true && -z "$GIT_CRYPT_KEY" ]]; then
  GIT_CRYPT_FLAGS=(-c filter.git-crypt.smudge=cat -c filter.git-crypt.clean=cat)
fi
```

## Step 3: Compute Project Name and Index

```bash
PROJECT="$(basename "$(git rev-parse --show-toplevel)")"
PARENT="$(dirname "$(git rev-parse --show-toplevel)")"

# Find next available index
# Scan parent directory for {PROJECT}-{AGENT}-N pattern
NEXT_INDEX=1
for dir in "${PARENT}/${PROJECT}-${AGENT}"-*/; do
  if [[ -d "$dir" ]]; then
    N="${dir##*-}"
    N="${N%/}"
    if [[ "$N" =~ ^[0-9]+$ ]] && (( N >= NEXT_INDEX )); then
      NEXT_INDEX=$((N + 1))
    fi
  fi
done

WORKTREE_PATH="${PARENT}/${PROJECT}-${AGENT}-${NEXT_INDEX}"
```

## Step 3.5: Lock Acquisition

Use `mkdir` for atomic lock (cross-platform: Linux, macOS, WSL).

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
LOCKDIR="${GIT_COMMON}/ai-worktree-spawn.lock"
MAX_RETRIES=3
LOCK_TIMEOUT=10  # seconds

acquire_lock() {
  local retries=0
  while ! mkdir "$LOCKDIR" 2>/dev/null; do
    # Check for stale lock
    if [[ -f "$LOCKDIR/pid" ]]; then
      local lock_age=$(( $(date +%s) - $(stat -c %Y "$LOCKDIR/pid" 2>/dev/null || stat -f %m "$LOCKDIR/pid" 2>/dev/null) ))
      if (( lock_age > LOCK_TIMEOUT )); then
        echo "Warning: Stale lock detected (age ${lock_age}s), removing"
        rm -rf "$LOCKDIR"
        continue
      fi
    fi
    retries=$((retries + 1))
    if (( retries >= MAX_RETRIES )); then
      echo "Error: Failed to acquire lock after $MAX_RETRIES retries"
      exit 2
    fi
    echo "Waiting for lock... retry $retries/$MAX_RETRIES"
    sleep 1
  done
  echo $$ > "$LOCKDIR/pid"
}

release_lock() {
  rm -rf "$LOCKDIR"
}

# Usage: wrap index computation + worktree creation
acquire_lock
trap release_lock EXIT
# ... Steps 3 through 6 run here ...
release_lock
trap - EXIT
```

## Step 4: Determine Branch Name

```bash
normalize_slug() {
  # Lowercase, replace non-alnum with hyphens, trim, max 30 chars
  echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-30
}

if [[ -n "${EXPLICIT_BRANCH:-}" ]]; then
  BRANCH="$EXPLICIT_BRANCH"
elif [[ -n "${TASK_SLUG:-}" ]]; then
  SLUG="$(normalize_slug "$TASK_SLUG")"
  BRANCH="wt/${AGENT}/${NEXT_INDEX}-${SLUG}"
else
  BRANCH="wt/${AGENT}/${NEXT_INDEX}"
fi
```

## Step 5: Determine Base Ref

```bash
resolve_base_ref() {
  local explicit_base="${1:-}"

  # Priority 1: explicit --base argument
  if [[ -n "$explicit_base" ]]; then
    if git rev-parse --verify --quiet "$explicit_base" >/dev/null 2>&1; then
      echo "$explicit_base"
      return
    fi
    echo "Error: Base ref not found: $explicit_base" >&2
    exit 1
  fi

  # Priority 2: origin/main
  if git rev-parse --verify --quiet "origin/main" >/dev/null 2>&1; then
    echo "origin/main"; return
  fi

  # Priority 3: main or master
  if git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
    echo "main"; return
  fi
  if git rev-parse --verify --quiet "master" >/dev/null 2>&1; then
    echo "master"; return
  fi

  # Priority 4: current HEAD
  echo "HEAD"
}

BASE_REF="$(resolve_base_ref "${BASE_OVERRIDE:-}")"
```

## Step 6: Create Worktree

```bash
# GIT_CRYPT_REPORT is consumed by Step 8 (skill report).
GIT_CRYPT_REPORT=""

if [[ "$GIT_CRYPT_ACTIVE" == true && -n "$GIT_CRYPT_KEY" ]]; then
    # ---- Auto-unlock path: 4-step sequence ----
    # Step 1: worktree add WITH command-level smudge bypass.
    # Why not --no-checkout: git-crypt unlock runs `git status` and rejects if
    # working tree is "not clean"; an empty (--no-checkout) worktree counts as
    # "all tracked files deleted" and unlock aborts. So we checkout ciphertext
    # cleanly first, then have unlock decrypt in place.
    if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
        git -c filter.git-crypt.smudge=cat -c filter.git-crypt.clean=cat \
            worktree add "${WORKTREE_PATH}" "${BRANCH}"
    else
        git -c filter.git-crypt.smudge=cat -c filter.git-crypt.clean=cat \
            worktree add -b "${BRANCH}" "${WORKTREE_PATH}" "${BASE_REF}"
    fi

    # Step 2: worktree-local TEMPORARY bypass so unlock's git-status check passes.
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.smudge cat
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.clean cat
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.required false

    # Step 3: git-crypt unlock -- decrypts working tree + stores key in worktree GIT_DIR.
    if (cd "${WORKTREE_PATH}" && git-crypt unlock "${GIT_CRYPT_KEY}"); then
        # Step 4: RESTORE filter to git-crypt so future commits encrypt properly.
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.smudge "git-crypt smudge"
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.clean "git-crypt clean"
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.required true
        GIT_CRYPT_REPORT="unlocked via ${GIT_CRYPT_KEY}"
    else
        # Unlock failed -- temp bypass from step 2 stays; worktree usable as binary.
        echo "Warning: git-crypt unlock failed with ${GIT_CRYPT_KEY}; staying on bypass"
        GIT_CRYPT_REPORT="disabled (unlock failed; encrypted files stay binary)"
    fi
else
    # ---- Bypass path (no git-crypt, or git-crypt active but no key file) ----
    if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
        git "${GIT_CRYPT_FLAGS[@]}" worktree add "${WORKTREE_PATH}" "${BRANCH}"
    else
        git "${GIT_CRYPT_FLAGS[@]}" worktree add -b "${BRANCH}" "${WORKTREE_PATH}" "${BASE_REF}"
    fi
    if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
        # Make bypass permanent in the worktree.
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.smudge cat
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.clean cat
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.required false
        git -C "${WORKTREE_PATH}" checkout -- . 2>/dev/null
        GIT_CRYPT_REPORT="disabled (no key; run from main repo: gc-export-key)"
    fi
fi
```

## Step 7: Log the Creation

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] SPAWN project=${PROJECT} agent=${AGENT} index=${NEXT_INDEX} path=${WORKTREE_PATH} branch=${BRANCH} base=${BASE_REF}" \
  >> "${GIT_COMMON}/ai-worktree-spawn.log"
```
