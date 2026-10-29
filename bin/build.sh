#!/usr/bin/env bash
# =============================================================================
# bin/build.sh — Unified build orchestrator
#
# Runs profile generation, the generated docs pages, the changelog, and the
# documentation site build. Can be run individually or as part of a release.
#
# Usage:
#   bin/build.sh                    # Run all generation steps (+ docs build if set up)
#   bin/build.sh generate-md        # Regenerate profile .md files, docs rule pages, README beta pointer
#   bin/build.sh generate-readme    # Regenerate CHANGELOG.md and docs/changelog.md
#   bin/build.sh docs               # Build the Docusaurus site into website/build
#   bin/build.sh --help             # Show this message
# =============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)

usage() {
    echo "Usage: $(basename "$0") [subcommand]"
    echo ""
    echo "Subcommands:"
    echo "  (none)           Run all generation steps, then the docs build when website/ is set up"
    echo "  generate-md      Regenerate profile .md files, docs rule pages and the README beta pointer"
    echo "  generate-versions  Republish website/static/generator/profiles/versions.json"
    echo "  generate-readme  Regenerate CHANGELOG.md and docs/changelog.md from git log"
    echo "  docs             Build the documentation site with npm (website/)"
    echo "  --help, -h       Show this message"
    echo ""
    echo "Examples:"
    echo "  bin/build.sh                 # Full build"
    echo "  bin/build.sh generate-md     # Profile .md files + docs rule pages + README pointer"
    echo "  bin/build.sh generate-versions # The generator's releases manifest"
    echo "  bin/build.sh generate-readme # Changelog only"
    echo "  bin/build.sh docs            # Docusaurus build"
}

run_generate_md() {
    echo "=== Generating profile .md files and docs rule pages ==="
    bash "$SCRIPT_DIR/generate-md.sh"
    echo "=== Done ==="
}

run_generate_versions() {
    echo "=== Updating the generator's versions manifest ==="
    bash "$SCRIPT_DIR/generate-versions.sh"
    echo "=== Done ==="
}

run_generate_readme() {
    echo "=== Updating CHANGELOG.md and docs/changelog.md ==="
    bash "$SCRIPT_DIR/generate-readme.sh"
    echo "=== Done ==="
}

run_docs() {
    if [[ ! -f "$ROOT_DIR/website/package.json" ]]; then
        echo "Error: website/package.json not found — docs site is not set up" >&2
        exit 1
    fi
    echo "=== Building the documentation site ==="
    ( cd "$ROOT_DIR/website" && npm run build )
    echo "=== Done ==="
}

# -- Parse subcommand
SUBCMD="${1:-all}"

case "$SUBCMD" in
    all)
        run_generate_md
        run_generate_versions
        run_generate_readme
        if [[ -f "$ROOT_DIR/website/package.json" ]]; then
            run_docs
        fi
        ;;
    generate-md)
        run_generate_md
        ;;
    generate-versions)
        run_generate_versions
        ;;
    generate-readme)
        run_generate_readme
        ;;
    docs)
        run_docs
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
