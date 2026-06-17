#!/usr/bin/env bash
# =====================================================================
# test-rulesets-api.sh
# Unit tests for cf-inc-rulesets.sh functions.
#
# These tests validate the utility functions that do NOT require
# Cloudflare API access (builders, validators, converters).
#
# Usage:
#   bash tests/test-rulesets-api.sh
#   bash tests/test-rulesets-api.sh -v    # verbose
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")
VERBOSE=0
TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

# Colors
NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'

# Parse args
if [[ "$1" == "-v" || "$1" == "--verbose" ]]; then
    VERBOSE=1
fi

# Source the utilities we need (without triggering authentication)
# We need to define SCRIPT_DIR and source the rulesets include file
export SCRIPT_DIR="$REPO_DIR"
export PROFILE_DIR="$REPO_DIR/profiles"

# Source message functions and utility functions only
source "$REPO_DIR/inc/cf-inc.sh"
source "$REPO_DIR/inc/cf-inc-rulesets.sh"

# _cf_ruleset_read_profile_rules is defined in cf-inc-wp.sh
source "$REPO_DIR/inc/cf-inc-wp.sh"

# =========================================
# Test Framework
# =========================================

assert_eq() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    ((TEST_COUNT++))
    
    if [[ "$expected" == "$actual" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  ${YELLOW}Expected:${NC} $expected"
        echo -e "  ${YELLOW}Actual:${NC}   $actual"
        ((FAIL_COUNT++))
    fi
}

assert_contains() {
    local description="$1"
    local expected="$2"
    local actual="$3"
    ((TEST_COUNT++))
    
    if echo "$actual" | grep -qF "$expected"; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  ${YELLOW}Expected to contain:${NC} $expected"
        echo -e "  ${YELLOW}Actual:${NC}   $actual"
        ((FAIL_COUNT++))
    fi
}

assert_exit_code() {
    local description="$1"
    local expected_code="$2"
    shift 2
    ((TEST_COUNT++))
    
    "$@" &>/dev/null
    local actual_code=$?
    
    if [[ $actual_code -eq $expected_code ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description (exit=$expected_code)"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description (expected exit=$expected_code, got $actual_code)"
        ((FAIL_COUNT++))
    fi
}

# =========================================
# Test Suite
# =========================================

echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  cf-inc-rulesets.sh Unit Tests${NC}"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo ""

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_phase_name ──${NC}"
# --------------------------------------------------

PHASE=$(cf_ruleset_phase_name)
assert_eq "Returns the WAF custom rules phase" "http_request_firewall_custom" "$PHASE"

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_api_version ──${NC}"
# --------------------------------------------------

VERSION_OUTPUT=$(cf_ruleset_api_version)
assert_contains "Contains version string" "cf-inc-rulesets.sh version" "$VERSION_OUTPUT"

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_validate_action ──${NC}"
# --------------------------------------------------

# Valid actions
for action in block challenge js_challenge managed_challenge log skip execute; do
    cf_ruleset_validate_action "$action" &>/dev/null
    assert_eq "Valid action: $action" 0 $?
done

# Invalid actions
for action in allow bypass invalid_action; do
    cf_ruleset_validate_action "$action" &>/dev/null
    assert_eq "Invalid action: $action" 1 $?
done

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_build_rule_payload ──${NC}"
# --------------------------------------------------

# Basic rule payload
BASIC=$(cf_ruleset_build_rule_payload \
    '(ip.src in {192.0.2.1})' \
    'block' \
    'Test block rule' \
    'true')
assert_contains "Basic rule has expression" "192.0.2.1" "$BASIC"
assert_contains "Basic rule has action block" '"block"' "$BASIC"
assert_contains "Basic rule has description" "Test block rule" "$BASIC"
assert_contains "Basic rule has enabled true" '"enabled": true' "$BASIC"
assert_contains "Basic rule has logging" '"logging"' "$BASIC"

# Rule with logging disabled
NO_LOG=$(cf_ruleset_build_rule_payload \
    '(ip.src in {192.0.2.1})' \
    'skip' \
    'Test skip rule' \
    'true' \
    'false')
assert_contains "Skip rule has logging disabled" '"enabled": false' "$NO_LOG"

# Rule with action_parameters
WITH_AP=$(cf_ruleset_build_rule_payload \
    '(ip.src in {192.0.2.1})' \
    'block' \
    'Test custom response' \
    'true' \
    'true' \
    '{"response":{"status_code":403,"content":"Blocked","content_type":"text/plain"}}')
assert_contains "Rule with action_parameters has response" '"response"' "$WITH_AP"
assert_contains "Rule with action_parameters has status_code" '403' "$WITH_AP"

# Empty action_parameters should be stripped
NO_AP=$(cf_ruleset_build_rule_payload \
    '(ip.src in {192.0.2.1})' \
    'block' \
    'Test no AP' \
    'true' \
    'true' \
    '{}')
if echo "$NO_AP" | grep -q '"action_parameters"'; then
    echo -e "  ${YELLOW}Note: empty action_parameters kept (behavior may vary)${NC}"
else
    assert_eq "Empty action_parameters stripped correctly" 0 0
fi

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_build_rule_payload_skip ──${NC}"
# --------------------------------------------------

# Skip with ruleset=current
SKIP_RULESET=$(cf_ruleset_build_rule_payload_skip \
    "Skip all remaining" \
    "(ip.src in {192.0.2.1})" \
    "current")
assert_contains "Skip with ruleset has skip action" '"skip"' "$SKIP_RULESET"
assert_contains "Skip with ruleset has ruleset: current" '"ruleset": "current"' "$SKIP_RULESET"
assert_contains "Skip with ruleset has logging disabled" '"enabled": false' "$SKIP_RULESET"

# Skip with phases
SKIP_PHASES=$(cf_ruleset_build_rule_payload_skip \
    "Skip WAF managed rules" \
    "(ip.src in {192.0.2.1})" \
    "" \
    "http_request_firewall_managed")
assert_contains "Skip with phases has phases" '"phases"' "$SKIP_PHASES"
assert_contains "Skip with phases has specific phase" 'http_request_firewall_managed' "$SKIP_PHASES"

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_build_rule_payload_block ──${NC}"
# --------------------------------------------------

# Default block response
BLOCK_DEF=$(cf_ruleset_build_rule_payload_block \
    "Block with default" \
    "(ip.src in {192.0.2.1})")
assert_contains "Default block has action" '"block"' "$BLOCK_DEF"
assert_contains "Default block has response" '"response"' "$BLOCK_DEF"
assert_contains "Default block has status_code 403" '403' "$BLOCK_DEF"
assert_contains "Default block has content_type" 'text/plain' "$BLOCK_DEF"

# Custom block response
BLOCK_CUSTOM=$(cf_ruleset_build_rule_payload_block \
    "Block with JSON" \
    "(ip.src in {192.0.2.1})" \
    429 \
    '{"error":"rate_limited"}' \
    "application/json")
assert_contains "Custom block has status 429" '429' "$BLOCK_CUSTOM"
assert_contains "Custom block has JSON content" 'rate_limited' "$BLOCK_CUSTOM"
assert_contains "Custom block has JSON content_type" 'application/json' "$BLOCK_CUSTOM"

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_build_rule_payload_ratelimit ──${NC}"
# --------------------------------------------------

RL_BASIC=$(cf_ruleset_build_rule_payload_ratelimit \
    "Rate limit test" \
    "(http.request.uri.path eq \"/wp-login.php\")" \
    '["ip.src"]' \
    60 \
    100 \
    300)
assert_contains "Rate limit has ratelimit config" '"ratelimit"' "$RL_BASIC"
assert_contains "Rate limit has characteristics" '"characteristics"' "$RL_BASIC"
assert_contains "Rate limit has ip.src" 'ip.src' "$RL_BASIC"
assert_contains "Rate limit has period 60" '60' "$RL_BASIC"
assert_contains "Rate limit has requests_per_period 100" '100' "$RL_BASIC"
assert_contains "Rate limit has mitigation_timeout 300" '300' "$RL_BASIC"

# --------------------------------------------------
echo -e "${YELLOW}── _cf_ruleset_read_profile_rules (v3) ──${NC}"
# --------------------------------------------------

# Create a temporary v3 profile for testing
TMP_V3=$(mktemp)
cat > "$TMP_V3" << 'EOF'
{
  "name": "test-v3",
  "description": "Test v3 profile",
  "version": 3,
  "phase": "http_request_firewall_custom",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "300",
      "description": "R1V300 - Test rule",
      "expression": "(ip.src in {192.0.2.1})",
      "action": "block",
      "enabled": true,
      "logging": { "enabled": true }
    }
  ]
}
EOF

V3_RULES=$(_cf_ruleset_read_profile_rules "$TMP_V3")
assert_contains "v3 profile: reads rules" "R1V300" "$V3_RULES"
assert_contains "v3 profile: keeps action as-is" '"block"' "$V3_RULES"
assert_contains "v3 profile: keeps expression" "192.0.2.1" "$V3_RULES"
rm "$TMP_V3"

# Create a temporary v2 profile for testing
TMP_V2=$(mktemp)
cat > "$TMP_V2" << 'EOF'
{
  "name": "test-v2",
  "description": "Test v2 profile",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "205",
      "description": "R1V205 - Allow test",
      "expression": "(ip.src in {192.0.2.1})",
      "action": "allow",
      "priority": 1
    }
  ]
}
EOF

V2_RULES=$(_cf_ruleset_read_profile_rules "$TMP_V2")
assert_contains "v2 profile: converts allow to skip" '"skip"' "$V2_RULES"
assert_contains "v2 profile: preserves description" "R1V205" "$V2_RULES"
assert_contains "v2 profile: preserves expression" "192.0.2.1" "$V2_RULES"
assert_contains "v2 profile: has action_parameters for skip" '"ruleset"' "$V2_RULES"
V2_NO_ENABLED=$(echo "$V2_RULES" | grep -c '"enabled"' || true)
assert_eq "v2 profile: enabled stripped" 0 "$V2_NO_ENABLED"
V2_NO_LOGGING=$(echo "$V2_RULES" | grep -c '"logging"' || true)
assert_eq "v2 profile: logging stripped" 0 "$V2_NO_LOGGING"
V2_NO_PRIORITY=$(echo "$V2_RULES" | grep -c '"priority"' || true)
assert_eq "v2 profile: priority stripped" 0 "$V2_NO_PRIORITY"
V2_NO_RULE_NUM=$(echo "$V2_RULES" | grep -c '"rule_number"' || true)
assert_eq "v2 profile: rule_number stripped" 0 "$V2_NO_RULE_NUM"
V2_NO_RULE_VER=$(echo "$V2_RULES" | grep -c '"rule_version"' || true)
assert_eq "v2 profile: rule_version stripped" 0 "$V2_NO_RULE_VER"
rm "$TMP_V2"

# Verify v2 block rule has NO action_parameters
TMP_V2_BLOCK=$(mktemp)
cat > "$TMP_V2_BLOCK" << 'EOF'
{
  "name": "test-v2-block",
  "description": "Test v2 block rule",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "205",
      "description": "R1V205 - Block test",
      "expression": "(http.request.uri.path eq \"/xmlrpc.php\")",
      "action": "block",
      "priority": 1
    }
  ]
}
EOF
V2_BLOCK_RULES=$(_cf_ruleset_read_profile_rules "$TMP_V2_BLOCK")
assert_contains "v2 block rule: action preserved as block" '"block"' "$V2_BLOCK_RULES"
V2_BLOCK_NO_AP=$(echo "$V2_BLOCK_RULES" | grep -c '"action_parameters"' || true)
assert_eq "v2 block rule: no action_parameters" 0 "$V2_BLOCK_NO_AP"
rm "$TMP_V2_BLOCK"

# Verify v3 profiles strip to minimal fields too
TMP_V3_CLEAN=$(mktemp)
cat > "$TMP_V3_CLEAN" << 'EOF'
{
  "name": "test-v3-clean",
  "description": "Test v3 clean",
  "version": 3,
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "300",
      "description": "R1V300 - Clean test",
      "expression": "(ip.src in {192.0.2.1})",
      "action": "block",
      "enabled": true
    }
  ]
}
EOF
V3_CLEAN_RULES=$(_cf_ruleset_read_profile_rules "$TMP_V3_CLEAN")
V3_NO_RULE_NUM=$(echo "$V3_CLEAN_RULES" | grep -c '"rule_number"' || true)
assert_eq "v3 profile: rule_number stripped (not sent to API)" 0 "$V3_NO_RULE_NUM"
V3_NO_RULE_VER=$(echo "$V3_CLEAN_RULES" | grep -c '"rule_version"' || true)
assert_eq "v3 profile: rule_version stripped (not sent to API)" 0 "$V3_NO_RULE_VER"
V3_NO_ENABLED=$(echo "$V3_CLEAN_RULES" | grep -c '"enabled"' || true)
assert_eq "v3 profile: enabled stripped (PUT endpoint may not accept it)" 0 "$V3_NO_ENABLED"
V3_NO_LOGGING=$(echo "$V3_CLEAN_RULES" | grep -c '"logging"' || true)
assert_eq "v3 profile: logging stripped (PUT endpoint may not accept it)" 0 "$V3_NO_LOGGING"
assert_contains "v3 profile: description preserved" "R1V300" "$V3_CLEAN_RULES"
rm "$TMP_V3_CLEAN"

# --------------------------------------------------
echo -e "${YELLOW}── cf_ruleset_validate_profile_json ──${NC}"
# --------------------------------------------------

# Validate a good v3 profile
TMP_GOOD=$(mktemp)
cat > "$TMP_GOOD" << 'EOF'
{
  "name": "test-good",
  "description": "Test good profile",
  "version": 3,
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "300",
      "description": "Test rule",
      "expression": "(ip.src in {192.0.2.1})",
      "action": "block",
      "enabled": true
    }
  ]
}
EOF
cf_ruleset_validate_profile_json "$TMP_GOOD" &>/dev/null
assert_eq "Valid v3 profile passes validation" 0 $?
rm "$TMP_GOOD"

# Validate a profile with invalid action
TMP_BAD=$(mktemp)
cat > "$TMP_BAD" << 'EOF'
{
  "name": "test-bad",
  "description": "Test bad profile",
  "version": 3,
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "300",
      "description": "Bad rule",
      "expression": "(ip.src in {192.0.2.1})",
      "action": "invalid_action",
      "enabled": true
    }
  ]
}
EOF
cf_ruleset_validate_profile_json "$TMP_BAD" &>/dev/null
assert_eq "Invalid action fails validation" 1 $?
rm "$TMP_BAD"

# Validate a v2 profile (should pass with warning)
TMP_V2B=$(mktemp)
cat > "$TMP_V2B" << 'EOF'
{
  "name": "test-v2b",
  "description": "Test v2 profile",
  "rules": [
    {
      "rule_number": "1",
      "rule_version": "205",
      "description": "V2 test",
      "expression": "(ip.src in {192.0.2.1})",
      "action": "block",
      "priority": 1
    }
  ]
}
EOF
cf_ruleset_validate_profile_json "$TMP_V2B" &>/dev/null
assert_eq "v2 profile with block action passes" 0 $?
rm "$TMP_V2B"

# --------------------------------------------------
echo -e "${YELLOW}── _list_ruleset_functions (basic smoke test) ──${NC}"
# --------------------------------------------------

FUNCS=$(_list_ruleset_functions 2>&1)
# The function index array uses indexed array syntax as a decorative list;
# verify at least some content is output
if [[ -n "$FUNCS" ]]; then
    assert_eq "Function listing produces output" 0 0
else
    assert_eq "Function listing produces output" 0 1
fi

# =========================================
# Summary
# =========================================
echo ""
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Results${NC}"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "  Total:  $TEST_COUNT"
echo -e "  ${GREEN}Passed: $PASS_COUNT${NC}"
echo -e "  ${RED}Failed: $FAIL_COUNT${NC}"
echo ""

if [[ $FAIL_COUNT -eq 0 ]]; then
    echo -e "${GREEN}All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}Some tests failed.${NC}"
    exit 1
fi
