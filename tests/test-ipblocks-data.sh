#!/usr/bin/env bash
# =====================================================================
# test-ipblocks-data.sh
# Offline tests for the published ipblocks-ua-qs JSON export.
#
# Covers:
#   * website/static/data/ipblocks-ua-qs.json exists and parses
#   * the document schema — version, name and required keys
#   * ips / networks are non-empty, sorted and de-duplicated
#   * every entry in the source lists appears in the export
#   * the user-agent list carries the corrected spellings
#   * regenerating with bin/export-ipblocks.sh produces no diff
#
# No network access, no Cloudflare credentials; does not modify tracked
# files (the regeneration check writes to a temporary file).
#
# Usage:
#   bash tests/test-ipblocks-data.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

SRC_DIR="$REPO_DIR/ipblocks-ua-qs"
EXPORT_FILE="$REPO_DIR/website/static/data/ipblocks-ua-qs.json"
EXPORT_SCRIPT="$REPO_DIR/bin/export-ipblocks.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
BLUE='\033[0;34m'

pass() {
    ((TEST_COUNT++))
    ((PASS_COUNT++))
    echo -e "${GREEN}✓ PASS${NC}: $1"
}

fail() {
    ((TEST_COUNT++))
    ((FAIL_COUNT++))
    echo -e "${RED}✗ FAIL${NC}: $1"
}

assert_eq() {
    local description="$1" expected="$2" actual="$3"
    if [[ "$expected" == "$actual" ]]; then
        pass "$description"
    else
        fail "$description"
        echo "  expected: $expected"
        echo "  actual:   $actual"
    fi
}

assert_file() {
    local description="$1" path="$2"
    if [[ -f "$path" ]]; then
        pass "$description"
    else
        fail "$description ($path)"
    fi
}

# One source file as sorted, de-duplicated entries — the same rules the
# exporter applies, so the two can be compared.
read_list() {
    local file="$1"
    LC_ALL=C sed -e 's/#.*//' -e 's/[[:space:]]*$//' -e 's/^[[:space:]]*//' "$file" \
        | LC_ALL=C sed '/^$/d' \
        | LC_ALL=C sort -u
}

echo -e "${BLUE}=== files ===${NC}"
assert_file "the export exists" "$EXPORT_FILE"
assert_file "the exporter exists" "$EXPORT_SCRIPT"
assert_file "the BlogVault list exists" "$SRC_DIR/ips-blogvault.txt"
assert_file "the WP Umbrella list exists" "$SRC_DIR/ips-wp-umbrella.txt"
assert_file "the user-agent list exists" "$SRC_DIR/user-agents.txt"
assert_file "the query-string list exists" "$SRC_DIR/query-strings.txt"
assert_file "the ASN list exists" "$SRC_DIR/asn.txt"

echo ""
echo -e "${BLUE}=== schema ===${NC}"

if command -v jq >/dev/null 2>&1 && jq -e . "$EXPORT_FILE" >/dev/null 2>&1; then
    pass "the export is valid JSON"
else
    fail "the export is valid JSON"
    echo ""
    echo -e "${BLUE}=== Results ===${NC}"
    echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
    exit 1
fi

assert_eq "schema_version is 1" "1" "$(jq -r '.schema_version' "$EXPORT_FILE")"
assert_eq "the document is named" "ipblocks-ua-qs" "$(jq -r '.name' "$EXPORT_FILE")"
assert_eq "the description is set" "true" \
    "$(jq -r '(.description | length) > 0' "$EXPORT_FILE")"

missing_keys=""
for key in schema_version name description sources ips networks asns lists; do
    jq -e "has(\"$key\")" "$EXPORT_FILE" >/dev/null 2>&1 || missing_keys+="$key "
done
assert_eq "every required key is present" "" "$missing_keys"

echo ""
echo -e "${BLUE}=== addresses ===${NC}"

assert_eq "the address list is not empty" "true" \
    "$(jq -r '(.ips | length) > 0' "$EXPORT_FILE")"
assert_eq "the address list is sorted and unique" "" \
    "$(jq -r '.ips[]' "$EXPORT_FILE" | LC_ALL=C sort -u -c 2>&1)"
assert_eq "the network list is sorted and unique" "" \
    "$(jq -r '.networks[]' "$EXPORT_FILE" | LC_ALL=C sort -u -c 2>&1)"
assert_eq "no network leaked into the address list" "0" \
    "$(jq -r '[.ips[] | select(test("[:/]"))] | length' "$EXPORT_FILE")"
assert_eq "both source address lists are represented" "true" \
    "$(jq -r '(.lists.ips_blogvault | length) > 0 and (.lists.ips_wp_umbrella | length) > 0' "$EXPORT_FILE")"

echo ""
echo -e "${BLUE}=== source parity ===${NC}"

check_parity() {
    local description="$1" source_file="$2" jq_path="$3"
    local from_source from_export
    from_source=$(read_list "$source_file")
    from_export=$(jq -r "$jq_path" "$EXPORT_FILE" | LC_ALL=C sort -u)
    assert_eq "$description" "$from_source" "$from_export"
}

check_parity "BlogVault addresses match the source" "$SRC_DIR/ips-blogvault.txt" '.lists.ips_blogvault[]'
check_parity "WP Umbrella addresses match the source" "$SRC_DIR/ips-wp-umbrella.txt" '.lists.ips_wp_umbrella[]'
check_parity "user agents match the source" "$SRC_DIR/user-agents.txt" '.lists.user_agents[]'
check_parity "query strings match the source" "$SRC_DIR/query-strings.txt" '.lists.query_strings[]'

echo ""
echo -e "${BLUE}=== user agents ===${NC}"

for agent in "Better Uptime Bot" "ShortPixel" "Uptime-Kuma"; do
    assert_eq "the source list spells $agent correctly" "1" \
        "$(grep -cxF "$agent" "$SRC_DIR/user-agents.txt")"
done

echo ""
echo -e "${BLUE}=== asns ===${NC}"

assert_eq "every ASN has a number and a label" "0" \
    "$(jq -r '[.asns[] | select((.asn | type) != "number" or (.label | length) == 0)] | length' "$EXPORT_FILE")"

echo ""
echo -e "${BLUE}=== regeneration ===${NC}"

tmp_file=$(mktemp)
trap 'rm -f "$tmp_file"' EXIT

if bash "$EXPORT_SCRIPT" "$tmp_file" >/dev/null 2>&1; then
    pass "the exporter runs"
else
    fail "the exporter runs"
fi

assert_eq "regenerating matches the committed export" "" "$(diff -q "$tmp_file" "$EXPORT_FILE" 2>&1)"

echo ""
echo -e "${BLUE}=== Results ===${NC}"
echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
