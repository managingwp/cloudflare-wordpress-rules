#!/usr/bin/env bash
# =====================================================================
# test-beta-perplexity.sh
# Offline regression tests for the Perplexity allowlist in the beta R1
# skip rule (profiles/mwp-rules-beta.json).
#
# Covers:
#   * R1 allows PerplexityBot and Perplexity-User (case-sensitive)
#   * Both clauses sit before the cf.client.bot clause
#   * R1 stays inside the 4,096-character Free-plan expression limit
#   * R2-R4 expressions are unchanged from the v207 release
#   * R1 still skips the ruleset with the expected action parameters
#   * The docs beta page carries the same clauses
#
# No Cloudflare API access or credentials required; does not modify files.
#
# Usage:
#   bash tests/test-beta-perplexity.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

BETA_JSON="$REPO_DIR/profiles/mwp-rules-beta.json"
V207_JSON="$REPO_DIR/profiles/mwp-rules-v207.json"
BETA_PAGE="$REPO_DIR/docs/reference/beta-rules.md"

EXPRESSION_LIMIT=4096

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

    if printf '%s' "$haystack" | grep -qF -- "$needle"; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  expected to contain: $needle"
        ((FAIL_COUNT++))
    fi
}

assert_lt() {
    local description="$1" actual="$2" limit="$3"
    ((TEST_COUNT++))

    if [[ "$actual" =~ ^[0-9]+$ && "$actual" -lt "$limit" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description ($actual < $limit)"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  expected $actual to be less than $limit"
        ((FAIL_COUNT++))
    fi
}

r1_expression=$(jq -r '.rules[0].expression' "$BETA_JSON")
r1_length=${#r1_expression}
rule_count=$(jq '.rules | length' "$BETA_JSON")

echo -e "${BLUE}=== R1 Perplexity allowlist ===${NC}"
assert_contains "R1 allows PerplexityBot" 'http.user_agent contains "PerplexityBot"' "$r1_expression"
assert_contains "R1 allows Perplexity-User" 'http.user_agent contains "Perplexity-User"' "$r1_expression"
assert_contains "both clauses sit before the cf.client.bot clause" \
    'http.user_agent contains "PerplexityBot") or (http.user_agent contains "Perplexity-User") or (cf.client.bot)' \
    "$r1_expression"
assert_eq "beta profile keeps four rules" "4" "$rule_count"
assert_lt "R1 expression stays under the Free-plan limit" "$r1_length" "$EXPRESSION_LIMIT"

echo ""
echo -e "${BLUE}=== R1 action parameters ===${NC}"
assert_eq "R1 action is skip" "skip" "$(jq -r '.rules[0].action' "$BETA_JSON")"
assert_eq "R1 skips the current ruleset" "current" "$(jq -r '.rules[0].action_parameters.ruleset' "$BETA_JSON")"
assert_eq "R1 is enabled" "true" "$(jq -r '.rules[0].enabled' "$BETA_JSON")"

echo ""
echo -e "${BLUE}=== R2-R4 unchanged from v207 ===${NC}"
for i in 1 2 3; do
    rule_num=$((i + 1))
    assert_eq "R${rule_num} expression matches v207" \
        "$(jq -r ".rules[$i].expression" "$V207_JSON")" \
        "$(jq -r ".rules[$i].expression" "$BETA_JSON")"
done

echo ""
echo -e "${BLUE}=== docs beta page ===${NC}"
beta_page_block=$(awk '
    /<!-- RULES-START -->/ { inblock=1 }
    /<!-- RULES-END -->/   { inblock=0 }
    inblock { print }
' "$BETA_PAGE")
assert_contains "docs beta page allows PerplexityBot" 'PerplexityBot' "$beta_page_block"
assert_contains "docs beta page allows Perplexity-User" 'Perplexity-User' "$beta_page_block"

echo ""
echo -e "${BLUE}=== Results ===${NC}"
echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"
echo "R1 expression length: $r1_length"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
