#!/usr/bin/env bash
# skills/worktree-teardown/lib/teardown.sh
#
# session:worktree-teardown's executable half -- the destructive skill in this
# plugin. The Step 3 pre-flight (uncommitted changes / unpushed commits) is the
# work-loss guard: it lives here, as real code, rather than as bash transcribed
# out of a Markdown reference on every invocation. A transcription slip in that
# guard does not fail loudly, it deletes work.
#
# Steps, in the order they run:
#   1  validate -- must run from the MAIN repo, never from inside a worktree
#   2  resolve worktree path + branch from `git worktree list --porcelain`
#   0  --dry-run gate, placed after resolution so the plan names the real branch
#   3  pre-flight work-loss guard -- stop unless --force
#   4  git worktree remove (+ prune)
#   5  sync main BEFORE the branch delete, so `git branch -d` can verify merge status
#   6  git branch -d  (skipped by --keep-branch, escalated to -D by --force)
#   7  append TEARDOWN to $GIT_COMMON/ai-worktree-spawn.log
#   8  print the [OK] report
#
# Usage:
#   teardown.sh <worktree-path> [--force] [--keep-branch] [--dry-run]
# Exit: 0 = teardown complete, or --dry-run plan printed
#       1 = validation failure, unknown worktree, pre-flight block, or removal failure
#
# On a non-zero exit the caller (SKILL.md Step 4) turns this script's stderr
# into the structured [FAIL] verdict; the Error: lines below are that detail.

set -euo pipefail

usage() {
    cat <<'EOF'
teardown.sh -- session:worktree-teardown's deterministic half

Usage:
  teardown.sh <worktree-path> [--force] [--keep-branch] [--dry-run]

  <worktree-path>  Worktree to remove (required). Run from the main repo.
  --force          User's explicit override of the pre-flight work-loss guard:
                   discards uncommitted changes and unpushed commits, force-
                   removes the worktree, force-deletes an unmerged branch.
  --keep-branch    Remove the worktree but keep its branch.
  --dry-run        Print the plan and stop.

Exit: 0 = complete or plan printed, 1 = validation / pre-flight / removal failure.
EOF
}

WORKTREE_ARG=""
FORCE=false
KEEP_BRANCH=false
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|help) usage; exit 0 ;;
        --force)        FORCE=true; shift ;;
        --keep-branch)  KEEP_BRANCH=true; shift ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --*)            echo "Error: Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)              WORKTREE_ARG="$1"; shift ;;
    esac
done

# ---- Step 1: Validate -- must be in the main repo, NOT a worktree -----------

GIT_COMMON="$(git rev-parse --git-common-dir)"
GIT_DIR="$(git rev-parse --git-dir)"

if [[ "$GIT_DIR" != "$GIT_COMMON" ]]; then
    echo "Error: You are inside a worktree. Run this from the main repo."
    echo "  cd $(dirname "$GIT_COMMON") && /session:worktree-teardown <worktree-path>"
    exit 1
fi

if [[ -z "$WORKTREE_ARG" ]]; then
    echo "Error: Missing worktree path argument."
    echo ""
    echo "Usage: /session:worktree-teardown <worktree-path> [--force] [--keep-branch] [--dry-run]"
    echo ""
    echo "Active worktrees:"
    git worktree list
    exit 1
fi

# ---- Step 2: Resolve worktree info ------------------------------------------

WORKTREE_PATH="$(realpath "$WORKTREE_ARG")"
WORKTREE_NAME="$(basename "$WORKTREE_PATH")"

# Verify it is a known worktree and extract the branch checked out there.
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

# ---- Step 0: Dry-run gate ---------------------------------------------------

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Plan:"
    echo "  Worktree: $WORKTREE_PATH"
    echo "  Branch:   $BRANCH"
    echo "  Actions:  preflight -> worktree remove -> sync main -> branch delete"
    echo "No changes made."
    exit 0
fi

# ---- Step 3: Pre-flight checks (the work-loss guard) ------------------------

preflight_check() {
    local worktree_path="$1"
    local force="${2:-false}"
    local unpushed

    # Uncommitted changes in the target worktree -- worktree-local, so both the
    # unstaged and the staged diff have to be clean.
    if ! git -C "$worktree_path" diff --quiet || ! git -C "$worktree_path" diff --cached --quiet; then
        if [[ "$force" == true ]]; then
            echo "Warning: Discarding uncommitted changes (--force)"
        else
            echo "Error: Uncommitted changes detected in $worktree_path."
            echo "  Commit, stash, or use --force to discard."
            exit 1
        fi
    fi

    # Unpushed commits (only commits in HEAD that are NOT in upstream).
    # `|| true`: no upstream configured makes @{u} fail, which is not a block.
    unpushed="$(git -C "$worktree_path" log --oneline '@{u}..HEAD' 2>/dev/null || true)"

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

preflight_check "$WORKTREE_PATH" "$FORCE"

# ---- Step 4: Remove worktree ------------------------------------------------

if ! git worktree remove "$WORKTREE_PATH" 2>/dev/null; then
    if [[ "$FORCE" == true ]]; then
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

# ---- Step 5: Sync main ------------------------------------------------------
# BEFORE the branch delete, so `git branch -d` can verify merge status.

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

MAIN_STATUS="up to date with origin/${MAIN_BRANCH}"
if ! git pull origin "$MAIN_BRANCH"; then
    # Hand the conflict back to the AI agent: list the files and keep going.
    # `git branch -d` below stays safe -- it refuses an unmerged branch.
    echo "Conflict detected during pull."
    echo "Attempting to resolve..."
    git diff --name-only --diff-filter=U
    MAIN_STATUS="pull failed -- resolve before continuing (see output above)"
fi

# ---- Step 6: Delete branch --------------------------------------------------

BRANCH_STATUS=""

delete_branch() {
    local branch="$1"

    if [[ "$KEEP_BRANCH" == true ]]; then
        echo "Branch kept: $branch (--keep-branch)"
        BRANCH_STATUS="kept"
        return
    fi

    if git branch -d "$branch" 2>/dev/null; then
        echo "Branch deleted: $branch"
        BRANCH_STATUS="deleted"
    else
        if [[ "$FORCE" == true ]]; then
            git branch -D "$branch"
            echo "Branch force-deleted: $branch (was not fully merged)"
            BRANCH_STATUS="force-deleted"
        else
            echo "Warning: Branch '$branch' not fully merged into $MAIN_BRANCH."
            echo "  Use --force to delete anyway, or --keep-branch to keep it."
            BRANCH_STATUS="kept (not fully merged)"
        fi
    fi
}

delete_branch "$BRANCH"

# ---- Step 7: Log ------------------------------------------------------------

echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] TEARDOWN worktree=${WORKTREE_NAME} branch=${BRANCH} path=${WORKTREE_PATH}" \
    >> "${GIT_COMMON}/ai-worktree-spawn.log"

# ---- Step 8: Report ---------------------------------------------------------
# The Note is unconditional: the outer shell's cwd is undetectable from here.

MAIN_REPO="$(git rev-parse --show-toplevel)"

echo "[OK] Teardown complete"
echo "  Removed:  ${WORKTREE_PATH}"
echo "  Branch:   ${BRANCH} (${BRANCH_STATUS})"
echo "  Now on:   ${MAIN_BRANCH} (${MAIN_STATUS})"
echo ""
echo "  Note: if your outer shell was cd'd inside the removed worktree, run"
echo "  \`cd ${MAIN_REPO}\` there now to avoid \`getcwd: cannot access parent"
echo "  directories\` errors from zsh/pyenv/p10k."
