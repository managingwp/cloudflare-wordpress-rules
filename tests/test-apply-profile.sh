#!/usr/bin/env bash
# =====================================================================
# test-apply-profile.sh
# Offline tests for cf_ruleset_apply_profile and the tables it prints.
#
# No Cloudflare credentials or network access are required: the Rulesets
# API wrapper is stubbed and the fixture is a real entry point response.
#
# Usage:
#   bash tests/test-apply-profile.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")
FIXTURE="$SCRIPT_DIR/cf-ruleset-entrypoint.json"
RULESET_ID_EXPECTED="0eacafce74544ec0a43d8e2c08c4e7ef"
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

export TERM="${TERM:-xterm}"
export QUIET=0
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

assert_matches() {
    local description="$1" pattern="$2" haystack="$3"
    ((TEST_COUNT++))
    if grep -qE -- "$pattern" <<< "$haystack"; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo "    no match for: $pattern"
        ((FAIL_COUNT++))
    fi
}

# =========================================
# Stubbed Rulesets API
# =========================================
EXISTING=0
POST_CALLS=0
PUT_CALLS=0

_cf_ruleset_api () {
    local METHOD=$1
    case "$METHOD" in
        GET)
            if [[ "$EXISTING" -eq 1 ]]; then
                RULESET_CURL_EXIT_CODE=200
                RULESET_API_OUTPUT=$(cat "$FIXTURE")
            else
                RULESET_CURL_EXIT_CODE=404
                RULESET_API_OUTPUT='{"success":false,"errors":[{"code":10000,"message":"not found"}],"result":null}'
            fi
            ;;
        POST)
            ((POST_CALLS++))
            RULESET_CURL_EXIT_CODE=200
            RULESET_API_OUTPUT=$(cat "$FIXTURE")
            ;;
        PUT)
            ((PUT_CALLS++))
            RULESET_CURL_EXIT_CODE=200
            RULESET_API_OUTPUT=$(cat "$FIXTURE")
            ;;
        *)
            RULESET_CURL_EXIT_CODE=200
            RULESET_API_OUTPUT='{}'
            ;;
    esac
    return 0
}

reset_stubs() {
    EXISTING=$1
    POST_CALLS=0
    PUT_CALLS=0
    SKIP_CONFIRM=0
    RULESET_API_OUTPUT=""
    GET_OR_CREATE_RULESET_ID=""
    GET_OR_CREATE_RULESET_JSON=""
    GET_OR_CREATE_WAS_CREATED=0
    CF_APPLIED_RULESET_ID=""
}

OUT_FILE=""
ERR_FILE=""
OUT=""
ERR=""
APPLY_EXIT=0

# Run apply_profile in this shell (never a command substitution, which would
# discard the globals it reports) and capture the two streams separately.
run_apply() {
    local zone=$1
    local answer=${2:-}

    OUT_FILE=$(mktemp)
    ERR_FILE=$(mktemp)

    if [[ -n "$answer" ]]; then
        cf_ruleset_apply_profile "$zone" "$RULES_JSON" <<< "$answer" >"$OUT_FILE" 2>"$ERR_FILE"
    else
        cf_ruleset_apply_profile "$zone" "$RULES_JSON" </dev/null >"$OUT_FILE" 2>"$ERR_FILE"
    fi
    APPLY_EXIT=$?

    OUT=$(cat "$OUT_FILE")
    ERR=$(cat "$ERR_FILE")
    rm -f "$OUT_FILE" "$ERR_FILE"
}

RULES_JSON=$(jq -c '[.result.rules[]]' "$FIXTURE")

echo -e "${YELLOW}=== new zone: create and report ===${NC}"

reset_stubs 0
run_apply "1656055ad7d95047bd976710406ad760"

assert_eq "new zone exits 0" "0" "$APPLY_EXIT"
assert_eq "new zone sends one POST" "1" "$POST_CALLS"
assert_eq "new zone sends no PUT" "0" "$PUT_CALLS"
assert_contains "new zone reports the created ruleset" "Created entry point ruleset" "$ERR"
assert_eq "new zone reports the rule count" "1" "$(grep -c 'with 4 rule(s)' <<< "$ERR")"
assert_contains "new zone renders the result table" "UPDATED" "$OUT"
assert_eq "new zone renders four rows" "4" "$(grep -cE '^[0-9]+[[:space:]]' <<< "$OUT")"
assert_contains "new zone dates the ruleset" "updated 2026-10-16 20:32:35" "$OUT"
assert_not_contains "new zone never prompts" "Replace all existing rules?" "$ERR"
assert_eq "new zone exposes the applied ruleset id" "$RULESET_ID_EXPECTED" "$CF_APPLIED_RULESET_ID"
assert_not_contains "new zone does not dump JSON on stdout" '"success":' "$OUT"
assert_not_contains "new zone does not dump expressions on stdout" '"expression":' "$OUT"
assert_not_contains "new zone does not print a bare ruleset id" "$RULESET_ID_EXPECTED" "$OUT"

echo ""
echo -e "${YELLOW}=== existing zone: preview, accept, report ===${NC}"

reset_stubs 1
run_apply "1656055ad7d95047bd976710406ad760" "y"

assert_eq "accepted replacement exits 0" "0" "$APPLY_EXIT"
assert_eq "accepted replacement sends one PUT" "1" "$PUT_CALLS"
assert_matches "existing rule count is numeric" 'already has [0-9]+ rule\(s\)' "$ERR"
assert_not_contains "existing rule count is not blank" "already has  rule(s)" "$ERR"
assert_contains "preview shows the numeric count" "already has 4 rule(s)" "$ERR"
assert_contains "preview names the profile count" "The profile contains 4 rule(s)" "$ERR"
assert_contains "preview renders a table on stderr" "ACTION" "$ERR"
assert_contains "preview dates the rules" "2026-10-16 20:32:35" "$ERR"
assert_contains "result table goes to stdout" "UPDATED" "$OUT"
assert_eq "result table has four rows" "4" "$(grep -cE '^[0-9]+[[:space:]]' <<< "$OUT")"
assert_contains "result reports the replaced count" "Replaced 4 rule(s) in ruleset" "$ERR"
assert_not_contains "accepted replacement does not dump JSON on stdout" '"success":' "$OUT"

echo ""
echo -e "${YELLOW}=== existing zone: decline ===${NC}"

reset_stubs 1
run_apply "1656055ad7d95047bd976710406ad760" "n"

assert_eq "declined replacement exits 1" "1" "$APPLY_EXIT"
assert_eq "declined replacement sends no PUT" "0" "$PUT_CALLS"
assert_contains "declined replacement says it was cancelled" "Operation cancelled" "$ERR"
assert_eq "declined replacement keeps stdout empty" "" "$OUT"

echo ""
echo -e "${YELLOW}=== existing zone: --yes ===${NC}"

reset_stubs 1
SKIP_CONFIRM=1
run_apply "1656055ad7d95047bd976710406ad760"

assert_eq "skip-confirm exits 0" "0" "$APPLY_EXIT"
assert_eq "skip-confirm sends one PUT" "1" "$PUT_CALLS"
assert_not_contains "skip-confirm prints no preview" "already has" "$ERR"
assert_not_contains "skip-confirm never prompts" "Replace all existing rules?" "$ERR"
assert_contains "skip-confirm still renders the result table" "UPDATED" "$OUT"
assert_eq "skip-confirm renders four rows" "4" "$(grep -cE '^[0-9]+[[:space:]]' <<< "$OUT")"
SKIP_CONFIRM=0

echo ""
echo -e "${YELLOW}=== entry point with no rules ===${NC}"

EMPTY_FIXTURE='{"result":{"id":"rs-empty","name":"default","phase":"http_request_firewall_custom","version":"1","last_updated":"2026-01-01T00:00:00Z","rules":[]},"success":true,"errors":[],"messages":[]}'
reset_stubs 1
_cf_ruleset_api () {
    local METHOD=$1
    case "$METHOD" in
        GET|PUT)
            [[ "$METHOD" == "PUT" ]] && ((PUT_CALLS++))
            RULESET_CURL_EXIT_CODE=200
            RULESET_API_OUTPUT="$EMPTY_FIXTURE"
            ;;
        *)
            POST_CALLS=$((POST_CALLS + 1))
            RULESET_CURL_EXIT_CODE=200
            RULESET_API_OUTPUT="$EMPTY_FIXTURE"
            ;;
    esac
    return 0
}
run_apply "zone-empty" "y"

assert_matches "empty entry point reports a numeric zero count" 'already has 0 rule\(s\)' "$ERR"
assert_contains "empty entry point explains the result" "No WAF custom rules" "$OUT"
assert_not_contains "empty entry point prints no table header" "UPDATED" "$OUT"

# Restore the stub used by the scenarios above.
# shellcheck source=../inc/cf-inc-rulesets.sh
source "$REPO_DIR/inc/cf-inc-rulesets.sh"

echo ""
echo -e "${YELLOW}=== Summary ===${NC}"
echo "Tests:  $TEST_COUNT"
if [[ "$FAIL_COUNT" -eq 0 ]]; then
    echo -e "${GREEN}Passed: $PASS_COUNT${NC}"
    echo "All apply-profile tests passed."
    exit 0
else
    echo -e "${RED}Failed: $FAIL_COUNT${NC} (passed $PASS_COUNT)"
    exit 1
fi
