#!/usr/bin/env bash
# home-tidy: dry run by default, first matching rule wins, ticket keys route ahead of
# globs, never overwrites, never creates a missing bucket, and reports (does not
# move) non-note files inside a vault. Each test runs against a throwaway $HOME.
set -uo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TIDY="$ROOT/home/dot_local/bin/executable_home-tidy"
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

# fresh_home: an empty $HOME with Data, Work and Notes/work buckets and a rules file.
fresh_home() {
    H="$WORK/home-$RANDOM$RANDOM"
    mkdir -p "$H/Downloads" "$H/Documents" "$H/Data" "$H/Work/Issues" "$H/Notes/work"
    cat >"$H/rules" <<'EOF'
# comment
zone Downloads
zone Documents
vault Notes/work
note-ext md png
keep *.lnk
keep Documents/Receipts
ticket ALM
ticket-dest Work/Issues
*.bacpac -> Data/databases
*.XLSX -> Data/datasets
*.xlsx -> Data/other
Receipts/ -> Documents
*.mp4 -> Videos
EOF
}

# tidy [args]: runs home-tidy against $H; sets out and rc.
tidy() {
    out="$(HOME="$H" HOME_TIDY_RULES="$H/rules" bash "$TIDY" "$@" 2>&1)"
    rc=$?
}

test_dry_run_reports_without_moving() {
    fresh_home
    touch "$H/Downloads/model.bacpac"
    tidy
    if [[ $rc -eq 0 && "$out" == *"move   Downloads/model.bacpac -> Data/databases/"* && -f "$H/Downloads/model.bacpac" && ! -e "$H/Data/databases" ]]; then
        ok "dry run reports the move and leaves the file"
    else
        bad "dry run reports the move and leaves the file" "rc=$rc out=$out"
    fi
}

test_apply_uses_first_matching_rule_case_insensitively() {
    fresh_home
    touch "$H/Downloads/Report.xlsx"
    tidy --apply
    if [[ -f "$H/Data/datasets/Report.xlsx" && ! -e "$H/Data/other" && ! -e "$H/Downloads/Report.xlsx" ]]; then
        ok "apply moves into the first matching rule's dest"
    else
        bad "apply moves into the first matching rule's dest" "$out"
    fi
}

test_ticket_key_routes_ahead_of_globs() {
    fresh_home
    touch "$H/Downloads/ALM-610 validation.xlsx" "$H/Downloads/alm717_backup.bacpac" "$H/Downloads/Empyrean_ALM_2026.08.1.xlsx"
    mkdir "$H/Documents/ALM-728"
    tidy --apply
    if [[ -f "$H/Work/Issues/ALM-610/ALM-610 validation.xlsx" &&
        -f "$H/Work/Issues/ALM-717/alm717_backup.bacpac" &&
        -d "$H/Work/Issues/ALM-728" && ! -e "$H/Work/Issues/ALM-728/ALM-728" &&
        -f "$H/Data/datasets/Empyrean_ALM_2026.08.1.xlsx" ]]; then
        ok "ticket keys (with or without dash, files or dirs) route to Work/Issues/<KEY>"
    else
        bad "ticket keys route to Work/Issues/<KEY>" "$out"
    fi
}

test_existing_target_is_never_overwritten() {
    fresh_home
    mkdir -p "$H/Data/databases"
    echo old >"$H/Data/databases/model.bacpac"
    echo new >"$H/Downloads/model.bacpac"
    tidy --apply
    if [[ "$(cat "$H/Data/databases/model.bacpac")" == old && -f "$H/Downloads/model.bacpac" && "$out" == *"skip   Downloads/model.bacpac: Data/databases/model.bacpac already exists"* ]]; then
        ok "an existing target is skipped, not overwritten"
    else
        bad "an existing target is skipped, not overwritten" "$out"
    fi
}

test_missing_bucket_is_not_created() {
    fresh_home
    touch "$H/Downloads/demo.mp4"
    tidy --apply
    if [[ ! -e "$H/Videos" && -f "$H/Downloads/demo.mp4" && "$out" == *"no ~/Videos bucket"* ]]; then
        ok "a dest whose bucket is missing is skipped"
    else
        bad "a dest whose bucket is missing is skipped" "$out"
    fi
}

test_keep_and_dir_only_rules() {
    fresh_home
    touch "$H/Downloads/App.lnk" "$H/Downloads/Receipts"
    mkdir -p "$H/Documents/Receipts" "$H/Downloads/ALM Docs"
    tidy --apply
    if [[ -f "$H/Downloads/App.lnk" && -d "$H/Documents/Receipts" && -f "$H/Downloads/Receipts" &&
        "$out" != *"App.lnk"* && "$out" != *"Documents/Receipts"* &&
        "$out" == *"left   Downloads/Receipts (no rule)"* && "$out" == *"left   Downloads/ALM Docs (no rule)"* ]]; then
        ok "keep globs (bare and path) hide entries; a dir-only rule ignores files"
    else
        bad "keep globs hide entries; dir-only rule ignores files" "$out"
    fi
}

test_vault_strays_are_reported_not_moved() {
    fresh_home
    mkdir -p "$H/Notes/work/Projects/x/evidence" "$H/Notes/work/.obsidian"
    touch "$H/Notes/work/Projects/x/README.md" "$H/Notes/work/Projects/x/shot.PNG" \
        "$H/Notes/work/Projects/x/evidence/run.csv" "$H/Notes/work/.obsidian/app.json" "$H/Notes/work/.gitignore"
    tidy --apply
    if [[ "$out" == *"vault  Notes/work/Projects/x/evidence/run.csv"* && -f "$H/Notes/work/Projects/x/evidence/run.csv" &&
        "$out" != *"README.md"* && "$out" != *"shot.PNG"* && "$out" != *"app.json"* && "$out" != *".gitignore"* ]]; then
        ok "vault strays are reported in place; notes, attachments, dotfiles are not"
    else
        bad "vault strays are reported in place" "$out"
    fi
}

test_unknown_rule_fails_loudly() {
    fresh_home
    echo "zones Downloads" >>"$H/rules"
    tidy
    if [[ $rc -eq 2 && "$out" == *"bad rule"* ]]; then
        ok "an unknown directive exits 2"
    else
        bad "an unknown directive exits 2" "rc=$rc out=$out"
    fi
}

test_dry_run_reports_without_moving
test_apply_uses_first_matching_rule_case_insensitively
test_ticket_key_routes_ahead_of_globs
test_existing_target_is_never_overwritten
test_missing_bucket_is_not_created
test_keep_and_dir_only_rules
test_vault_strays_are_reported_not_moved
test_unknown_rule_fails_loudly

printf '\n%d passed, %d failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
