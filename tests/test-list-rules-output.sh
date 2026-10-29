#!/usr/bin/env bash
# =====================================================================
# test-list-rules-output.sh
# Offline tests for the list-rules renderer and CLI flag surface.
#
# No Cloudflare credentials or network access are required: the fixture
# holds a real entry point response and the renderer reads
# RULESET_API_OUTPUT directly.
#
# Usage:
#   bash tests/test-list-rules-output.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")
FIXTURE="$SCRIPT_DIR/cf-ruleset-entrypoint.json"
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'

if [[ ! -f "$FIXTURE" ]]; then
    echo "Missing fixture: $FIXTURE" >&2
    exit 1
fi

export SCRIPT_DIR="$REPO_DIR"
export PROFILE_DIR="$REPO_DIR/profiles"

# Source the utilities only; no authentication is triggered.
# shellcheck source=../inc/cf-inc.sh
source "$REPO_DIR/inc/cf-inc.sh"
# shellcheck source=../inc/cf-inc-rulesets.sh
source "$REPO_DIR/inc/cf-inc-rulesets.sh"

# =========================================
# Test framework
# =========================================
assert_eq() {
    local description="$1" expected="$2" actual="$3"
    ((TEST_COUNT++))
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo "    expected: $expected"
        echo "    actual:   $actual"
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
        echo "    missing: $needle"
        ((FAIL_COUNT++))
    fi
}

assert_not_contains() {
    local description="$1" needle="$2" haystack="$3"
    ((TEST_COUNT++))
    if grep -qF -- "$needle" <<< "$haystack"; then
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo "    unexpected: $needle"
        ((FAIL_COUNT++))
    else
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    fi
}

assert_exit() {
    local description="$1" expected="$2" actual="$3"
    assert_eq "$description" "$expected" "$actual"
}

# Count fields in one CSV row, honoring doubled quotes inside fields.
csv_field_count() {
    awk '
        function count_fields(line,   i, c, n, in_quotes) {
            n = 1; in_quotes = 0
            for (i = 1; i <= length(line); i++) {
                c = substr(line, i, 1)
                if (c == "\"") {
                    if (in_quotes && substr(line, i + 1, 1) == "\"") { i++ }
                    else { in_quotes = !in_quotes }
                } else if (c == "," && !in_quotes) {
                    n++
                }
            }
            return n
        }
        { print count_fields($0) }
    ' <<< "$1"
}

# =========================================
# Shared render helper
# =========================================
render() {
    local format="$1" long="${2:-0}"
    LIST_FORMAT="$format"
    LIST_LONG="$long"
    _cf_ruleset_render_list "cannaessence.ch" "8e88ca76443f8e20af9c78042803b58d" 2>/dev/null
}

export RULESET_API_OUTPUT
RULESET_API_OUTPUT=$(cat "$FIXTURE")
CF_CSV_HEADER_PRINTED=0

echo -e "${YELLOW}=== list-rules table ===${NC}"

TABLE=$(render table)
assert_eq "table renders four aligned data rows" "4" "$(grep -cE '^[0-9]+[[:space:]]' <<< "$TABLE")"
assert_eq "table prints each rule ID exactly once" "1" "$(grep -cF 'eb107ee2c59741a581214b3e359fffc5' <<< "$TABLE")"
assert_eq "table prints each rule ID exactly once (block)" "1" "$(grep -cF 'a8d7034442ea4b76aad7a48b5454dc38' <<< "$TABLE")"
assert_eq "table prints each rule ID exactly once (managed challenge)" "1" "$(grep -cF '85d6b0bce6fa4445bc7d1a2ad87a913c' <<< "$TABLE")"
assert_eq "table prints each rule ID exactly once (js challenge)" "1" "$(grep -cF 'df7e5f803cf845d7858ea7737b084691' <<< "$TABLE")"
assert_contains "table shows the skip action" "skip" "$TABLE"
assert_contains "table shows the block action" "block" "$TABLE"
assert_contains "table shows the managed challenge action" "managed_challenge" "$TABLE"
assert_contains "table shows the js challenge action" "js_challenge" "$TABLE"
assert_contains "table shows ruleset version" "version 12" "$TABLE"
assert_contains "table shows the rule count" "4 rules" "$TABLE"
assert_contains "table shows the UPDATED column" "UPDATED" "$TABLE"
assert_eq "table renders every rule's last_updated" "4" "$(grep -E '^[0-9]+[[:space:]]' <<< "$TABLE" | grep -c '2026-10-16 20:32:35')"
assert_not_contains "table does not print fractional seconds" ".953566" "$TABLE"
assert_contains "table shows the en dash description" "R3V207 – Managed Challenge" "$TABLE"
assert_not_contains "table does not dump the raw JSON kind" '"kind":' "$TABLE"
assert_not_contains "table does not dump the raw expression field" '"expression":' "$TABLE"
assert_not_contains "table does not print a startup banner" "Running list-rules" "$TABLE"

ENABLED_ROWS=$(grep -E '^[0-9]+[[:space:]]' <<< "$TABLE" | grep -cE '[[:space:]]yes[[:space:]]')
assert_eq "every fixture rule renders as enabled" "4" "$ENABLED_ROWS"

# Disabled rules must render, marked no.
DISABLED_FIXTURE=$(jq '.result.rules[1].enabled = false' "$FIXTURE")
RULESET_API_OUTPUT="$DISABLED_FIXTURE"
DISABLED_TABLE=$(render table)
assert_contains "disabled rule is still listed" "a8d7034442ea4b76aad7a48b5454dc38" "$DISABLED_TABLE"
DISABLED_ROW=$(grep '^2[[:space:]]' <<< "$DISABLED_TABLE")
assert_contains "disabled rule renders enabled=no" "no" "$DISABLED_ROW"
RULESET_API_OUTPUT=$(cat "$FIXTURE")

echo ""
echo -e "${YELLOW}=== list-rules --long ===${NC}"

LONG=$(render table 1)
assert_eq "long mode prints one expression per rule" "4" "$(grep -c 'expression:' <<< "$LONG")"
assert_eq "long mode prints one action_parameters line" "1" "$(grep -c 'action_parameters:' <<< "$LONG")"
assert_eq "long mode prints logging for every rule" "4" "$(grep -c 'logging:' <<< "$LONG")"
assert_contains "long mode prints the full skip expression" "http.user_agent contains \"InfiniteWP\"" "$LONG"
assert_contains "long mode prints the ruleset target" '{"ruleset":"current"}' "$LONG"

echo ""
echo -e "${YELLOW}=== list-rules --json ===${NC}"

JSON_OUT=$(render json)
assert_eq "json output is one line per zone" "1" "$(wc -l <<< "$JSON_OUT" | tr -d ' ')"
assert_eq "json parses as a single document" "true" "$(jq -e 'type == "object"' <<< "$JSON_OUT")"
assert_eq "json carries the domain" "cannaessence.ch" "$(jq -r '.domain' <<< "$JSON_OUT")"
assert_eq "json carries the zone id" "8e88ca76443f8e20af9c78042803b58d" "$(jq -r '.zone_id' <<< "$JSON_OUT")"
assert_eq "json carries four rules" "4" "$(jq -r '.rules | length' <<< "$JSON_OUT")"
assert_eq "json carries the ruleset id" "0eacafce74544ec0a43d8e2c08c4e7ef" "$(jq -r '.ruleset.id' <<< "$JSON_OUT")"
assert_eq "json carries the ruleset version" "12" "$(jq -r '.ruleset.version' <<< "$JSON_OUT")"
assert_eq "json rule_count matches the rules array" "4" "$(jq -r '.ruleset.rule_count' <<< "$JSON_OUT")"
assert_eq "json preserves rule order" "skip" "$(jq -r '.rules[0].action' <<< "$JSON_OUT")"

echo ""
echo -e "${YELLOW}=== list-rules --csv ===${NC}"

CF_CSV_HEADER_PRINTED=0
CSV_OUT=$(render csv)
assert_eq "csv has one header plus four rows" "5" "$(wc -l <<< "$CSV_OUT" | tr -d ' ')"
assert_eq "csv header is stable" \
    "domain,zone_id,position,rule_id,action,enabled,logging,description,expression" \
    "$(head -1 <<< "$CSV_OUT")"
assert_eq "csv rows have nine fields" "9" "$(csv_field_count "$(sed -n '2p' <<< "$CSV_OUT")")"
assert_contains "csv keeps the comma-bearing R1 description in one field" 'R1V207 -  Allow URI Query, URL, User Agents, and IPs (Allow)' "$CSV_OUT"
assert_contains "csv keeps the escaped skip expression" 'wc-api=wc_shipstation' "$CSV_OUT"

# A second zone in the same process must not repeat the header.
CSV_TMP_A=$(mktemp)
CSV_TMP_B=$(mktemp)
CF_CSV_HEADER_PRINTED=0
render csv > "$CSV_TMP_A"
render csv > "$CSV_TMP_B"
assert_eq "csv header prints once per process" "4" "$(wc -l < "$CSV_TMP_B" | tr -d ' ')"
assert_eq "csv second zone still has four rows" "4" "$(grep -c '^"' "$CSV_TMP_B")"
rm -f "$CSV_TMP_A" "$CSV_TMP_B"
CF_CSV_HEADER_PRINTED=0

echo ""
echo -e "${YELLOW}=== list-rules --raw ===${NC}"

RAW_OUT=$(render raw)
assert_eq "raw output matches the fixture byte for byte" "0" "$(diff <(cat "$FIXTURE") <(printf '%s\n' "$RAW_OUT") >/dev/null 2>&1; echo $?)"
assert_contains "raw output still carries the API envelope" '"success": true' "$RAW_OUT"

echo ""
echo -e "${YELLOW}=== empty and missing entry points ===${NC}"

EMPTY_FIXTURE='{"result":{"id":"rs","name":"default","phase":"http_request_firewall_custom","version":"1","last_updated":"2026-01-01T00:00:00Z","rules":[]},"success":true,"errors":[],"messages":[]}'
RULESET_API_OUTPUT="$EMPTY_FIXTURE"
assert_exit "empty table exits 0" "0" "$(render table >/dev/null 2>&1; echo $?)"
assert_contains "empty table explains the state" "No WAF custom rules" "$(render table)"
assert_eq "empty json is valid with zero rules" "true" "$(render json | jq -e '(.rules | length) == 0 and .ruleset != null')"
CF_CSV_HEADER_PRINTED=0
assert_eq "empty csv is header-only" "1" "$(render csv | wc -l | tr -d ' ')"

MISSING_FIXTURE='{"success":false,"errors":[{"code":7003,"message":"Could not route to /rulesets/phases/http_request_firewall_custom/entrypoint"}],"messages":[],"result":null}'
RULESET_API_OUTPUT="$MISSING_FIXTURE"
assert_exit "missing entry point exits 0" "0" "$(render table >/dev/null 2>&1; echo $?)"
assert_eq "missing entry point json has null ruleset" "true" "$(render json | jq -e '.ruleset == null and (.rules | length) == 0')"

RULESET_API_OUTPUT=$(cat "$FIXTURE")

echo ""
echo -e "${YELLOW}=== single emission and CLI surface ===${NC}"

# Stub the entry point fetch: the body it echoes must not reach stdout.
cf_ruleset_get_entrypoint() {
    printf '%s\n' "$RULESET_API_OUTPUT"
    return 0
}
LIST_FORMAT=table
LIST_LONG=0
ONCE=$(cf_ruleset_list_rules "cannaessence.ch" "8e88ca76443f8e20af9c78042803b58d" 2>/dev/null)
assert_eq "stubbed fetch renders the body once" "0" "$(grep -cF '"kind":' <<< "$ONCE")"
assert_eq "stubbed fetch renders one table header" "1" "$(grep -c '^#  ACTION' <<< "$ONCE")"
assert_eq "stubbed fetch renders four rows" "4" "$(grep -cE '^[0-9]+[[:space:]]' <<< "$ONCE")"

# Restore the real function for the rest of the suite.
unset -f cf_ruleset_get_entrypoint
# shellcheck source=../inc/cf-inc-rulesets.sh
source "$REPO_DIR/inc/cf-inc-rulesets.sh"

USAGE=$("$REPO_DIR/cloudflare-wordpress-rules.sh" 2>&1 || true)
assert_contains "usage lists --json" "--json" "$USAGE"
assert_contains "usage lists --csv" "--csv" "$USAGE"
assert_contains "usage lists --raw" "--raw" "$USAGE"
assert_contains "usage lists --long" "--long" "$USAGE"
assert_contains "usage marks --table-only deprecated" "DEPRECATED" "$USAGE"

set +e
"$REPO_DIR/cloudflare-wordpress-rules.sh" -d example.com -c list-rules --json --csv >/dev/null 2>&1
CONFLICT_EXIT=$?
"$REPO_DIR/cloudflare-wordpress-rules.sh" -d example.com -c list-rules --json --table-only >/dev/null 2>&1
TABLE_CONFLICT_EXIT=$?
"$REPO_DIR/cloudflare-wordpress-rules.sh" -d example.com -c list-rules --long --csv >/dev/null 2>&1
LONG_CONFLICT_EXIT=$?
assert_exit "conflicting formats exit 2" "2" "$CONFLICT_EXIT"
assert_exit "--table-only conflicts with --json" "2" "$TABLE_CONFLICT_EXIT"
assert_exit "--long conflicts with --csv" "2" "$LONG_CONFLICT_EXIT"

echo ""
echo -e "${YELLOW}=== Summary ===${NC}"
echo "Tests:  $TEST_COUNT"
echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
if [[ $FAIL_COUNT -gt 0 ]]; then
    echo -e "${RED}Failed: $FAIL_COUNT${NC}"
    exit 1
fi
echo -e "${GREEN}All list-rules output tests passed.${NC}"
