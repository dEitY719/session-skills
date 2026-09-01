# Bash Commands — implementation details for each execution step

## Step 0: Dry-run Gate

If `--dry-run`, print the plan and stop (no destructive action).

```bash
if [[ "${DRY_RUN:-false}" == true ]]; then
  echo "[DRY-RUN] Plan:"
  echo "  Worktree: $1"
  echo "  Actions:  preflight -> worktree remove -> sync main -> branch delete"
  echo "No changes made."
  exit 0
fi
```

## Step 1: Validate — Must Be in Main Repo, NOT a Worktree

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_DIR="$(git rev-parse --git-dir)"

if [[ "$GIT_DIR" != "$GIT_COMMON" ]]; then
  echo "Error: You are inside a worktree. Run this from the main repo."
  echo "  cd $(dirname "$GIT_COMMON") && /session:worktree-teardown <worktree-path>"
  exit 1
fi

# Require worktree path argument
WORKTREE_ARG="$1"
if [[ -z "$WORKTREE_ARG" ]]; then
  echo "Error: Missing worktree path argument."
  echo ""
  echo "Usage: /session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]"
  echo ""
  echo "Active worktrees:"
  git worktree list
  exit 1
fi
```

## Step 2: Resolve Worktree Info

```bash
# Resolve to absolute path
WORKTREE_PATH="$(realpath "$WORKTREE_ARG")"
WORKTREE_NAME="$(basename "$WORKTREE_PATH")"

# Verify it's a known worktree and extract branch
BRANCH="$(git worktree list --porcelain | awk -v wp="$WORKTREE_PATH" '
  /^worktree / { wt = substr($0, 10) }
  /^branch /   { if (wt == wp) { sub(/^branch refs\/heads\//, ""); print } }
')"

if [[ -z "$BRANCH" ]]; then
  echo "Error: '$WORKTREE_PATH' is not a known worktree of this repo."
  echo ""
  echo "Active worktrees:"
  git worktree list
  exit 1
fi
```

## Step 3: Pre-flight Checks

```bash
preflight_check() {
  local worktree_path="$1"
  local force="${2:-false}"

  # Check for uncommitted changes in the target worktree
  if ! git -C "$worktree_path" diff --quiet || ! git -C "$worktree_path" diff --cached --quiet; then
    if [[ "$force" == true ]]; then
      echo "Warning: Discarding uncommitted changes (--force)"
    else
      echo "Error: Uncommitted changes detected in $worktree_path."
      echo "  Commit, stash, or use --force to discard."
      exit 1
    fi
  fi

  # Unpushed commits (only commits in HEAD that are NOT in upstream)
  local unpushed
  unpushed="$(git -C "$worktree_path" log --oneline @{u}..HEAD 2>/dev/null)"

  if [[ -n "$unpushed" ]]; then
    if [[ "$force" == true ]]; then
      echo "Warning: Discarding unpushed commits (--force)"
    else
      echo "Error: Unpushed commits detected."
      echo "  Push first, or use --force to discard."
      exit 1
    fi
  fi
}

preflight_check "$WORKTREE_PATH" "${FORCE:-false}"
```

## Step 4: Remove Worktree

```bash
if ! git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
  if [[ "${FORCE:-false}" == true ]]; then
    echo "Warning: Force-removing worktree"
    git worktree remove --force "$WORKTREE_PATH"
  else
    echo "Error: Cannot remove worktree. It may have uncommitted changes."
    echo "  Use --force to override."
    exit 1
  fi
fi
git worktree prune
echo "Worktree removed: $WORKTREE_PATH"
```

## Step 5: Sync Main

Sync main BEFORE branch delete so `git branch -d` can verify merge status.

```bash
# Resolve main branch name
resolve_main_branch() {
  if git rev-parse --verify --quiet "main" >/dev/null 2>&1; then
    echo "main"
  elif git rev-parse --verify --quiet "master" >/dev/null 2>&1; then
    echo "master"
  else
    echo "Error: Neither 'main' nor 'master' branch found." >&2
    exit 1
  fi
}

MAIN_BRANCH="$(resolve_main_branch)"
git checkout "$MAIN_BRANCH"

# Pull with conflict detection
if ! git pull origin "$MAIN_BRANCH"; then
  echo "Conflict detected during pull."
  echo "Attempting to resolve..."
  # List conflicting files
  git diff --name-only --diff-filter=U
  # AI agent should analyze and resolve conflicts here
  # If resolved:
  #   git add <resolved-files>
  #   git commit -m "chore: resolve merge conflicts after teardown"
  # If unresolvable:
  #   echo "Error: Cannot auto-resolve conflicts. Manual intervention needed."
fi
```

## Step 6: Delete Branch

Runs after sync so local main contains the merge commit.

```bash
delete_branch() {
  local branch="$1"
  local keep="${KEEP_BRANCH:-false}"

  if [[ "$keep" == true ]]; then
    echo "Branch kept: $branch (--keep-branch)"
    return
  fi

  if git branch -d "$branch" 2>/dev/null; then
    echo "Branch deleted: $branch"
  else
    if [[ "${FORCE:-false}" == true ]]; then
      git branch -D "$branch"
      echo "Branch force-deleted: $branch (was not fully merged)"
    else
      echo "Warning: Branch '$branch' not fully merged into main."
      echo "  Use --force to delete anyway, or --keep-branch to keep it."
    fi
  fi
}

delete_branch "$BRANCH"
```

## Step 7: Log

```bash
GIT_COMMON="$(git rev-parse --git-common-dir)"
echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] TEARDOWN worktree=${WORKTREE_NAME} branch=${BRANCH} path=${WORKTREE_PATH}" \
  >> "${GIT_COMMON}/ai-worktree-spawn.log"
```
