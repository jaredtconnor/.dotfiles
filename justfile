# Dotfiles — chezmoi-managed
#
# Common commands:
#   just sync       - Apply chezmoi locally
#   just sync-all   - Force-apply locally + push to all remote hosts
#   just status     - Show chezmoi diff
#   just edit       - Open chezmoi source in editor
#
# See 'just --list' for all available commands

hosts_file := home_directory() / ".ssh" / "hosts"

# Show available commands
default:
    @just --list

# Apply chezmoi locally
sync:
    @~/.dotfiles/scripts/sync-chezmoi.sh

# Apply chezmoi locally without prompting
sync-force:
    @~/.dotfiles/scripts/sync-chezmoi.sh --force

# Force-apply locally then push to all remote hosts
sync-all: sync-force
    #!/usr/bin/env bash
    hosts_file="{{ hosts_file }}"
    sync_script="$HOME/.dotfiles/scripts/sync-chezmoi.sh"
    if [[ ! -f "$hosts_file" ]]; then
        echo "No hosts file at $hosts_file"
        exit 1
    fi
    if [[ ! -f "$sync_script" ]]; then
        echo "No sync helper at $sync_script"
        exit 1
    fi
    # Current host, lowercased short name -- skipped below since `sync-force`
    # already applied locally and a host can't SSH to itself.
    self="$(hostname -s | tr '[:upper:]' '[:lower:]')"
    ok=0; fail=0; skip=0; selfskip=0
    while IFS= read -r line; do
        host="${line%%#*}"
        host="${host// /}"
        [[ -z "$host" ]] && continue
        printf '\033[1;34m=== %s ===\033[0m\n' "$host"
        if [[ "$(echo "$host" | tr '[:upper:]' '[:lower:]')" == "$self" ]]; then
            printf '\033[1;36m  self (applied locally via sync-force)\033[0m\n'
            selfskip=$((selfskip + 1))
            continue
        fi
        if ! ssh -n -o ConnectTimeout=5 -o BatchMode=yes "$host" true 2>/dev/null; then
            printf '\033[1;33m  skipped (unreachable or needs password)\033[0m\n'
            skip=$((skip + 1))
            continue
        fi
        output=$(ssh "$host" 'set -e; export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; if [ ! -d "$HOME/.dotfiles/.git" ]; then echo "no ~/.dotfiles repo -- run install.sh on this host first"; exit 1; fi; bash -s -- --force' < "$sync_script" 2>&1)
        rc=$?
        [[ -n "$output" ]] && echo "$output" | sed 's/^/  /'
        if [[ $rc -eq 0 ]]; then
            printf '\033[1;32m  done\033[0m\n'
            ok=$((ok + 1))
        else
            printf '\033[1;31m  failed\033[0m\n'
            fail=$((fail + 1))
        fi
    done < "$hosts_file"
    echo ""
    printf '\033[1;34mSummary: %d ok, %d failed, %d skipped, %d self\033[0m\n' "$ok" "$fail" "$skip" "$selfskip"
    [[ $fail -eq 0 ]]

# Force-apply chezmoi on one configured host (e.g. `just sync-host apollo`)
sync-host HOST:
    #!/usr/bin/env bash
    hosts_file="{{ hosts_file }}"
    sync_script="$HOME/.dotfiles/scripts/sync-chezmoi.sh"
    host="{{ HOST }}"
    if [[ ! -f "$hosts_file" ]]; then
        echo "No hosts file at $hosts_file"
        exit 1
    fi
    if [[ ! -f "$sync_script" ]]; then
        echo "No sync helper at $sync_script"
        exit 1
    fi

    configured=0
    while IFS= read -r line; do
        candidate="${line%%#*}"
        candidate="${candidate// /}"
        [[ -z "$candidate" ]] && continue
        if [[ "$candidate" == "$host" ]]; then
            configured=1
            break
        fi
    done < "$hosts_file"
    if [[ $configured -ne 1 ]]; then
        echo "Unknown host '$host'. Add it to $hosts_file before syncing it."
        exit 1
    fi

    self="$(hostname -s | tr '[:upper:]' '[:lower:]')"
    if [[ "$(echo "$host" | tr '[:upper:]' '[:lower:]')" == "$self" ]]; then
        just sync-force
        exit $?
    fi
    if ! ssh -n -o ConnectTimeout=5 -o BatchMode=yes "$host" true 2>/dev/null; then
        echo "$host is unreachable or needs password authentication"
        exit 1
    fi

    output=$(ssh "$host" 'set -e; export PATH="$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"; if [ ! -d "$HOME/.dotfiles/.git" ]; then echo "no ~/.dotfiles repo -- run install.sh on this host first"; exit 1; fi; bash -s -- --force' < "$sync_script" 2>&1)
    rc=$?
    [[ -n "$output" ]] && echo "$output"
    exit $rc

# Show what chezmoi would change
status:
    @chezmoi diff || true

# Open chezmoi source directory in editor
edit:
    @chezmoi edit

# Run chezmoi doctor
doctor:
    @chezmoi doctor

# Verify chezmoi setup across all hosts
doctor-all:
    #!/usr/bin/env bash
    hosts_file="{{ hosts_file }}"
    if [[ ! -f "$hosts_file" ]]; then
        echo "No hosts file at $hosts_file"
        exit 1
    fi
    echo "Local:"
    chezmoi doctor 2>&1 | grep -E "^(ok|FAIL|WARN|version)" | sed 's/^/  /'
    echo ""
    while IFS= read -r line; do
        host="${line%%#*}"
        host="${host// /}"
        [[ -z "$host" ]] && continue
        printf '%s: ' "$host"
        if ! ssh -n -o ConnectTimeout=5 -o BatchMode=yes "$host" true 2>/dev/null; then
            printf '\033[1;33mskipped\033[0m\n'
            continue
        fi
        version=$(ssh -n "$host" 'export PATH="$HOME/.local/bin:$PATH" && chezmoi --version 2>&1 | awk "{print \$3}"' 2>/dev/null)
        if [[ -n "$version" ]]; then
            printf '\033[1;32m%s\033[0m\n' "$version"
        else
            printf '\033[1;31mno chezmoi\033[0m\n'
        fi
    done < "$hosts_file"

# Distribute SSH keys to all hosts
share-keys KEY="id_ed25519":
    @share-ssh-keys {{ KEY }}

# No shebang: on Windows just needs cygpath for shebang recipes, plain recipes run under Git's sh.
# Format lua + shell files (stylua + shfmt)
format:
    @stylua .
    @files="$(git ls-files '*.sh' '*.bash')"; [ -z "$files" ] || shfmt -i 4 -ci -w $files

# Check formatting without modifying files (exits non-zero on drift)
format-check:
    @stylua --check .
    @files="$(git ls-files '*.sh' '*.bash')"; [ -z "$files" ] || shfmt -i 4 -ci -d $files

# Fail-closed publication gate: scan working tree for secrets + private data
verify-publication:
    @bash scripts/verify-publication.sh

# Same, over full history (verifies a clean root before publishing)
verify-publication-history:
    @bash scripts/verify-publication.sh --history
