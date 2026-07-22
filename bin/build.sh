#!/usr/bin/env bash
# =============================================================================
# bin/build.sh — Unified build orchestrator
#
# Runs profile generation and README/changelog update steps.
# Can be run individually or as part of a release.
#
# Usage:
#   bin/build.sh                    # Run all generation steps
#   bin/build.sh generate-md        # Only regenerate profile .md files
#   bin/build.sh generate-readme    # Only update README.md changelog
#   bin/build.sh --help             # Show this message
# =============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)

usage() {
    echo "Usage: $(basename "$0") [subcommand]"
    echo ""
    echo "Subcommands:"
    echo "  (none)           Run all generation steps (default)"
    echo "  generate-md      Regenerate profile .md files from JSON"
    echo "  generate-readme  Update README.md changelog from git log"
    echo "  --help, -h       Show this message"
    echo ""
    echo "Examples:"
    echo "  bin/build.sh                 # Full build"
    echo "  bin/build.sh generate-md     # .md files only"
    echo "  bin/build.sh generate-readme # README only"
}

run_generate_md() {
    echo "=== Generating profile .md files ==="
    bash "$SCRIPT_DIR/generate-md.sh"
    echo "=== Done ==="
}

run_generate_readme() {
    echo "=== Updating README.md changelog ==="
    bash "$SCRIPT_DIR/generate-readme.sh"
    echo "=== Done ==="
}

# -- Parse subcommand
SUBCMD="${1:-all}"

case "$SUBCMD" in
    all)
        run_generate_md
        run_generate_readme
        ;;
    generate-md)
        run_generate_md
        ;;
    generate-readme)
        run_generate_readme
        ;;
    --help|-h)
        usage
        exit 0
        ;;
    *)
        echo "Error: Unknown subcommand '$SUBCMD'"
        echo ""
        usage
        exit 1
        ;;
esac
