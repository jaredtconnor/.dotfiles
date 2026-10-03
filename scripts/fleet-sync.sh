#!/usr/bin/env bash
# Run an unattended sync on every fleet host at once, then summarize.
#
# Runs in the fleet-sync Forgejo workflow (dotfiles, dotfiles-private and
# agent-tooling each carry a copy; life-ops carries one narrowed to the Hermes
# host). Each host pins the key to
# `sync-chezmoi.sh --unattended` in its authorized_keys, so connecting is the
# whole request. See scripts/fleet-sync-admin.sh for the host-side setup.
#
# Environment (user-level Forgejo secret and variables):
#   FLEET_SYNC_SSH_KEY      private key
#   FLEET_SYNC_HOSTS        whitespace-separated name=ssh://user@address:port
#   FLEET_SYNC_KNOWN_HOSTS  known_hosts lines for those addresses
#   FLEET_SYNC_LOG          "full" prints each host's output; anything else
#                           prints counts only. Public repos have public run
#                           logs, and host names and addresses are private.
#
# Exits non-zero only when a reachable host failed. Files edited locally on a
# host are left alone and listed (everything else there is applied); a host
# that doesn't answer (asleep, offline) is listed too, and the nightly run
# catches it up.
set -uo pipefail

: "${FLEET_SYNC_SSH_KEY:?secret FLEET_SYNC_SSH_KEY is not set}"
: "${FLEET_SYNC_HOSTS:?variable FLEET_SYNC_HOSTS is not set}"
: "${FLEET_SYNC_KNOWN_HOSTS:?variable FLEET_SYNC_KNOWN_HOSTS is not set}"
full=0
[[ "${FLEET_SYNC_LOG:-}" == full ]] && full=1

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
umask 077
printf '%s\n' "$FLEET_SYNC_SSH_KEY" >"$work/key"
unset FLEET_SYNC_SSH_KEY
printf '%s\n' "$FLEET_SYNC_KNOWN_HOSTS" >"$work/known_hosts"

names=()
for entry in $FLEET_SYNC_HOSTS; do
    name="${entry%%=*}"
    target="${entry#*=}"
    names+=("$name")
    (
        # A full externals refresh takes a minute or two; 20 minutes is hung.
        timeout 1200 ssh -n -T \
            -i "$work/key" -o IdentitiesOnly=yes -o IdentityAgent=none \
            -o BatchMode=yes -o ConnectTimeout=10 -o ServerAliveInterval=30 \
            -o StrictHostKeyChecking=yes -o UserKnownHostsFile="$work/known_hosts" \
            "$target" >"$work/$name.log" 2>&1
        echo $? >"$work/$name.rc"
    ) &
done
wait

ok=() edited=() asleep=() failed=()
for name in "${names[@]}"; do
    rc="$(cat "$work/$name.rc")"
    case "$rc" in
        0) ok+=("$name") ;;
        3) edited+=("$name") ;;
        255)
            if grep -qE 'timed out|No route to host|Host is down|Connection refused|Network is unreachable' "$work/$name.log"; then
                asleep+=("$name")
            else
                failed+=("$name")
            fi
            ;;
        *) failed+=("$name") ;;
    esac
    if [[ "$full" -eq 1 ]]; then
        printf '::group::%s (exit %s)\n' "$name" "$rc"
        cat "$work/$name.log"
        printf '::endgroup::\n'
    fi
done

if [[ "$full" -eq 1 ]]; then
    printf '\nsynced:        %s\n' "${ok[*]:-none}"
    printf 'local edits:   %s\n' "${edited[*]:-none}"
    printf 'unreachable:   %s\n' "${asleep[*]:-none}"
    printf 'failed:        %s\n' "${failed[*]:-none}"
    if [[ ${#edited[@]} -gt 0 ]]; then
        printf '::warning::local edits left alone on %s (see their logs)\n' "${edited[*]}"
    fi
else
    printf '%d synced, %d with local edits left alone, %d unreachable, %d failed\n' \
        "${#ok[@]}" "${#edited[@]}" "${#asleep[@]}" "${#failed[@]}"
    if [[ ${#failed[@]} -gt 0 || ${#edited[@]} -gt 0 ]]; then
        echo "Host details stay out of this public log: run \`just fleet-sync\` for a private run."
    fi
fi

[[ ${#failed[@]} -eq 0 ]]
