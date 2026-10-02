#!/usr/bin/env bash
# P3-T1: every tracked dotfiles path is classified, and privacy-sensitive
# categories are classified private (or sanitize), while general config stays public.
set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
POLICY="$ROOT/policy/publication-policy.yaml"

pass=0
fail=0
ok() {
    pass=$((pass + 1))
    printf '  ok   %s\n' "$1"
}
bad() {
    fail=$((fail + 1))
    printf '  FAIL %s: %s\n' "$1" "$2"
}

# Load glob lists from the policy.
mapfile -t PRIV < <(yq -r '.private_input.paths[]' "$POLICY")
mapfile -t GEN < <(yq -r '.generated.paths[]' "$POLICY")
mapfile -t LOCAL < <(yq -r '.local.paths[]' "$POLICY")
mapfile -t SANI < <(yq -r '.sanitize.paths[]' "$POLICY")

# classify <path> -> echoes class name (first match wins).
classify() {
    local p="$1" g
    for g in "${PRIV[@]}"; do [[ "$p" == $g ]] && {
        echo private_input
        return
    }; done
    for g in "${GEN[@]}"; do [[ "$p" == $g ]] && {
        echo generated
        return
    }; done
    for g in "${LOCAL[@]}"; do [[ "$p" == $g ]] && {
        echo local
        return
    }; done
    for g in "${SANI[@]}"; do [[ "$p" == $g ]] && {
        echo sanitize
        return
    }; done
    echo public
}

cd "$ROOT"

# Every tracked path resolves to exactly one class (fallback guarantees coverage;
# this checks the classifier runs cleanly over the whole tree).
test_every_tracked_path_has_a_policy_classification() {
    local p c n=0
    while read -r p; do
        [ -z "$p" ] && continue
        c="$(classify "$p")"
        [ -z "$c" ] && {
            bad every_path "$p unclassified"
            return
        }
        n=$((n + 1))
    done < <(git ls-files)
    ok "every_tracked_path_has_a_policy_classification ($n paths)"
}

test_ssh_host_inventory_is_private() {
    # The host inventory and key hints must not be tracked in public source at
    # all — they live in the companion. Only *.tmpl wrappers remain here.
    local tracked
    tracked="$(git ls-files home/private_dot_ssh | grep -vE '\.tmpl$' || true)"
    [ -z "$tracked" ] && ok ssh_host_inventory_is_private ||
        bad ssh_host_inventory_is_private "non-wrapper files tracked: $tracked"
    # The policy still classifies such paths as private_input (defense for future).
    [ "$(classify home/private_dot_ssh/hosts)" = private_input ] ||
        bad ssh_host_inventory_glob "hosts glob not private_input"
}

test_machine_and_work_identity_are_private() {
    # identity/host data keys are declared private inputs (move to companion)
    local keys
    keys="$(yq -r '.private_input.data_keys[]' "$POLICY")"
    for k in work_email work_hostname server_hostnames workstation_hostnames; do
        printf '%s\n' "$keys" | grep -qx "$k" || {
            bad machine_work_identity "$k missing from private data_keys"
            return
        }
    done
    # hermes agent config moves too
    # hermes agent config is not tracked in public source (moved to companion)
    local hermes
    hermes="$(git ls-files home/private_dot_hermes | grep -vE '\.tmpl$' || true)"
    [ -z "$hermes" ] ||
        {
            bad machine_work_identity "hermes tracked in public: $hermes"
            return
        }
    ok machine_and_work_identity_are_private
}

test_general_chezmoi_configuration_remains_public() {
    # Core config templates stay public (class public or sanitize), never private_input.
    local f
    for f in home/.chezmoi.toml.tmpl home/.chezmoiignore home/dot_zshrc home/dot_config/git/config.tmpl; do
        local c
        c="$(classify "$f")"
        [ "$c" = private_input ] && {
            bad general_config_public "$f wrongly private_input"
            return
        }
    done
    # a plain public file classifies as public
    [ "$(classify home/dot_tmux.conf)" = public ] || {
        bad general_config_public "tmux.conf not public"
        return
    }
    ok general_chezmoi_configuration_remains_public
}

test_every_tracked_path_has_a_policy_classification
test_ssh_host_inventory_is_private
test_machine_and_work_identity_are_private
test_general_chezmoi_configuration_remains_public

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
