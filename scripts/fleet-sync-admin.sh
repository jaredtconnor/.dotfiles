#!/usr/bin/env bash
# Set up the hosts and Forgejo for the fleet-sync workflow. Run on a workstation.
#
#   fleet-sync-admin.sh publish      authorize the fleet-sync key on every host
#                                    and publish the host list + host keys
#   fleet-sync-admin.sh rotate-key   new key: store it as the Forgejo secret,
#                                    write its .pub to the companion, publish
#   fleet-sync-admin.sh run          run the full-detail workflow (in
#                                    dotfiles-private) now
#
# The fleet is ~/.ssh/hosts plus this machine, minus hosts without a
# ~/.dotfiles checkout that pulls from Forgejo. Re-run `publish` after adding a
# host to the companion's ssh/hosts. The private key exists only in Forgejo;
# rotate-key replaces it.
#
# On each host the key is pinned to one command, so whoever holds it can only
# make that host pull from Forgejo and apply:
#   restrict,command="... sync-chezmoi.sh --unattended" ssh-ed25519 ... fleet-sync@forgejo
set -euo pipefail

PRIVATE_DIR="${PRIVATE_DOTFILES_DIR:-$HOME/.dotfiles-private}"
PUB="$PRIVATE_DIR/fleet/fleet-sync.pub"
HOSTS_FILE="$HOME/.ssh/hosts"
COMMENT="fleet-sync@forgejo"
WORKFLOW="/repos/eigyn/dotfiles-private/actions/workflows/fleet-sync.yml"
# shellcheck disable=SC2016 # expanded by the host's shell, not here
FORCED='PATH=/opt/homebrew/bin:/usr/local/bin:$PATH ~/.dotfiles/scripts/sync-chezmoi.sh --unattended'

say() { printf '\033[1;34m%s\033[0m\n' "$*"; }
warn() { printf '\033[1;33m%s\033[0m\n' "$*" >&2; }

# Send a JSON body from stdin. tea api exits 0 on HTTP errors, so read the
# status line it writes to stderr with -i.
forgejo() {
    local status
    status="$(tea api -i -X "$1" "$2" -d @- 2>&1 >/dev/null | sed -n 1p)"
    [[ "$status" =~ \ 2[0-9][0-9]\  ]] || {
        printf '%s %s: %s\n' "$1" "$2" "$status" >&2
        return 1
    }
}

set_variable() {
    local name="$1" value="$2" body
    body="$(python3 -c 'import json, sys; print(json.dumps({"name": sys.argv[1], "value": sys.argv[2]}))' "$name" "$value")"
    forgejo PUT "/user/actions/variables/$name" <<<"$body" 2>/dev/null ||
        forgejo POST "/user/actions/variables/$name" <<<"$body"
}

fleet_aliases() {
    local self line
    self="$(hostname -s | tr '[:upper:]' '[:lower:]')"
    {
        printf '%s\n' "$self"
        while IFS= read -r line; do
            line="${line%%#*}"
            line="${line// /}"
            [[ -n "$line" ]] && printf '%s\n' "$line"
        done <"$HOSTS_FILE"
    } | awk '!seen[$0]++'
}

ssh_opt() {
    awk -v key="$2" '$1 == key { $1 = ""; sub(/^ /, ""); print; exit }' <<<"$1"
}

# known_hosts lines for one alias, rewritten to the address the runner dials.
host_keys() {
    local config="$1" address="$2" port="$3" lookup pattern file
    lookup="$(ssh_opt "$config" hostkeyalias)"
    [[ -n "$lookup" ]] || lookup="$address"
    pattern="$address"
    if [[ "$port" != 22 ]]; then
        lookup="[$lookup]:$port"
        pattern="[$address]:$port"
    fi
    for file in $(ssh_opt "$config" userknownhostsfile); do
        file="${file/#\~/$HOME}"
        [[ -f "$file" ]] || continue
        # Skip comments and @cert-authority / @revoked lines.
        ssh-keygen -F "$lookup" -f "$file" 2>/dev/null |
            awk -v p="$pattern" '!/^[#@]/ && NF >= 3 { print p, $2, $3 }'
    done | awk '!seen[$0]++'
}

authorize() {
    local alias="$1" line
    line="restrict,command=\"$FORCED\" $(cat "$PUB")"
    # shellcheck disable=SC2029 # args are quoted locally on purpose
    ssh -o BatchMode=yes -o ConnectTimeout=10 "$alias" "bash -s -- $(printf '%q ' "$line" "$COMMENT")" <<'REMOTE'
set -eu
line="$1"
comment="$2"
ak="$HOME/.ssh/authorized_keys"
umask 077
mkdir -p "$HOME/.ssh"
touch "$ak"
if grep -qxF "$line" "$ak"; then
    echo "  key: already authorized"
    exit 0
fi
tmp="$(mktemp "$HOME/.ssh/authorized_keys.XXXXXX")"
grep -vF " $comment" "$ak" >"$tmp" || true
printf '%s\n' "$line" >>"$tmp"
if [ -L "$ak" ]; then
    # Proxmox links authorized_keys into /etc/pve; write through the link.
    cat "$tmp" >"$ak"
    rm -f "$tmp"
else
    mv "$tmp" "$ak"
fi
echo "  key: authorized"
REMOTE
}

cmd_publish() {
    [[ -f "$PUB" ]] || {
        warn "No $PUB yet. Run rotate-key first."
        exit 1
    }
    [[ -f "$HOSTS_FILE" ]] || {
        warn "No $HOSTS_FILE (it comes from the private companion)."
        exit 1
    }

    local alias config user address port origin keys entries="" known="" pending=()
    # fd 3, so nothing in the loop that reads stdin (ssh) eats the host list.
    while IFS= read -r alias <&3; do
        say "$alias"
        config="$(ssh -G "$alias" 2>/dev/null)"
        user="$(ssh_opt "$config" user)"
        address="$(ssh_opt "$config" hostname)"
        port="$(ssh_opt "$config" port)"

        if ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$alias" true 2>/dev/null; then
            origin="$(ssh -n -o BatchMode=yes -o ConnectTimeout=5 "$alias" 'git -C ~/.dotfiles remote get-url origin' 2>/dev/null || true)"
            if [[ -z "$origin" ]]; then
                warn "  no ~/.dotfiles checkout: left out"
                continue
            fi
            # A push reaches the GitHub mirror later than the workflow runs.
            if [[ "$origin" == *github.com* ]]; then
                warn "  ~/.dotfiles pulls from the GitHub mirror, so a push would miss it: left out"
                continue
            fi
            authorize "$alias"
        else
            warn "  unreachable: listed, but authorize it later by re-running publish"
            pending+=("$alias")
        fi

        keys="$(host_keys "$config" "$address" "$port")"
        if [[ -z "$keys" ]]; then
            warn "  no host key for $address in known_hosts (ssh to it once): left out"
            continue
        fi
        entries+="$alias=ssh://$user@$address:$port "
        known+="$keys"$'\n'
    done 3< <(fleet_aliases)

    say "Publishing FLEET_SYNC_HOSTS and FLEET_SYNC_KNOWN_HOSTS (user-level Forgejo variables)"
    set_variable FLEET_SYNC_HOSTS "${entries% }"
    set_variable FLEET_SYNC_KNOWN_HOSTS "$known"
    # shellcheck disable=SC2086 # one entry per line
    printf '  %s\n' $entries
    if [[ ${#pending[@]} -gt 0 ]]; then
        warn "Not authorized yet: ${pending[*]}"
    fi
}

tmp=""
cmd_rotate_key() {
    tmp="$(mktemp -d)"
    trap 'rm -rf "$tmp"' EXIT
    ssh-keygen -q -t ed25519 -N "" -C "$COMMENT" -f "$tmp/key"
    say "Storing the private key as FLEET_SYNC_SSH_KEY (user-level Forgejo secret)"
    python3 -c 'import json, sys; print(json.dumps({"data": open(sys.argv[1]).read()}))' "$tmp/key" |
        forgejo PUT /user/actions/secrets/FLEET_SYNC_SSH_KEY
    rm -f "$tmp/key"
    mkdir -p "$(dirname "$PUB")"
    cp "$tmp/key.pub" "$PUB"
    say "Wrote $PUB; commit and push it in the companion"
    cmd_publish
}

cmd_run() {
    forgejo POST "$WORKFLOW/dispatches" <<<'{"ref": "main"}'
    say "Started; follow it under Actions -> fleet-sync on dotfiles-private."
}

case "${1:-}" in
    publish) cmd_publish ;;
    rotate-key) cmd_rotate_key ;;
    run) cmd_run ;;
    *)
        awk 'NR > 1 && /^#/ { sub(/^# ?/, ""); print; next } NR > 1 { exit }' "$0"
        exit 2
        ;;
esac
