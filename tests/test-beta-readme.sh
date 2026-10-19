#!/usr/bin/env bash
# =====================================================================
# test-beta-readme.sh
# Offline tests for the generated beta rules block at the top of README.md.
#
# Covers:
#   * README beta markers — one ordered pair, below the H1
#   * Placement — above the release notice and the README changelog
#   * Generated block — matches the rendered beta profile
#   * AGENTS.md — documents the beta-first policy
#
# No Cloudflare API access or credentials required; does not modify files.
#
# Usage:
#   bash tests/test-beta-readme.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

README_FILE="$REPO_DIR/README.md"
AGENTS_FILE="$REPO_DIR/AGENTS.md"
BETA_JSON="$REPO_DIR/profiles/mwp-rules-beta.json"
BETA_MD="$REPO_DIR/profiles/mwp-rules-beta.md"

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

    if printf '%s' "$haystack" | grep -qF "$needle"; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  expected to contain: $needle"
        ((FAIL_COUNT++))
    fi
}

assert_gt() {
    local description="$1" actual="$2" expected="$3"
    ((TEST_COUNT++))

    if [[ "$actual" =~ ^[0-9]+$ && "$expected" =~ ^[0-9]+$ && "$actual" -gt "$expected" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  expected line $actual to be greater than line $expected"
        ((FAIL_COUNT++))
    fi
}

assert_same_text() {
    local description="$1" expected="$2" actual="$3"
    ((TEST_COUNT++))

    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        diff -u <(printf '%s\n' "$expected") <(printf '%s\n' "$actual") | sed -n '1,20p'
        ((FAIL_COUNT++))
    fi
}

line_of() {
    grep -nF "$1" "$2" | head -1 | cut -d: -f1
}

expected_beta_body=$(awk '
    /<!-- RULES-START -->/ { inblock=1; next }
    /<!-- RULES-END -->/   { inblock=0; next }
    inblock {
        if ($0 == "# Rules Data") next
        if ($0 ~ /^## R/) sub(/^## /, "### ")
        print
    }
' "$BETA_MD" | sed '/^$/d')

actual_beta_body=$(awk '
    /^### R[0-9]/ { inblock=1 }
    /<!-- BETA-RULES-END -->/ { inblock=0 }
    inblock { print }
' "$README_FILE" | sed '/^$/d')

h1_line=$(line_of '# Cloudflare WordPress Rules' "$README_FILE")
start_line=$(line_of '<!-- BETA-RULES-START -->' "$README_FILE")
end_line=$(line_of '<!-- BETA-RULES-END -->' "$README_FILE")
whats_new_line=$(line_of "## What's New in v2.4.0" "$README_FILE")
changelog_line=$(line_of '<!--- CHANGELOG --->' "$README_FILE")
agents_policy_line=$(grep -n '^## Beta Rules Are Always At The Top' "$AGENTS_FILE" | head -1 | cut -d: -f1)
agents_dev_line=$(grep -n '^## Development Documentation' "$AGENTS_FILE" | head -1 | cut -d: -f1)
rule_count=$(grep -c '^### R[0-9]' "$README_FILE")
expected_rule_count=$(jq '.rules | length' "$BETA_JSON")

echo -e "${BLUE}=== README beta block ===${NC}"
assert_eq "exactly one beta start marker" "1" "$(grep -cF '<!-- BETA-RULES-START -->' "$README_FILE")"
assert_eq "exactly one beta end marker" "1" "$(grep -cF '<!-- BETA-RULES-END -->' "$README_FILE")"
assert_gt "beta start marker is below the H1" "$start_line" "$h1_line"
assert_gt "beta end marker follows the start marker" "$end_line" "$start_line"
assert_gt "beta block is above the release notice" "$whats_new_line" "$start_line"
assert_gt "beta block is above the README changelog" "$changelog_line" "$start_line"
assert_contains "beta block has a staging heading" "## Beta Rules (Staging)" "$(cat "$README_FILE")"
assert_contains "beta block has a rules heading" "### Rules Data" "$(cat "$README_FILE")"
assert_eq "beta block rule count matches the profile" "$expected_rule_count" "$rule_count"
assert_same_text "beta block body matches the rendered beta profile" "$expected_beta_body" "$actual_beta_body"

echo ""
echo -e "${BLUE}=== AGENTS.md beta policy ===${NC}"
assert_contains "AGENTS.md has the top beta policy" "## Beta Rules Are Always At The Top" "$(cat "$AGENTS_FILE")"
assert_gt "Development Documentation is below the beta policy" "$agents_dev_line" "$agents_policy_line"
assert_contains "AGENTS.md names the beta generator" "bin/build.sh generate-md" "$(cat "$AGENTS_FILE")"
assert_contains "AGENTS.md guards VERSION" 'Do not bump `VERSION`' "$(cat "$AGENTS_FILE")"
assert_contains "AGENTS.md names CHANGELOG.md" "CHANGELOG.md" "$(cat "$AGENTS_FILE")"
assert_contains "AGENTS.md names the changelog generator" "bin/build.sh generate-readme" "$(cat "$AGENTS_FILE")"

echo ""
echo -e "${BLUE}=== Results ===${NC}"
echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
