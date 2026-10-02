#!/usr/bin/env bash
# Fail-closed publication gate for the public dotfiles.
#
# Blocks publication on any secret (gitleaks) or privacy-policy violation.
# By default scans the WORKING TREE (the sanitized, publishable content).
# With --history it scans all reachable commits (used to verify the clean root).
#
# Usage:
#   scripts/verify-publication.sh            # scan working tree
#   scripts/verify-publication.sh --history  # scan full git history
#   scripts/verify-publication.sh <dir>      # scan an arbitrary directory (fixtures)
#
# Exit 0 only when safe to publish.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "$HERE/.." && pwd)"
POLICY="$HERE/publication-policy.txt"
LOCAL_POLICY="$HERE/publication-policy.local.txt"

MODE="tree"
TARGET="$ROOT"
case "${1:-}" in
    --history) MODE="history" ;;
    "") : ;;
    *)
        MODE="dir"
        TARGET="$1"
        ;;
esac

fail=0
note() { printf '%s\n' "$*" >&2; }

command -v gitleaks >/dev/null 2>&1 || {
    note "error: gitleaks required"
    exit 2
}

# --- 1. secrets ----------------------------------------------------------
case "$MODE" in
    history) gitleaks git "$ROOT" --no-banner >/dev/null 2>&1 || {
        note "FAIL secrets: gitleaks findings in history"
        fail=1
    } ;;
    *) gitleaks dir "$TARGET" --no-banner >/dev/null 2>&1 || {
        note "FAIL secrets: gitleaks findings in files"
        fail=1
    } ;;
esac

# --- file list -----------------------------------------------------------
if [ "$MODE" = "dir" ]; then
    mapfile -t FILES < <(cd "$TARGET" && find . -type f -not -path './.git/*' | sed 's#^\./##')
    prefix="$TARGET/"
else
    mapfile -t FILES < <(git -C "$ROOT" ls-files)
    prefix="$ROOT/"
fi

# --- 2. content policy (generic + local specifics) -----------------------
patterns=()
for pf in "$POLICY" "$LOCAL_POLICY"; do
    [ -f "$pf" ] || continue
    while IFS= read -r p; do
        [ -z "$p" ] && continue
        case "$p" in \#*) continue ;; esac
        patterns+=("$p")
    done <"$pf"
done

is_policy_file() {
    case "$1" in
        scripts/publication-policy.txt | scripts/publication-policy.local.txt) return 0 ;;
        *) return 1 ;;
    esac
}

for pat in "${patterns[@]}"; do
    for f in "${FILES[@]}"; do
        is_policy_file "$f" && continue
        [ -f "$prefix$f" ] || continue
        if grep -IEqn "$pat" "$prefix$f" 2>/dev/null; then
            note "FAIL policy: '$f' matches /$pat/"
            fail=1
        fi
    done
done

# --- 3. private-overlay / key files never public -------------------------
for f in "${FILES[@]}"; do
    case "$f" in
        *.pem | *id_ed25519 | *id_rsa | */private/*)
            note "FAIL: '$f' looks like private key/overlay material"
            fail=1
            ;;
    esac
done

[ "$fail" -eq 0 ] && note "publication gate: OK ($MODE)"
exit "$fail"
