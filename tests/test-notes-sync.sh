#!/usr/bin/env bash
# notes-sync launcher: it must refuse to start on a vault that is missing, empty, or not set up
# for Obsidian Sync (ob would sync an empty folder as "delete every note"), and otherwise hand
# over to `ob sync --continuous`. `ob` is a stub that records how it was called.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
LAUNCHER="$ROOT/home/dot_local/bin/executable_notes-sync"
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

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT
STUB="$WORK/bin"
mkdir -p "$STUB"
cat >"$STUB/ob" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" >>"$OB_CALLS"
[[ "$1" == sync-status ]] && exit "${OB_STATUS_RC:-0}"
exit 0
EOF
chmod +x "$STUB/ob"

# run_launcher <vault> [env...]: runs the launcher against the stub; sets rc, err, calls.
run_launcher() {
    local vault="$1"
    shift
    : >"$WORK/calls"
    err="$(env HOME="$WORK/home" NOTES_SYNC_BIN_DIR="$STUB" OB_CALLS="$WORK/calls" \
        ${vault:+NOTES_SYNC_VAULT="$vault"} "$@" bash "$LAUNCHER" 2>&1 >/dev/null)"
    rc=$?
    calls="$(cat "$WORK/calls")"
}

# make_vault <dir> [note]: a vault with .obsidian, plus a note unless "no-note".
make_vault() {
    mkdir -p "$1/.obsidian"
    [[ "${2:-}" == no-note ]] || printf '# note\n' >"$1/note.md"
}

test_missing_vault_refuses_without_calling_ob() {
    run_launcher "$WORK/nowhere"
    if [[ $rc -ne 0 && -z "$calls" && "$err" == *"does not exist"* ]]; then
        ok missing_vault_refuses_without_calling_ob
    else bad missing_vault_refuses_without_calling_ob "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_vault_without_obsidian_folder_refuses() {
    mkdir -p "$WORK/plain"
    printf '# note\n' >"$WORK/plain/note.md"
    run_launcher "$WORK/plain"
    if [[ $rc -ne 0 && -z "$calls" && "$err" == *".obsidian"* ]]; then
        ok vault_without_obsidian_folder_refuses
    else bad vault_without_obsidian_folder_refuses "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_vault_without_notes_refuses() {
    make_vault "$WORK/empty" no-note
    printf '# not a note\n' >"$WORK/empty/.obsidian/workspace.md"
    run_launcher "$WORK/empty"
    if [[ $rc -ne 0 && -z "$calls" && "$err" == *"no notes"* ]]; then
        ok vault_without_notes_refuses
    else bad vault_without_notes_refuses "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_unconfigured_vault_refuses() {
    make_vault "$WORK/unset"
    run_launcher "$WORK/unset" OB_STATUS_RC=1
    if [[ $rc -ne 0 && "$calls" == "sync-status --path $WORK/unset" && "$err" == *"not set up"* ]]; then
        ok unconfigured_vault_refuses
    else bad unconfigured_vault_refuses "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_healthy_vault_runs_continuous_sync() {
    make_vault "$WORK/good"
    run_launcher "$WORK/good"
    if [[ $rc -eq 0 && "$(tail -1 <<<"$calls")" == "sync --continuous --path $WORK/good" ]]; then
        ok healthy_vault_runs_continuous_sync
    else bad healthy_vault_runs_continuous_sync "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_missing_ob_refuses_and_says_so() {
    make_vault "$WORK/noob"
    run_launcher "$WORK/noob" NOTES_SYNC_BIN_DIR="$WORK/empty-bin" PATH=/usr/bin:/bin
    if [[ $rc -ne 0 && -z "$calls" && "$err" == *"ob is not installed"* ]]; then
        ok missing_ob_refuses_and_says_so
    else bad missing_ob_refuses_and_says_so "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_default_vault_is_notes_personal() {
    make_vault "$WORK/home/Notes/personal"
    run_launcher ""
    if [[ $rc -eq 0 && "$(tail -1 <<<"$calls")" == "sync --continuous --path $WORK/home/Notes/personal" ]]; then
        ok default_vault_is_notes_personal
    else bad default_vault_is_notes_personal "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_missing_vault_refuses_without_calling_ob
test_vault_without_obsidian_folder_refuses
test_vault_without_notes_refuses
test_unconfigured_vault_refuses
test_healthy_vault_runs_continuous_sync
test_missing_ob_refuses_and_says_so
test_default_vault_is_notes_personal

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
