#!/usr/bin/env bash
# Pull canonical repositories, apply chezmoi, and summarize external updates.
set -euo pipefail

DOTFILES_DIR="${DOTFILES_DIR:-$HOME/.dotfiles}"
PRIVATE_DIR="${PRIVATE_DOTFILES_DIR:-$HOME/.dotfiles-private}"
FORCE=0

if [[ "${1:-}" == "--force" ]]; then
    FORCE=1
elif [[ $# -gt 0 ]]; then
    printf 'usage: %s [--force]\n' "$0" >&2
    exit 2
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

step "Repositories"
sync_repo "dotfiles" "$DOTFILES_DIR"
sync_repo "private companion" "$PRIVATE_DIR"

init_args=(--no-tty --source "$DOTFILES_DIR")
# Externals are noisy but never prompt: refresh them non-interactively.
ext_args=(--refresh-externals=always --include=externals --force)
# Managed files may prompt on local divergence: applied separately, interactively.
managed_args=(--exclude=externals)
if [[ "$FORCE" -eq 1 ]]; then
    managed_args+=(--no-tty --force)
fi
chezmoi init "${init_args[@]}"

inventory="$(mktemp)"
apply_output="$(mktemp)"
before_inventory="$(mktemp)"
trap 'rm -f "$inventory" "$apply_output" "$before_inventory"' EXIT
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
external_total=$(( ${#git_paths[@]} + archive_count ))
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
# Foreground so chezmoi's overwrite/skip prompt is answerable on divergence;
# quiet by design (no external git noise). run_ scripts stream their output.
if ! chezmoi apply "${managed_args[@]}"; then
    printf '  chezmoi apply failed.\n' >&2
    exit 1
fi
