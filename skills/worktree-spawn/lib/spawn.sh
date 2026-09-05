#!/usr/bin/env bash
# skills/worktree-spawn/lib/spawn.sh
#
# session:worktree-spawn's executable half. Everything deterministic lives here
# so it is never re-transcribed per invocation; SKILL.md keeps only the
# judgment (agent override, Korean task-slug translation, the git-crypt
# staging caveat, the final cd).
#
# Steps, in the order they run:
#   1    validate preconditions -- git repo, NOT inside a worktree, writable parent
#   2    detect the AI agent                (references/agent-detection.md)
#   1.5  detect git-crypt, resolve key file (references/options-and-errors.md)
#   3.5  acquire the spawn lock             ($GIT_COMMON/ai-worktree-spawn.lock)
#   3    project name + next free index     (scan of {project}-{agent}-N)
#   4    branch name
#   5    base ref
#   --dry-run gate: plan printed here, nothing created
#   6    git worktree add, with git-crypt auto-unlock or bypass
#   7    append the audit trail             ($GIT_COMMON/ai-worktree-spawn.log)
#   8    print the [OK] report
#
# Usage:
#   spawn.sh [--ai <name>] [--task <slug>] [--base <ref>] [--dry-run] [<branch>]
# Exit: 0 = worktree created, or --dry-run plan printed
#       1 = precondition failure, unknown option, bad base ref, git failure
#       2 = lock acquisition failed after MAX_RETRIES

set -euo pipefail

usage() {
    cat <<'EOF'
spawn.sh -- session:worktree-spawn's deterministic half

Usage:
  spawn.sh [--ai <name>] [--task <slug>] [--base <ref>] [--dry-run] [<branch>]

  --ai <name>     Override agent detection.
  --task <slug>   Append a slug to the branch name. English only -- the caller
                  translates; this script only normalizes (lowercase, hyphens,
                  30 chars).
  --base <ref>    Base ref. Default: origin/main > main/master > HEAD.
  --dry-run       Print the plan (agent, path, branch, base, command) and stop.
  <branch>        Explicit branch name instead of wt/<agent>/<N>.

Exit: 0 = created or plan printed, 1 = precondition/git failure, 2 = lock failed.
EOF
}

AGENT_OVERRIDE=""
TASK_SLUG=""
BASE_OVERRIDE=""
EXPLICIT_BRANCH=""
DRY_RUN=false

while [[ $# -gt 0 ]]; do
    case "$1" in
        -h|--help|help) usage; exit 0 ;;
        --ai)           AGENT_OVERRIDE="${2:-}"; shift 2 ;;
        --task)         TASK_SLUG="${2:-}"; shift 2 ;;
        --base)         BASE_OVERRIDE="${2:-}"; shift 2 ;;
        --dry-run)      DRY_RUN=true; shift ;;
        --*)            echo "Error: Unknown option: $1" >&2; usage >&2; exit 1 ;;
        *)              EXPLICIT_BRANCH="$1"; shift ;;
    esac
done

# ---- Step 1: Validate preconditions -----------------------------------------

if ! TOPLEVEL="$(git rev-parse --show-toplevel 2>/dev/null)"; then
    echo "Error: Not a git repository."
    exit 1
fi

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
PARENT="$(dirname "$TOPLEVEL")"
test -w "$PARENT" || { echo "Error: Permission denied: $PARENT"; exit 1; }

# ---- Step 2: Detect AI agent ------------------------------------------------

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

AGENT="$(detect_ai_agent "$AGENT_OVERRIDE")"

# ---- Step 1.5: Detect git-crypt and resolve key file ------------------------

GIT_CRYPT_ACTIVE=false
if git config --get filter.git-crypt.smudge >/dev/null 2>&1; then
    GIT_CRYPT_ACTIVE=true
fi

# Key file priority chain:
# 1) $GIT_CRYPT_KEY_FILE  2) ~/.config/git-crypt/<project>.key  3) ~/.config/git-crypt/default.key
GIT_CRYPT_KEY=""
PROJECT="$(basename "$TOPLEVEL")"
if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
    for candidate in \
        "${GIT_CRYPT_KEY_FILE:-}" \
        "${HOME}/.config/git-crypt/${PROJECT}.key" \
        "${HOME}/.config/git-crypt/default.key"; do
        if [[ -n "$candidate" && -r "$candidate" ]]; then
            GIT_CRYPT_KEY="$candidate"
            break
        fi
    done
fi

# The `worktree add` itself always bypasses the smudge filter when git-crypt is
# active -- with a key so the ciphertext checks out cleanly for `git-crypt
# unlock` to decrypt in place (an empty --no-checkout tree reads as "all tracked
# files deleted" and unlock aborts), without one because the bypass is the whole
# fallback. What differs is only what Step 6 does afterwards.
GIT=(git)
if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
    GIT+=(-c filter.git-crypt.smudge=cat -c filter.git-crypt.clean=cat)
fi

# ---- Step 3.5: Lock acquisition ---------------------------------------------
# mkdir is the atomic primitive that works on Linux, macOS and WSL alike.

LOCKDIR="${GIT_COMMON}/ai-worktree-spawn.lock"
MAX_RETRIES=3
LOCK_TIMEOUT=10  # seconds

acquire_lock() {
    local retries=0
    local lock_mtime lock_age
    while ! mkdir "$LOCKDIR" 2>/dev/null; do
        # Check for stale lock
        if [[ -f "$LOCKDIR/pid" ]]; then
            lock_mtime="$(stat -c %Y "$LOCKDIR/pid" 2>/dev/null || stat -f %m "$LOCKDIR/pid" 2>/dev/null || echo 0)"
            lock_age=$(( $(date +%s) - lock_mtime ))
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
    echo "$$" > "$LOCKDIR/pid"
}

release_lock() {
    rm -rf "$LOCKDIR"
}

acquire_lock
trap release_lock EXIT

# ---- Step 3: Compute project name and index ---------------------------------

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

# ---- Step 4: Determine branch name ------------------------------------------

normalize_slug() {
    # Lowercase, replace non-alnum with hyphens, trim, max 30 chars
    echo "$1" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/--*/-/g; s/^-//; s/-$//' | cut -c1-30
}

if [[ -n "$EXPLICIT_BRANCH" ]]; then
    BRANCH="$EXPLICIT_BRANCH"
elif [[ -n "$TASK_SLUG" ]]; then
    SLUG="$(normalize_slug "$TASK_SLUG")"
    BRANCH="wt/${AGENT}/${NEXT_INDEX}-${SLUG}"
else
    BRANCH="wt/${AGENT}/${NEXT_INDEX}"
fi

# ---- Step 5: Determine base ref ---------------------------------------------

resolve_base_ref() {
    local explicit_base="${1:-}"
    local ref

    # Priority 1: explicit --base argument
    if [[ -n "$explicit_base" ]]; then
        if git rev-parse --verify --quiet "$explicit_base" >/dev/null 2>&1; then
            echo "$explicit_base"
            return
        fi
        echo "Error: Base ref not found: $explicit_base" >&2
        exit 1
    fi

    # Priority 2-3: origin/main, then main or master
    for ref in origin/main main master; do
        if git rev-parse --verify --quiet "$ref" >/dev/null 2>&1; then
            echo "$ref"; return
        fi
    done

    # Priority 4: current HEAD
    echo "HEAD"
}

# `exit 1` above fires inside the command substitution's subshell; set -e turns
# that non-zero status into a stop here, which is the intended behaviour.
BASE_REF="$(resolve_base_ref "$BASE_OVERRIDE")"

# The one `git worktree add` shape, built before the gate so --dry-run prints
# the exact command Step 6 runs rather than a hand-kept copy of it.
if git show-ref --verify --quiet "refs/heads/${BRANCH}"; then
    ADD_ARGS=(worktree add "${WORKTREE_PATH}" "${BRANCH}")
else
    ADD_ARGS=(worktree add -b "${BRANCH}" "${WORKTREE_PATH}" "${BASE_REF}")
fi

# ---- --dry-run gate ---------------------------------------------------------

if [[ "$DRY_RUN" == true ]]; then
    echo "[DRY-RUN] Plan:"
    echo "  Agent:   ${AGENT}"
    echo "  Path:    ${WORKTREE_PATH}"
    echo "  Branch:  ${BRANCH}"
    echo "  Base:    ${BASE_REF}"
    echo "  Command: ${GIT[*]} ${ADD_ARGS[*]}"
    echo "No changes made."
    exit 0
fi

# ---- Step 6: Create worktree ------------------------------------------------
# GIT_CRYPT_REPORT is consumed by the Step 8 report.

GIT_CRYPT_REPORT=""

"${GIT[@]}" "${ADD_ARGS[@]}"

if [[ "$GIT_CRYPT_ACTIVE" == true ]]; then
    # Worktree-local bypass. On the unlock path it is temporary, and only there
    # so `git-crypt unlock`'s own `git status` check passes; with no key it is
    # the permanent fallback.
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.smudge cat
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.clean cat
    git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.required false

    if [[ -z "$GIT_CRYPT_KEY" ]]; then
        git -C "${WORKTREE_PATH}" checkout -- . 2>/dev/null || true
        GIT_CRYPT_REPORT="disabled (no key; run from main repo: gc-export-key)"
    elif (cd "${WORKTREE_PATH}" && git-crypt unlock "${GIT_CRYPT_KEY}"); then
        # unlock decrypted the tree and stored the key in the worktree GIT_DIR;
        # RESTORE the filter to git-crypt so future commits encrypt properly.
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.smudge "git-crypt smudge"
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.clean "git-crypt clean"
        git -C "${WORKTREE_PATH}" config --worktree filter.git-crypt.required true
        GIT_CRYPT_REPORT="unlocked via ${GIT_CRYPT_KEY}"
    else
        # Unlock failed -- the bypass above stays; worktree usable as binary.
        echo "Warning: git-crypt unlock failed with ${GIT_CRYPT_KEY}; staying on bypass"
        GIT_CRYPT_REPORT="disabled (unlock failed; encrypted files stay binary)"
    fi
fi

release_lock
trap - EXIT

# ---- Step 7: Log the creation -----------------------------------------------

echo "[$(date +%Y-%m-%dT%H:%M:%S%z)] SPAWN project=${PROJECT} agent=${AGENT} index=${NEXT_INDEX} path=${WORKTREE_PATH} branch=${BRANCH} base=${BASE_REF}" \
    >> "${GIT_COMMON}/ai-worktree-spawn.log"

# ---- Step 8: Report ---------------------------------------------------------

echo "[OK] Worktree ready"
echo "  Path:   ${WORKTREE_PATH}"
echo "  Branch: ${BRANCH}"
echo "  Base:   ${BASE_REF}"
if [[ -n "$GIT_CRYPT_REPORT" ]]; then
    echo "  git-crypt: ${GIT_CRYPT_REPORT}"
fi
echo "  Teardown: git push -u origin ${BRANCH} && git worktree remove ${WORKTREE_PATH} && git branch -d ${BRANCH}"
echo "  cd ${WORKTREE_PATH}"
