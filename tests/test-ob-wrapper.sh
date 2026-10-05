#!/usr/bin/env bash
# ob wrapper: always runs obsidian-headless with the node it was built for, and rebuilds its
# native module (better-sqlite3) once when that node's ABI changes. node and npm are stubs that
# record how they were called.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WRAPPER="$ROOT/home/dot_local/bin/executable_ob"
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
NODE_DIR="$WORK/node/bin"
mkdir -p "$NODE_DIR"
cat >"$NODE_DIR/node" <<'EOF'
#!/usr/bin/env bash
if [[ "$1" == -p ]]; then echo "$STUB_ABI"; exit 0; fi
printf 'node %s\n' "$*" >>"$CALLS"
EOF
cat >"$NODE_DIR/npm" <<'EOF'
#!/usr/bin/env bash
printf 'npm %s\n' "$*" >>"$CALLS"
exit "${NPM_RC:-0}"
EOF
chmod +x "$NODE_DIR/node" "$NODE_DIR/npm"

# run_wrapper <abi> [env...] -- [ob args...]: sets rc, err, calls.
run_wrapper() {
    local abi="$1"
    shift
    local envs=()
    while [[ $# -gt 0 && "$1" != -- ]]; do
        envs+=("$1")
        shift
    done
    shift
    : >"$WORK/calls"
    err="$(env HOME="$WORK/home" OB_PREFIX="$PREFIX" OB_NODE="$NODE_DIR/node" CALLS="$WORK/calls" \
        STUB_ABI="$abi" "${envs[@]}" bash "$WRAPPER" "$@" 2>&1 >/dev/null)"
    rc=$?
    calls="$(cat "$WORK/calls")"
}

fresh_prefix() {
    PREFIX="$WORK/prefix-$1"
    mkdir -p "$PREFIX/node_modules/obsidian-headless"
    [[ -z "${2:-}" ]] || printf '%s\n' "$2" >"$PREFIX/.node-abi"
}

test_matching_abi_runs_cli_without_rebuild() {
    fresh_prefix match 147
    run_wrapper 147 -- sync-status --path /v
    if [[ $rc -eq 0 && "$calls" == "node $PREFIX/node_modules/obsidian-headless/cli.js sync-status --path /v" ]]; then
        ok matching_abi_runs_cli_without_rebuild
    else bad matching_abi_runs_cli_without_rebuild "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_changed_abi_rebuilds_once_then_runs() {
    fresh_prefix changed 137
    run_wrapper 147 -- --version
    local expected="npm rebuild --prefix $PREFIX --loglevel=error
node $PREFIX/node_modules/obsidian-headless/cli.js --version"
    if [[ $rc -eq 0 && "$calls" == "$expected" && "$(cat "$PREFIX/.node-abi")" == 147 ]]; then
        ok changed_abi_rebuilds_once_then_runs
    else bad changed_abi_rebuilds_once_then_runs "rc=$rc calls=[$calls] err=[$err]"; fi
    run_wrapper 147 -- --version
    if [[ "$calls" != *"npm rebuild"* ]]; then
        ok second_run_skips_rebuild
    else bad second_run_skips_rebuild "calls=[$calls]"; fi
}

test_missing_marker_rebuilds() {
    fresh_prefix nomarker
    run_wrapper 147 -- --version
    if [[ $rc -eq 0 && "$calls" == "npm rebuild"* && "$(cat "$PREFIX/.node-abi")" == 147 ]]; then
        ok missing_marker_rebuilds
    else bad missing_marker_rebuilds "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_failed_rebuild_stops_and_keeps_marker() {
    fresh_prefix failed 137
    run_wrapper 147 NPM_RC=1 -- --version
    if [[ $rc -ne 0 && "$calls" != *"cli.js"* && "$(cat "$PREFIX/.node-abi")" == 137 ]]; then
        ok failed_rebuild_stops_and_keeps_marker
    else bad failed_rebuild_stops_and_keeps_marker "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_missing_node_says_so() {
    fresh_prefix nonode 147
    run_wrapper 147 OB_NODE="$WORK/nowhere/node" -- --version
    if [[ $rc -ne 0 && -z "$calls" && "$err" == *"node not found"* ]]; then
        ok missing_node_says_so
    else bad missing_node_says_so "rc=$rc calls=[$calls] err=[$err]"; fi
}

test_matching_abi_runs_cli_without_rebuild
test_changed_abi_rebuilds_once_then_runs
test_missing_marker_rebuilds
test_failed_rebuild_stops_and_keeps_marker
test_missing_node_says_so

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
