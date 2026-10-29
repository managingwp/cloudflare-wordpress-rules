#!/usr/bin/env bash
# =============================================================================
# bin/generate-readme.sh — Regenerate the changelog
#
# Writes the git log to CHANGELOG.md and mirrors it into docs/changelog.md
# between the markers:
#   <!--- CHANGELOG --->
#   <!--- END CHANGELOG --->
# =============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
CHANGELOG_FILE="$ROOT_DIR/CHANGELOG.md"
DOCS_CHANGELOG="$ROOT_DIR/docs/changelog.md"
START_MARKER='<!--- CHANGELOG --->'
END_MARKER='<!--- END CHANGELOG --->'

[[ -f "$DOCS_CHANGELOG" ]] || { echo "Error: $DOCS_CHANGELOG not found" >&2; exit 1; }

if ! grep -qF "$START_MARKER" "$DOCS_CHANGELOG" || ! grep -qF "$END_MARKER" "$DOCS_CHANGELOG"; then
    echo "Error: $DOCS_CHANGELOG must contain $START_MARKER and $END_MARKER" >&2
    exit 1
fi

tmp_log=$(mktemp)
tmp_docs=$(mktemp)
trap 'rm -f "$tmp_log" "$tmp_docs"' EXIT

git -C "$ROOT_DIR" log --pretty=format:"## %s%n%b" | sed '/^## /b; /^$/d; s/^/* /' > "$tmp_log"
cp "$tmp_log" "$CHANGELOG_FILE"
echo "Updated $CHANGELOG_FILE"

awk -v block_file="$tmp_log" '
    $0 == "<!--- CHANGELOG --->" {
        print
        while ((getline line < block_file) > 0) print line
        close(block_file)
        skip=1
        next
    }
    $0 == "<!--- END CHANGELOG --->" { skip=0; print; next }
    !skip { print }
' "$DOCS_CHANGELOG" > "$tmp_docs"

cp "$tmp_docs" "$DOCS_CHANGELOG"
echo "Updated $DOCS_CHANGELOG"
