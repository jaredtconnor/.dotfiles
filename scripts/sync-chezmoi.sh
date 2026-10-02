#!/usr/bin/env bash
# Pull canonical repositories, apply chezmoi, and summarize external updates.
#
#   (no flag)      prompt when a managed file was edited locally
#   --force        overwrite local edits
#   --unattended   what fleet-sync runs over SSH: never prompts, never
#                  overwrites a local edit. Everything else is applied; the
#                  edited files are left alone and listed, and it exits 3.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
PRIVATE_DIR="${PRIVATE_DOTFILES_DIR:-$HOME/.dotfiles-private}"
# Fixed path: the forced command and an interactive shell must agree on it.
LOCK="$HOME/.local/state/dotfiles-sync.lock"
FORCE=0
UNATTENDED=0

usage() {
    printf 'usage: %s [--force | --unattended]\n' "$0" >&2
    exit 2
}

[[ $# -le 1 ]] || usage
case "${1:-}" in
    "") ;;
    --force) FORCE=1 ;;
    --unattended) UNATTENDED=1 ;;
    *) usage ;;
esac

if [[ "$UNATTENDED" -eq 1 ]]; then
    # An SSH forced command starts with sshd's bare PATH.
    export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"
fi

short_sha() {
    git -C "$1" rev-parse --short=7 HEAD
}

sync_repo() {
    local label="$1"
    local path="$2"
    local before after output

    [[ -d "$path/.git" ]] || return 0
    before="$(short_sha "$path")"
    if ! output="$(git -C "$path" pull --ff-only origin main 2>&1)"; then
        printf '  %s: FAILED\n' "$label" >&2
        printf '%s\n' "$output" | sed 's/^/    /' >&2
        return 1
    fi
    after="$(short_sha "$path")"

    if [[ "$before" == "$after" ]]; then
        printf '  %s: current @ %s\n' "$label" "$after"
    else
        printf '  %s: updated %s -> %s\n' "$label" "$before" "$after"
    fi
}

render_external_inventory() {
    chezmoi execute-template <"$DOTFILES_DIR/home/.chezmoiexternal.toml.tmpl" |
        awk '
            /^\[".*"\]$/ {
                path = substr($0, 3, length($0) - 4)
                next
            }
            /^[[:space:]]*type[[:space:]]*=[[:space:]]*"git-repo"/ {
                print "git\t" path
                next
            }
            /^[[:space:]]*type[[:space:]]*=[[:space:]]*"archive"/ {
                print "archive\t" path
            }
        '
}

step() {
    if [[ -t 1 ]]; then
        printf '\n\033[1;34m==> %s\033[0m\n' "$1"
    else
        printf '\n==> %s\n' "$1"
    fi
}

# One sync at a time per host: a fleet-sync can land while `just sync` runs,
# and two pushes in a row start two fleet-syncs. The lock is a symlink whose
# target is the holder's pid: creating it is atomic and it is never without a
# pid (macOS has no flock). A holder that is gone, or whose pid now belongs to
# something else after a reboot, is stale; renaming the link first means only
# one waiter reclaims it.
acquire_lock() {
    local waited=0 holder
    mkdir -p "$(dirname "$LOCK")"
    until ln -s "$$" "$LOCK" 2>/dev/null; do
        holder="$(readlink "$LOCK" 2>/dev/null || true)"
        if [[ -n "$holder" ]] && ! ps -p "$holder" -o command= 2>/dev/null | grep -q sync-chezmoi; then
            mv "$LOCK" "$LOCK.$$" 2>/dev/null && rm -f "$LOCK.$$"
            continue
        fi
        if [[ "$waited" -eq 0 ]]; then
            printf 'waiting for another sync on this host (pid %s)\n' "${holder:-?}"
        elif [[ "$waited" -ge 900 ]]; then
            printf 'gave up after %ds waiting for %s\n' "$waited" "$LOCK" >&2
            exit 1
        fi
        sleep 5
        waited=$((waited + 5))
    done
}

acquire_lock
trap 'rm -f "$LOCK"' EXIT

step "Repositories"
sync_repo "dotfiles" "$DOTFILES_DIR"
sync_repo "private companion" "$PRIVATE_DIR"

init_args=(--no-tty --source "$DOTFILES_DIR")
# Externals are noisy but never prompt: refresh them non-interactively.
ext_args=(--refresh-externals=always --include=externals --force)
# Managed files may prompt on local divergence: applied separately, interactively.
managed_args=(--exclude=externals)
if [[ "$FORCE" -eq 1 || "$UNATTENDED" -eq 1 ]]; then
    managed_args+=(--no-tty --force)
fi
chezmoi init "${init_args[@]}"

inventory="$(mktemp)"
apply_output="$(mktemp)"
before_inventory="$(mktemp)"
trap 'rm -f "$inventory" "$apply_output" "$before_inventory" "$LOCK"' EXIT
render_external_inventory >"$inventory"

declare -a git_paths=()
archive_count=0
while IFS=$'\t' read -r kind path; do
    [[ -n "$path" ]] || continue
    if [[ "$kind" == "git" ]]; then
        git_paths+=("$path")
    else
        archive_count=$((archive_count + 1))
    fi
done <"$inventory"

for path in "${git_paths[@]}"; do
    if [[ -d "$HOME/$path/.git" ]]; then
        printf '%s\t%s\n' "$path" "$(short_sha "$HOME/$path")" >>"$before_inventory"
    else
        printf '%s\t-\n' "$path" >>"$before_inventory"
    fi
done

step "Externals"
external_total=$((${#git_paths[@]} + archive_count))
printf '  refreshing %d externals (this can take a while)...\n' "$external_total"
# Raw git fetch/diff output is captured and discarded on success; the per-repo
# summary below reports what actually changed. Show a live spinner meanwhile.
chezmoi apply "${ext_args[@]}" >"$apply_output" 2>&1 &
apply_pid=$!
if [[ -t 2 ]]; then
    spin='|/-\'
    i=0
    start=$SECONDS
    while kill -0 "$apply_pid" 2>/dev/null; do
        elapsed=$((SECONDS - start))
        last="$(tail -n1 "$apply_output" 2>/dev/null)"
        printf '\r\033[K  %s %3ds  %.50s' "${spin:i++%4:1}" "$elapsed" "$last" >&2
        sleep 0.5
    done
    printf '\r\033[K' >&2
fi
rc=0
wait "$apply_pid" || rc=$?
if [[ "$rc" -ne 0 ]]; then
    printf '  external refresh failed:\n' >&2
    sed 's/^/    /' "$apply_output" >&2
    exit 1
fi

updated=0
cloned=0
current=0
missing=0
changes=()
for path in "${git_paths[@]}"; do
    before="$(awk -F '\t' -v key="$path" '$1 == key { print $2; exit }' "$before_inventory")"
    if [[ ! -d "$HOME/$path/.git" ]]; then
        missing=$((missing + 1))
        changes+=("  $path: not present")
        continue
    fi
    after="$(short_sha "$HOME/$path")"
    if [[ "$before" == "-" ]]; then
        cloned=$((cloned + 1))
        changes+=("  $path: cloned @ $after")
    elif [[ "$before" != "$after" ]]; then
        commit_count="$(git -C "$HOME/$path" rev-list --count "$before..$after")"
        subject="$(git -C "$HOME/$path" log -1 --format=%s "$after")"
        updated=$((updated + 1))
        if [[ "$commit_count" -eq 1 ]]; then
            commit_label="commit"
        else
            commit_label="commits"
        fi
        changes+=("  $path: updated $before -> $after ($commit_count $commit_label)")
        changes+=("    $after $subject")
    else
        current=$((current + 1))
    fi
done

printf 'Externals: %d Git checked' "${#git_paths[@]}"
[[ "$updated" -gt 0 ]] && printf ', %d updated' "$updated"
[[ "$cloned" -gt 0 ]] && printf ', %d cloned' "$cloned"
[[ "$current" -gt 0 ]] && printf ', %d current' "$current"
[[ "$missing" -gt 0 ]] && printf ', %d unavailable' "$missing"
[[ "$archive_count" -gt 0 ]] && printf '; %d archives managed' "$archive_count"
printf '\n'
if [[ "${#changes[@]}" -gt 0 ]]; then
    printf '%s\n' "${changes[@]}"
fi

step "Managed files"
# Locally edited targets, for --unattended to leave alone. chezmoi status
# columns: 1 = target vs what chezmoi last wrote, 2 = target vs source. An
# edit needs both (one that already matches the source is harmless). A target
# chezmoi never wrote shows blank in column 1, so a pre-existing file that a
# new source entry would replace is caught by its missing entryState instead.
edited_targets() {
    local state line
    state="$(chezmoi state dump --format=json)"
    chezmoi status --exclude=externals,scripts | while IFS= read -r line; do
        if [[ "${line:0:1}" != " " && "${line:1:1}" != " " ]]; then
            printf '%s\n' "${line:3}"
        elif [[ "${line:0:2}" == " M" ]] && ! grep -qF "\"$HOME/${line:3}\":" <<<"$state"; then
            printf '%s\n' "${line:3}"
        fi
    done
}

diverged=""
if [[ "$UNATTENDED" -eq 1 ]]; then
    diverged="$(edited_targets)"
fi
if [[ -n "$diverged" ]]; then
    # Apply every other target one at a time (not recursing, so a parent
    # directory doesn't bring an edited file back in), then the scripts.
    # run_before_ scripts therefore run after the files here; they are all
    # run_once installers, which only rerun when their content changes.
    targets=()
    while IFS= read -r target; do
        grep -qxF -e "$target" <<<"$diverged" || targets+=("$HOME/$target")
    done < <(chezmoi managed --exclude=externals,scripts)
    # With no targets, chezmoi would apply everything, the edits included.
    if [[ ${#targets[@]} -gt 0 ]] && ! chezmoi apply "${managed_args[@]}" --recursive=false "${targets[@]}"; then
        printf '  chezmoi apply failed.\n' >&2
        exit 1
    fi
    if ! chezmoi apply --include=scripts --no-tty --force; then
        printf '  chezmoi apply failed.\n' >&2
        exit 1
    fi
    printf 'Edited locally, so left alone (run "just sync" on this host to resolve):\n' >&2
    sed 's|^|  ~/|' <<<"$diverged" >&2
    exit 3
fi
# Foreground so chezmoi's overwrite/skip prompt is answerable on divergence;
# quiet by design (no external git noise). run_ scripts stream their output.
if ! chezmoi apply "${managed_args[@]}"; then
    printf '  chezmoi apply failed.\n' >&2
    exit 1
fi
