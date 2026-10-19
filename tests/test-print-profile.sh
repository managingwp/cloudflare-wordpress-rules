#!/usr/bin/env bash
# =====================================================================
# test-print-profile.sh
# Offline tests for cf_print_profile output.
#
# Covers:
#   * cf_print_profile        — v3 "Action Parameters" block renders
#   * cf_print_profile        — no jq undefined-variable errors
#
# Regression guard for the single-quoted `.rules[$i]` filter that made
# jq treat `$i` as an undefined jq variable.
#
# No Cloudflare API access or credentials required.
#
# Usage:
#   bash tests/test-print-profile.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

export PROFILE_DIR="$REPO_DIR/profiles"
# Color helpers call tput, which needs a terminal type
export TERM="${TERM:-xterm}"

# Message helpers + colors
source "$REPO_DIR/inc/cf-inc.sh"
# Profile resolution helpers + cf_print_profile
source "$REPO_DIR/inc/cf-inc-wp.sh"

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

echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Print Profile Tests${NC}"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"

# -- cf_print_profile on a v3 profile with action_parameters
PRINT_OUTPUT=$(cf_print_profile default 2>&1)

assert_eq "print: action parameters block appears exactly once" \
    "1" "$(printf '%s\n' "$PRINT_OUTPUT" | grep -c 'Action Parameters:')"
assert_eq "print: no jq undefined-variable error" \
    "0" "$(printf '%s\n' "$PRINT_OUTPUT" | grep -c 'is not defined')"
assert_contains "print: action parameters contain ruleset value" \
    '"ruleset": "current"' "$PRINT_OUTPUT"

echo ""
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo "  Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"

[[ $FAIL_COUNT -eq 0 ]]
