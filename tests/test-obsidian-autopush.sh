#!/usr/bin/env bash
# obsidian-autopush: hourly git snapshots of the NAS vault copies. It must fail loudly (non-zero
# exit, so the unit's OnFailure= alerts) when the mount is missing, a commit or push fails, or a
# NAS sync container isn't healthy, but still snapshot what it can. mountpoint, git and docker
# are stubs that record how they were called.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCRIPT="$ROOT/home/dot_local/bin/executable_obsidian-autopush"
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
cat >"$STUB/mountpoint" <<'EOF'
#!/usr/bin/env bash
exit "${MOUNT_RC:-0}"
EOF
# git -C <repo> ...: a repo is dirty when it contains a .dirty file; push fails when .push-fails exists.
cat >"$STUB/git" <<'EOF'
#!/usr/bin/env bash
repo="$2"
printf 'git %s %s\n' "$(basename "$repo")" "${*:3}" >>"$CALLS"
case "$3" in
    status) [[ -e "$repo/.dirty" ]] && echo " M note.md" ;;
    push) [[ -e "$repo/.push-fails" ]] && exit 1 ;;
esac
exit 0
EOF
# docker inspect -f ... <container>: healthy unless $UNHEALTHY names the container.
cat >"$STUB/docker" <<'EOF'
#!/usr/bin/env bash
container="${!#}"
[[ " ${UNHEALTHY:-} " == *" $container "* ]] && echo unhealthy || echo healthy
EOF
chmod +x "$STUB"/*

# run_autopush [env...]: runs the script on $BASE; sets rc, err, calls.
run_autopush() {
    : >"$WORK/calls"
    err="$(env PATH="$STUB:$PATH" CALLS="$WORK/calls" OBSIDIAN_AUTOPUSH_BASE="$BASE" "$@" \
        bash "$SCRIPT" 2>&1 >/dev/null)"
    rc=$?
    calls="$(cat "$WORK/calls")"
}

# fresh_base <name> <vault[:dirty|:nogit|:pushfails]>...
fresh_base() {
    BASE="$WORK/$1"
    shift
    local spec v
    for spec in "$@"; do
        v="${spec%%:*}"
        mkdir -p "$BASE/$v"
        [[ "$spec" == *:nogit ]] || mkdir -p "$BASE/$v/.git"
        [[ "$spec" != *:dirty ]] || touch "$BASE/$v/.dirty"
        [[ "$spec" != *:pushfails ]] || touch "$BASE/$v/.push-fails"
    done
}

test_missing_mount_fails_without_git() {
    fresh_base nomount personal-notes work-notes
    run_autopush MOUNT_RC=1
    if [[ $rc -ne 0 && -z "$calls" && "$err" == *"not mounted"* ]]; then
        ok missing_mount_fails_without_git
    else bad missing_mount_fails_without_git "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_clean_vaults_push_without_commit() {
    fresh_base clean personal-notes work-notes
    run_autopush
    local expected="git personal-notes status --porcelain
git personal-notes push -q origin main
git work-notes status --porcelain
git work-notes push -q origin main"
    if [[ $rc -eq 0 && "$calls" == "$expected" ]]; then
        ok clean_vaults_push_without_commit
    else bad clean_vaults_push_without_commit "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_dirty_vault_commits_snapshot_then_pushes() {
    fresh_base dirty personal-notes:dirty work-notes
    run_autopush
    if [[ $rc -eq 0 && "$calls" == *"git personal-notes add -A"*"git personal-notes commit -q -m Auto-snapshot "*"git personal-notes push -q origin main"* && "$calls" != *"work-notes commit"* ]]; then
        ok dirty_vault_commits_snapshot_then_pushes
    else bad dirty_vault_commits_snapshot_then_pushes "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_vault_without_git_is_skipped() {
    fresh_base nogit personal-notes work-notes:nogit
    run_autopush
    if [[ $rc -eq 0 && "$calls" != *"work-notes"* ]]; then
        ok vault_without_git_is_skipped
    else bad vault_without_git_is_skipped "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_failed_push_fails_run_but_other_vaults_continue() {
    fresh_base pushfail personal-notes:pushfails work-notes
    run_autopush
    if [[ $rc -ne 0 && "$calls" == *"git work-notes push"* && "$err" == *"personal-notes push FAILED"* ]]; then
        ok failed_push_fails_run_but_other_vaults_continue
    else bad failed_push_fails_run_but_other_vaults_continue "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_unhealthy_container_still_snapshots_then_fails() {
    fresh_base unhealthy personal-notes:dirty work-notes
    run_autopush UNHEALTHY=obsidian-sync-personal
    if [[ $rc -ne 0 && "$calls" == *"git personal-notes commit"*"git personal-notes push"* && "$err" == *"obsidian-sync-personal is unhealthy"* && "$err" != *"work"* ]]; then
        ok unhealthy_container_still_snapshots_then_fails
    else bad unhealthy_container_still_snapshots_then_fails "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_missing_mount_fails_without_git
test_clean_vaults_push_without_commit
test_dirty_vault_commits_snapshot_then_pushes
test_vault_without_git_is_skipped
test_failed_push_fails_run_but_other_vaults_continue
test_unhealthy_container_still_snapshots_then_fails

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
