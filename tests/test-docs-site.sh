#!/usr/bin/env bash
# =====================================================================
# test-docs-site.sh
# Offline tests for the documentation layout and the slim README.
#
# Covers:
#   * README — slim, one beta marker pair, repo links resolve
#   * docs/ — front matter on every page, every page in the sidebar
#   * docs/ — relative Markdown links resolve
#   * docs/ — release notifications page documents the tag feed
#   * generated pages — markers and rule counts
#   * website/ — pinned Docusaurus version and build script
#   * GitHub Pages workflow — permissions and artifact path
#   * .gitignore — site build output stays untracked
#
# No network access, no Cloudflare credentials; does not modify files.
#
# Usage:
#   bash tests/test-docs-site.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

README_FILE="$REPO_DIR/README.md"
DOCS_DIR="$REPO_DIR/docs"
WEBSITE_DIR="$REPO_DIR/website"
SIDEBAR_FILE="$WEBSITE_DIR/sidebars.js"
WORKFLOW_FILE="$REPO_DIR/.github/workflows/docs.yml"
GITIGNORE_FILE="$REPO_DIR/.gitignore"
BETA_JSON="$REPO_DIR/profiles/mwp-rules-beta.json"

README_LINE_LIMIT=90

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    ((TEST_COUNT++))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  expected: $expected"
        echo -e "  actual:   $actual"
        ((FAIL_COUNT++))
    fi
}

assert_contains() {
    local description="$1" needle="$2" haystack="$3"
    ((TEST_COUNT++))
    if grep -qF -- "$needle" <<< "$haystack"; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  expected to contain: $needle"
        ((FAIL_COUNT++))
    fi
}

assert_file() {
    local description="$1" path="$2"
    ((TEST_COUNT++))
    if [[ -f "$path" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  missing: $path"
        ((FAIL_COUNT++))
    fi
}

# -- README ----------------------------------------------------------
readme_lines=$(wc -l < "$README_FILE" | tr -d ' ')

echo -e "${BLUE}=== README ===${NC}"
assert_eq "README stays slim (<= ${README_LINE_LIMIT} lines)" "1" \
    "$([[ "$readme_lines" -le "$README_LINE_LIMIT" ]] && echo 1 || echo 0)"
assert_eq "README has exactly one beta start marker" "1" \
    "$(grep -cF '<!-- BETA-RULES-START -->' "$README_FILE")"
assert_eq "README has exactly one beta end marker" "1" \
    "$(grep -cF '<!-- BETA-RULES-END -->' "$README_FILE")"
assert_contains "README links the docs site" \
    "managingwp.github.io/cloudflare-wordpress-rules" "$(cat "$README_FILE")"
assert_contains "README links the beta rules page" \
    "reference/beta-rules" "$(cat "$README_FILE")"

broken_readme_links="$(
    grep -oE '\]\([^)]+\)' "$README_FILE" |
        sed -e 's/^](//' -e 's/)$//' |
        while IFS= read -r link; do
            case "$link" in
                http*|mailto:*|'#'*) continue ;;
            esac
            target="${link%%#*}"
            [[ -z "$target" ]] && continue
            [[ -e "$REPO_DIR/$target" ]] || echo "$link"
        done
)"
assert_eq "README relative links resolve" "" "$broken_readme_links"

# -- docs content ----------------------------------------------------
docs_files=$(find "$DOCS_DIR" -name '*.md' | sort)
docs_total=$(printf '%s\n' "$docs_files" | sed '/^$/d' | wc -l | tr -d ' ')

echo ""
echo -e "${BLUE}=== docs pages ===${NC}"
missing_front_matter=""
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    if [[ "$(head -1 "$file")" != "---" ]] || ! grep -q '^title:' "$file"; then
        missing_front_matter+="$file "
    fi
done <<< "$docs_files"
assert_eq "every docs page has front matter with a title" "" "$missing_front_matter"

sidebar_ids=""
if [[ -f "$SIDEBAR_FILE" ]] && command -v node >/dev/null 2>&1; then
    sidebar_ids="$(
        cd "$WEBSITE_DIR" &&
            node -e '
                const sidebars = require("./sidebars.js");
                const ids = [];
                (function walk(items) {
                    for (const item of items) {
                        if (typeof item === "string") ids.push(item);
                        else if (item.items) walk(item.items);
                    }
                })(sidebars.docs);
                console.log(ids.join("\n"));
            '
    )"
fi
assert_eq "sidebar ids match the docs page count" "$docs_total" \
    "$(printf '%s\n' "$sidebar_ids" | sed '/^$/d' | wc -l | tr -d ' ')"

missing_pages=""
while IFS= read -r id; do
    [[ -z "$id" ]] && continue
    [[ -f "$DOCS_DIR/$id.md" ]] || missing_pages+="$id "
done <<< "$sidebar_ids"
assert_eq "every sidebar id resolves to a docs page" "" "$missing_pages"

missing_from_sidebar=""
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    id="${file#"$DOCS_DIR"/}"
    id="${id%.md}"
    if ! grep -qxF "$id" <<< "$sidebar_ids"; then
        missing_from_sidebar+="$id "
    fi
done <<< "$docs_files"
assert_eq "no docs page is missing from the sidebar" "" "$missing_from_sidebar"

broken_docs_links=""
while IFS= read -r file; do
    [[ -z "$file" ]] && continue
    while IFS= read -r link; do
        case "$link" in
            http*|mailto:*|'#'*|'/'*) continue ;;
        esac
        target="${link%%#*}"
        [[ -z "$target" ]] && continue
        case "$target" in
            *.md) ;;
            *) continue ;;
        esac
        [[ -e "$(dirname "$file")/$target" ]] || broken_docs_links+="${file#"$REPO_DIR"/} -> $link"$'\n'
    done < <(grep -oE '\]\([^)]+\)' "$file" | sed -e 's/^](//' -e 's/)$//')
done <<< "$docs_files"
assert_eq "relative docs links resolve" "" "$broken_docs_links"

# -- release notifications -------------------------------------------
NOTIF_PAGE="$DOCS_DIR/getting-started/release-notifications.md"

echo ""
echo -e "${BLUE}=== release notifications ===${NC}"
assert_file "release notifications page exists" "$NOTIF_PAGE"
assert_contains "release notifications page documents the tag feed" \
    "releases.atom" "$(cat "$NOTIF_PAGE" 2>/dev/null)"
assert_contains "release notifications page states the semver filter" \
    '^[0-9]+\.[0-9]+\.[0-9]+$' "$(cat "$NOTIF_PAGE" 2>/dev/null)"
assert_contains "release notifications page is in the sidebar" \
    "getting-started/release-notifications" "$(cat "$SIDEBAR_FILE" 2>/dev/null)"
assert_contains "release notes link the release notifications page" \
    "getting-started/release-notifications.md" "$(cat "$DOCS_DIR/release-notes.md" 2>/dev/null)"

# -- generated pages -------------------------------------------------
BETA_PAGE="$DOCS_DIR/reference/beta-rules.md"
STABLE_PAGE="$DOCS_DIR/reference/stable-rules.md"
CHANGELOG_PAGE="$DOCS_DIR/changelog.md"

echo ""
echo -e "${BLUE}=== generated pages ===${NC}"
assert_file "beta rules page exists" "$BETA_PAGE"
assert_file "stable rules page exists" "$STABLE_PAGE"
assert_file "changelog page exists" "$CHANGELOG_PAGE"
assert_contains "beta page has the RULES markers" "<!-- RULES-START -->" "$(cat "$BETA_PAGE" 2>/dev/null)"
assert_contains "stable page has the RULES markers" "<!-- RULES-START -->" "$(cat "$STABLE_PAGE" 2>/dev/null)"
assert_contains "changelog page has the CHANGELOG markers" '<!--- CHANGELOG --->' "$(cat "$CHANGELOG_PAGE" 2>/dev/null)"
assert_eq "beta page rule count matches the profile" \
    "$(jq '.rules | length' "$BETA_JSON")" "$(grep -c '^### R[0-9]' "$BETA_PAGE")"
assert_contains "stable page names its release" "Stable rules (v" "$(cat "$STABLE_PAGE" 2>/dev/null)"

# -- website config --------------------------------------------------
echo ""
echo -e "${BLUE}=== website ===${NC}"
assert_file "website/package.json exists" "$WEBSITE_DIR/package.json"
assert_file "website/docusaurus.config.js exists" "$WEBSITE_DIR/docusaurus.config.js"
assert_file "website/sidebars.js exists" "$SIDEBAR_FILE"
assert_contains "Docusaurus is pinned to 3.10.2" '"@docusaurus/core": "3.10.2"' "$(cat "$WEBSITE_DIR/package.json")"
assert_contains "build script exists" '"build": "docusaurus build"' "$(cat "$WEBSITE_DIR/package.json")"
assert_contains "docs path points at the repo docs folder" "path: '../docs'" "$(cat "$WEBSITE_DIR/docusaurus.config.js")"
assert_contains "broken links fail the build" "onBrokenLinks: 'throw'" "$(cat "$WEBSITE_DIR/docusaurus.config.js")"
assert_contains "GitHub Pages baseUrl is set" "baseUrl: '/cloudflare-wordpress-rules/'" "$(cat "$WEBSITE_DIR/docusaurus.config.js")"

# -- workflow and ignores --------------------------------------------
echo ""
echo -e "${BLUE}=== publishing ===${NC}"
assert_file "docs workflow exists" "$WORKFLOW_FILE"
assert_contains "workflow can write Pages" "pages: write" "$(cat "$WORKFLOW_FILE" 2>/dev/null)"
assert_contains "workflow has an OIDC token" "id-token: write" "$(cat "$WORKFLOW_FILE" 2>/dev/null)"
assert_contains "workflow uploads website/build" "path: website/build" "$(cat "$WORKFLOW_FILE" 2>/dev/null)"
assert_contains "workflow triggers on docs changes" "'docs/**'" "$(cat "$WORKFLOW_FILE" 2>/dev/null)"
assert_contains "node_modules is ignored" "website/node_modules/" "$(cat "$GITIGNORE_FILE")"
assert_contains "site build output is ignored" "website/build/" "$(cat "$GITIGNORE_FILE")"

echo ""
echo -e "${BLUE}=== Results ===${NC}"
echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
