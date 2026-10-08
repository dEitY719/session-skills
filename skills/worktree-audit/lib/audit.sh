#!/usr/bin/env bash
# audit.sh -- non-destructive forensic collector for session:worktree-audit.
#
# Usage: bash audit.sh <checkout-path>
#
# Lists every entry `git status --porcelain` reports in <checkout-path> (plus
# symlinks nested inside wholly untracked dirs) and prints the evidence the
# model needs to judge it: type, size, mtime, symlink target and whether it
# survives, `git check-ignore -v` evidence (including the dir-only-pattern gap
# on symlinks), creation time vs the branch commit range, and mentions in
# tracked setup docs. It also counts unpushed commits, the other teardown
# block. It never deletes, edits, or stages anything in the checkout. HINT
# lines suggest a verdict; the verdict itself is the model's.
#
# Output: one record per line, `KIND:` then TAB-separated key=value fields.
# references/audit-contract.md is the full format.
#
# Exit codes: 0 audit completed (zero artifacts included); 1 bad parameters.
set -u

usage() { echo "Usage: bash audit.sh <checkout-path>" >&2; }

case "${1:-}" in
    -h | --help) usage; exit 0 ;;
    "") echo "Error: missing <checkout-path>." >&2; usage; exit 1 ;;
esac
[ "$#" -eq 1 ] || { echo "Error: expected exactly one argument." >&2; usage; exit 1; }
[ -d "$1" ] || { echo "Error: not a directory: $1" >&2; exit 1; }
top=$(git -C "$1" rev-parse --show-toplevel 2>/dev/null) ||
    { echo "Error: not a git checkout: $1" >&2; exit 1; }
cd "$top" || exit 1
gitdir=$(git rev-parse --absolute-git-dir)

# GNU stat first, BSD stat second. Never follows a symlink (lstat semantics).
mtime_epoch() { stat -c %Y "$1" 2>/dev/null || stat -f %m "$1" 2>/dev/null || echo 0; }
mtime_human() {
    local t
    t=$(stat -c %y "$1" 2>/dev/null) || t=$(stat -f %Sm "$1" 2>/dev/null) || t=-
    printf '%s' "${t%%.*}"
}
# du -sh of the entry itself (never a symlink's target), bounded to 5s when
# `timeout` exists; `?` on timeout or failure.
size_of() {
    local out rc
    if command -v timeout >/dev/null 2>&1; then
        out=$(timeout 5 du -sh -- "$1" 2>/dev/null); rc=$?
    else
        out=$(du -sh -- "$1" 2>/dev/null); rc=$?
    fi
    [ "$rc" -eq 124 ] && out=""
    if [ -n "$out" ]; then printf '%s' "${out%%$'\t'*}"; else printf '?'; fi
}
field() { printf '\t%s=%s' "$1" "$2"; }

# --- branch commit range ---------------------------------------------------
# Same base-ref order as worktree-spawn's resolve_base_ref.
branch=$(git symbolic-ref -q --short HEAD || echo "(detached)")
base_ref=""
for r in origin/main main master; do
    if git rev-parse -q --verify "$r^{commit}" >/dev/null; then base_ref=$r; break; fi
done
base=""
[ -n "$base_ref" ] && base=$(git merge-base HEAD "$base_ref" 2>/dev/null)
base_epoch=0
first="none" last="none" last_epoch=0
if [ -n "$base" ]; then
    base_epoch=$(git log -1 --format=%ct "$base")
    range=$(git log --format='%ct %ad' --date=iso "$base..HEAD")
    if [ -n "$range" ]; then
        read -r last_epoch last <<<"$range"
        first=${range##*$'\n'} first=${first#* }
    fi
fi
[ "$last_epoch" -gt 0 ] || last_epoch=$base_epoch

# Unpushed commits: the same `@{u}..HEAD` test as worktree-teardown's
# pre-flight; no upstream is not a block there, so it is reported as such.
unpushed=$(git rev-list --count '@{u}..HEAD' 2>/dev/null) || unpushed=none-upstream

# --- dir-only pattern probe ------------------------------------------------
# git refuses `check-ignore <link>/` ("beyond a symbolic link"), so a dir-only
# pattern such as `.venv/` is probed against a scratch work tree holding only
# copies of the checkout's .gitignore files. The scratch dir is ours; the
# checkout is never written. Built once, in this shell (never inside a $(...)
# subshell, where the assignment would be lost), and removed on exit.
mirror=""
trap '[ -z "$mirror" ] || rm -rf "$mirror"' EXIT
ensure_mirror() {
    local g
    [ -z "$mirror" ] || return 0
    mirror=$(mktemp -d) || { mirror=""; return 1; }
    git ls-files -z -co --exclude-standard -- ':(glob)**/.gitignore' |
        while IFS= read -r -d '' g; do
            mkdir -p "$mirror/$(dirname "$g")" && cp "$g" "$mirror/$g"
        done
}
probe_dir_pattern() { # <path> -> prints the matching rule, or nothing
    git -C "$mirror" --git-dir="$gitdir" --work-tree="$mirror" \
        check-ignore -v --no-index -- "$1/" 2>/dev/null | cut -f1
}

# Tracked setup docs only: an untracked file is never evidence for itself.
docs=()
while IFS= read -r -d '' d; do docs+=("$d"); done < <(
    git ls-files -z -- 'README*' setup.sh run.sh local-ci.sh Makefile 'scripts/*')

# --- artifacts -------------------------------------------------------------
count=0
report() { # <xy> <path>
    local xy=$1 p=$2 type target=- texists=- size me=0 mh=- ignore gap="" when
    local documented="" d searched=() base_name h hints=() weak=()
    count=$((count + 1))

    if [ -L "$p" ]; then
        type=symlink
        target=$(readlink "$p")
        if [ -e "$p" ]; then texists=yes; else texists=no; fi
    elif [ -d "$p" ]; then type=dir
    elif [ -e "$p" ]; then type="file"  # quoted: SC2209
    else type=missing
    fi
    size=-
    [ "$type" = missing ] || size=$(size_of "$p")
    [ "$type" = missing ] || { me=$(mtime_epoch "$p"); mh=$(mtime_human "$p"); }

    ignore=$(git check-ignore -v --no-index -- "$p" 2>/dev/null | cut -f1)
    if [ "$type" = symlink ] && [ -z "$ignore" ] && ensure_mirror; then
        gap=$(probe_dir_pattern "$p")
    fi

    when=unknown
    if [ "$me" -gt 0 ] && [ "$base_epoch" -gt 0 ]; then
        if [ "$me" -lt "$base_epoch" ]; then when=before-branch
        elif [ "$me" -le "$last_epoch" ]; then when=during-branch
        else when=after-last-commit
        fi
    fi

    # Whole-word match of the relative path, never the artifact itself.
    for d in ${docs[@]+"${docs[@]}"}; do
        case "$d" in "$p" | "$p"/*) ;; *) searched+=("$d") ;; esac
    done
    if [ "${#searched[@]}" -gt 0 ]; then
        documented=$(grep -lwF -e "$p" -- "${searched[@]}" 2>/dev/null |
            tr '\n' ',' | sed 's/,$//')
    fi

    printf 'ARTIFACT:'
    field path "$p"; field status "$xy"; field type "$type"; field size "$size"
    field mtime "$mh"; field mtime_epoch "$me"; field target "$target"
    field target_exists "$texists"
    field ignored_by "${ignore:-none}"; field when "$when"
    field documented_in "${documented:-none}"
    printf '\n'

    # --- hints (suggestions only) -------------------------------------------
    # Discard and preserve hints are for untracked entries only; a tracked
    # change is always a commit question. `weak` hints never suppress the
    # commit fallback for an entry created on this branch.
    base_name=$(basename "$p")
    if [ "$xy" != "??" ]; then
        hints+=("commit|tracked file with local changes")
    else
        [ -n "$gap" ] && hints+=("gitignore-gap|dir-only pattern $gap matches $p/ but not the symlink $p")
        if [ "$type" = symlink ]; then
            if [ "$texists" = yes ]; then
                hints+=("discard|symlink, target exists; remove the link only: rm $p")
            else
                hints+=("discard|dangling symlink; target $target is gone")
            fi
        fi
        case "$base_name" in
            node_modules | __pycache__ | .pytest_cache | .mypy_cache | .ruff_cache | \
                .venv | venv | *.lock)
                [ "$type" = symlink ] || hints+=("discard|regenerable cache or setup artifact ($base_name)") ;;
            dist | out | build)
                [ "$type" = symlink ] || weak+=("discard|build output name ($base_name); confirm nothing hand-written is inside") ;;
            logs | *.log | *.dump | *.sql | *.jsonl)
                hints+=("preserve|log or dump; may hold unique data") ;;
        esac
        [ -n "$documented" ] && weak+=("discard|mentioned in setup docs: $documented")
        if [ "${#hints[@]}" -eq 0 ]; then
            case "$when" in
                during-branch | after-last-commit)
                    hints+=("commit|untracked, created on this branch; possibly work product") ;;
                *) [ "${#weak[@]}" -gt 0 ] || hints+=("review|no pattern matched; read it before judging") ;;
            esac
        fi
    fi
    for h in ${hints[@]+"${hints[@]}"} ${weak[@]+"${weak[@]}"}; do
        printf 'HINT:'; field path "$p"; field suggest "${h%%|*}"; field reason "${h#*|}"
        printf '\n'
    done
}

while IFS= read -r -d '' rec <&3; do
    xy=${rec:0:2} p=${rec:3}
    case "$xy" in R* | C*) IFS= read -r -d '' _ <&3 ;; esac # skip rename source
    p=${p%/}
    report "$xy" "$p"
    # --untracked-files=normal collapses a wholly untracked dir; surface the
    # symlinks inside it (not followed, bounded depth, heavy trees skipped).
    if [ "$xy" = "??" ] && [ ! -L "$p" ] && [ -d "$p" ]; then
        while IFS= read -r -d '' n <&4; do
            report "??" "$n"
        done 4< <(find "$p" -mindepth 1 -maxdepth 4 \
            \( -name node_modules -o -name .git \) -prune -o -type l -print0 2>/dev/null)
    fi
done 3< <(git status --porcelain=v1 -z --untracked-files=normal)

if [ "$unpushed" != none-upstream ] && [ "$unpushed" -gt 0 ]; then
    printf 'HINT:'; field path -; field suggest push
    field reason "$unpushed unpushed commit(s) on $branch; teardown blocks until pushed (gh-pr:create or git push, never --force)"
    printf '\n'
fi

printf 'STATUS:'
field checkout "$top"; field branch "$branch"; field base "${base_ref:-none}"
field branch_first_commit "$first"; field branch_last_commit "$last"
field artifacts "$count"; field unpushed "$unpushed"
printf '\n'
exit 0
