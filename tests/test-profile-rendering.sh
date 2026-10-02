#!/usr/bin/env bash
# P3-T4 / P4: render parity + public-safety for the private-companion composition.
# Read-only. Expected private values are read from the companion at runtime, so
# this public test contains no private literals.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"
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

PRIV="$HOME/.dotfiles-private"
DATA="$PRIV/data.yaml"
have_priv=0
[ -f "$DATA" ] && have_priv=1

# The public source must contain none of the companion's private string values.
test_public_source_has_no_private_values() {
    [ "$have_priv" = 1 ] || {
        ok "public_source_has_no_private_values (skipped: no companion)"
        return
    }
    # High-signal private values only (unambiguous): emails, forgejo host/base,
    # work org/host, NAS IP, and the SSH key identity names. Common-word machine
    # codenames are covered by the publication gate, not this substring grep.
    local leak="" v
    for v in \
        "$(yq -r '.identity.work_email' "$DATA")" \
        "$(yq -r '.identity.personal_email' "$DATA")" \
        "$(yq -r '.identity.work_hostname' "$DATA")" \
        "$(yq -r '.identity.forgejo_host' "$DATA")" \
        "$(yq -r '.identity.work_git_org' "$DATA")" \
        "$(yq -r '.identity.notes_nas_host' "$DATA")" \
        "$(yq -r '.ssh.identities[]' "$DATA")"; do
        [ -z "$v" ] || [ "$v" = "null" ] && continue
        git grep -qF "$v" -- . ':!tests' 2>/dev/null && leak="$leak $v"
    done
    [ -z "$leak" ] && ok public_source_has_no_private_values || bad public_source_has_no_private_values "leaked:$leak"
}

# Private source dir holds only template wrappers, never key material or inventory.
test_private_source_dir_has_only_wrappers() {
    local nontmpl
    nontmpl="$(git ls-files home/private_dot_ssh home/private_dot_hermes | grep -vE '\.tmpl$' || true)"
    [ -z "$nontmpl" ] && ok private_source_dir_has_only_wrappers || bad private_source_dir_has_only_wrappers "$nontmpl"
}

# Personal workstation render reproduces a private host + identity from companion.
test_personal_workstation_render_parity() {
    [ "$have_priv" = 1 ] || {
        ok "personal_workstation_render_parity (skipped)"
        return
    }
    local name host user cfg
    name="$(yq -r '.ssh.groups[-1].hosts[0].name' "$DATA")"
    host="$(yq -r '.ssh.groups[-1].hosts[0].hostname' "$DATA")"
    user="$(yq -r '.ssh.groups[-1].hosts[0].user' "$DATA")"
    cfg="$(chezmoi cat ~/.ssh/config 2>/dev/null)"
    printf '%s' "$cfg" >/tmp/.pp_ssh
    local g
    g="$(ssh -F /tmp/.pp_ssh -G "$name" 2>/dev/null)"
    rm -f /tmp/.pp_ssh
    if printf '%s\n' "$g" | grep -qx "hostname $host" && printf '%s\n' "$g" | grep -qx "user $user"; then
        ok personal_workstation_render_parity
    else bad personal_workstation_render_parity "ssh -G $name did not match companion data"; fi
}

# Work profile pulls the work identity from the companion (not the public repo).
test_work_profile_uses_private_identity_input() {
    [ "$have_priv" = 1 ] || {
        ok "work_profile_uses_private_identity_input (skipped)"
        return
    }
    local want data
    want="$(yq -r '.identity.work_email' "$DATA")"
    data="$(chezmoi execute-template --init --promptBool 'Is this a work machine=true' <home/.chezmoi.toml.tmpl 2>/dev/null)"
    case "$data" in *"work_email = \"$want\""*) ok work_profile_uses_private_identity_input ;; *) bad work_profile_uses_private_identity_input "work_email not sourced from companion" ;; esac
}

# With the companion hidden, the SSH render is generic and leaks nothing.
test_public_only_render_contains_no_prohibited_values() {
    [ "$have_priv" = 1 ] || {
        ok "public_only_render_contains_no_prohibited_values (skipped)"
        return
    }
    local host
    host="$(yq -r '.ssh.groups[-1].hosts[0].hostname' "$DATA")"
    local tmp
    tmp="$(mktemp -d)"
    mv "$DATA" "$tmp/data.yaml"
    local cfg
    cfg="$(chezmoi cat ~/.ssh/config 2>/dev/null)"
    mv "$tmp/data.yaml" "$DATA"
    rmdir "$tmp"
    if printf '%s' "$cfg" | grep -qF "$host"; then
        bad public_only_render_contains_no_prohibited_values "leak in generic render"
    else ok public_only_render_contains_no_prohibited_values; fi
}

test_public_source_has_no_private_values
test_private_source_dir_has_only_wrappers
test_personal_workstation_render_parity
test_work_profile_uses_private_identity_input
test_public_only_render_contains_no_prohibited_values

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[ "$fail" -eq 0 ]
