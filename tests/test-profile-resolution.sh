#!/usr/bin/env bash
# =====================================================================
# test-profile-resolution.sh
# Offline tests for profile selector resolution and listing.
#
# Covers:
#   * _cf_profile_path         — filename-first, then internal .name
#   * _cf_profile_display_name — symlink basename vs .name
#   * cf_list_profiles         — `default` shows distinctly (no duplicate)
#
# No Cloudflare API access or credentials required.
#
# Usage:
#   bash tests/test-profile-resolution.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

export PROFILE_DIR="$REPO_DIR/profiles"

# Message helpers + colors
source "$REPO_DIR/inc/cf-inc.sh"
# Profile resolution helpers + cf_list_profiles
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

assert_fails() {
    local description="$1"
    shift
    ((TEST_COUNT++))

    if "$@" >/dev/null 2>&1; then
        echo -e "${RED}✗ FAIL${NC}: $description (expected non-zero exit)"
        ((FAIL_COUNT++))
    else
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    fi
}

echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo -e "${BLUE}  Profile Resolution Tests${NC}"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"

# -- _cf_profile_path: filename-first resolution
assert_eq "resolver: filename selector resolves to symlink" \
    "$PROFILE_DIR/default.json" "$(_cf_profile_path default)"
assert_eq "resolver: versioned filename resolves directly" \
    "$PROFILE_DIR/mwp-rules-v207.json" "$(_cf_profile_path mwp-rules-v207)"

# -- _cf_profile_path: internal .name fallback
assert_eq "resolver: internal name resolves to file" \
    "$PROFILE_DIR/mwp-rules-v201-events.json" "$(_cf_profile_path default-calendar)"
assert_fails "resolver: unknown selector fails" _cf_profile_path no-such-profile

# -- _cf_profile_display_name
assert_eq "display: symlink uses basename" \
    "default" "$(_cf_profile_display_name "$PROFILE_DIR/default.json")"
assert_eq "display: regular file uses internal name" \
    "default-calendar" "$(_cf_profile_display_name "$PROFILE_DIR/mwp-rules-v201-events.json")"
assert_eq "display: versioned file uses internal name" \
    "mwp-rules-v207" "$(_cf_profile_display_name "$PROFILE_DIR/mwp-rules-v207.json")"

# -- cf_list_profiles: distinct default row, single versioned row
LIST_OUTPUT=$(cf_list_profiles)
assert_contains "list: contains a default row" "default" "$LIST_OUTPUT"
assert_eq "list: mwp-rules-v207 appears exactly once" \
    "1" "$(printf '%s\n' "$LIST_OUTPUT" | grep -cw mwp-rules-v207)"

echo ""
echo -e "${BLUE}══════════════════════════════════════════════${NC}"
echo "  Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
echo -e "${BLUE}══════════════════════════════════════════════${NC}"

[[ $FAIL_COUNT -eq 0 ]]
