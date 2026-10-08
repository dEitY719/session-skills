#!/usr/bin/env bash
# audit.sh -- non-destructive forensic collector for session:worktree-audit.
#
# Usage: bash audit.sh <checkout-path>
#
# Lists every entry `git status --porcelain` reports in <checkout-path> and
# prints the evidence the model needs to judge it: type, size, mtime, symlink
# target and whether it survives, `git check-ignore -v` evidence (including the
# dir-only-pattern gap on symlinks), creation time vs the branch commit range,
# and mentions in setup docs. It never deletes, edits, or stages anything in the
# checkout. HINT lines suggest a verdict; the verdict itself is the model's.
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
size_of() { du -sh "$@" 2>/dev/null | cut -f1; }
field() { printf '\t%s=%s' "$1" "$2"; }

# --- branch commit range ---------------------------------------------------
branch=$(git symbolic-ref -q --short HEAD || echo "(detached)")
base_ref=""
for r in main master origin/main origin/master; do
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

# --- dir-only pattern probe ------------------------------------------------
# git refuses `check-ignore <link>/` ("beyond a symbolic link"), so a dir-only
# pattern such as `.venv/` is probed against a scratch work tree holding only
# copies of the checkout's .gitignore files. The scratch dir is ours; the
# checkout is never written. Built once, on the first symlink that needs it.
mirror=""
probe_dir_pattern() { # <path> -> prints the matching rule, or nothing
    local g
    if [ -z "$mirror" ]; then
        mirror=$(mktemp -d) || return 0
        git ls-files -z -co --exclude-standard -- ':(glob)**/.gitignore' |
            while IFS= read -r -d '' g; do
                mkdir -p "$mirror/$(dirname "$g")" && cp "$g" "$mirror/$g"
            done
    fi
    git -C "$mirror" --git-dir="$gitdir" --work-tree="$mirror" \
        check-ignore -v --no-index -- "$1/" 2>/dev/null | cut -f1
}

docs=()
for d in README* setup.sh run.sh local-ci.sh Makefile scripts/*; do
    [ -f "$d" ] && docs+=("$d")
done

# --- artifacts -------------------------------------------------------------
count=0
while IFS= read -r -d '' rec <&3; do
    xy=${rec:0:2} p=${rec:3}
    case "$xy" in R* | C*) IFS= read -r -d '' _ <&3 ;; esac # skip rename source
    p=${p%/}
    count=$((count + 1))
    hints=()

    target=- texists=- tsize=-
    if [ -L "$p" ]; then
        type=symlink
        target=$(readlink "$p")
        if [ -e "$p" ]; then texists=yes; tsize=$(size_of -L "$p"); else texists=no; fi
    elif [ -d "$p" ]; then type=dir
    elif [ -e "$p" ]; then type="file"  # quoted: SC2209
    else type=missing
    fi
    size=-
    [ "$type" = missing ] || size=$(size_of "$p")
    me=0 mh=-
    [ "$type" = missing ] || { me=$(mtime_epoch "$p"); mh=$(mtime_human "$p"); }

    ignore=$(git check-ignore -v --no-index -- "$p" 2>/dev/null | cut -f1)
    gap=""
    if [ "$type" = symlink ] && [ -z "$ignore" ]; then
        gap=$(probe_dir_pattern "$p")
    fi

    when=unknown
    if [ "$me" -gt 0 ] && [ "$base_epoch" -gt 0 ]; then
        if [ "$me" -lt "$base_epoch" ]; then when=before-branch
        elif [ "$me" -le "$last_epoch" ]; then when=during-branch
        else when=after-last-commit
        fi
    fi

    documented=""
    if [ "${#docs[@]}" -gt 0 ]; then
        documented=$(grep -lF -e "$p" -e "$(basename "$p")" -- "${docs[@]}" 2>/dev/null |
            tr '\n' ',' | sed 's/,$//')
    fi

    printf 'ARTIFACT:'
    field path "$p"; field status "$xy"; field type "$type"; field size "$size"
    field mtime "$mh"; field mtime_epoch "$me"; field target "$target"
    field target_exists "$texists"; field target_size "$tsize"
    field ignored_by "${ignore:-none}"; field when "$when"
    field documented_in "${documented:-none}"
    printf '\n'

    # --- hints (suggestions only) -------------------------------------------
    base_name=$(basename "$p")
    if [ "$xy" != "??" ]; then
        hints+=("commit|tracked file with local changes")
    elif [ -n "$gap" ]; then
        hints+=("gitignore-gap|dir-only pattern $gap matches $p/ but not the symlink $p")
    fi
    if [ "$type" = symlink ]; then
        if [ "$texists" = yes ]; then
            hints+=("discard|symlink, target exists; remove the link only: rm $p")
        else
            hints+=("discard|dangling symlink; target $target is gone")
        fi
    fi
    case "$base_name" in
        node_modules | dist | out | build | __pycache__ | .pytest_cache | .mypy_cache | \
            .ruff_cache | .venv | venv | *.lock)
            [ "$type" = symlink ] || hints+=("discard|regenerable cache or setup artifact ($base_name)") ;;
        logs | *.log | *.dump | *.sql | *.jsonl)
            hints+=("preserve|log or dump; may hold unique data") ;;
    esac
    [ -n "$documented" ] && hints+=("discard|mentioned in setup docs: $documented")
    if [ "${#hints[@]}" -eq 0 ]; then
        case "$when" in
            during-branch | after-last-commit)
                hints+=("commit|untracked, created on this branch; possibly work product") ;;
            *) hints+=("review|no pattern matched; read it before judging") ;;
        esac
    fi
    for h in "${hints[@]}"; do
        printf 'HINT:'; field path "$p"; field suggest "${h%%|*}"; field reason "${h#*|}"
        printf '\n'
    done
done 3< <(git status --porcelain=v1 -z --untracked-files=normal)
[ -z "$mirror" ] || rm -rf "$mirror"

printf 'STATUS:'
field checkout "$top"; field branch "$branch"; field base "${base_ref:-none}"
field branch_first_commit "$first"; field branch_last_commit "$last"
field artifacts "$count"
printf '\n'
exit 0
