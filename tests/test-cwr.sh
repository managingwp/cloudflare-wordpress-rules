#!/usr/bin/env bash
# =====================================================================
# test-cwr.sh
# Offline tests for v2/cwr.sh — the bash-ui rewrite of the WAF CLI.
#
# No credentials and no network: tests/cwr/curl stands in for curl and
# answers from tests/cwr/*.json, so the whole create/list/delete path
# runs. Request bodies are captured and compared with the v1 script.
#
# Usage:
#   bash tests/test-cwr.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")
CWR="$REPO_DIR/v2/cwr.sh"
V1="$REPO_DIR/cloudflare-wordpress-rules.sh"
STUB_DIR="$SCRIPT_DIR/cwr"
ENTRYPOINT_FIXTURE="$SCRIPT_DIR/cf-ruleset-entrypoint.json"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/cwr-test.XXXXXX")
trap 'rm -rf "$WORK"' EXIT

# =========================================
# Test framework
# =========================================
assert_eq() {
    local description="$1" expected="$2" actual="$3"
    ((TEST_COUNT++))
    if [[ "$expected" == "$actual" ]]; then
        printf '%b%s%s\n' "$GREEN" "✓ PASS$NC: $description"
        ((PASS_COUNT++))
    else
        printf '%b%s%s\n' "$RED" "✗ FAIL$NC: $description"
        printf '    expected: %q\n    actual:   %q\n' "$expected" "$actual"
        ((FAIL_COUNT++))
    fi
}

assert_contains() {
    local description="$1" needle="$2" haystack="$3"
    ((TEST_COUNT++))
    if [[ "$haystack" == *"$needle"* ]]; then
        printf '%b%s%s\n' "$GREEN" "✓ PASS$NC: $description"
        ((PASS_COUNT++))
    else
        printf '%b%s%s\n' "$RED" "✗ FAIL$NC: $description"
        printf '    missing: %q\n' "$needle"
        ((FAIL_COUNT++))
    fi
}

assert_not_contains() {
    local description="$1" needle="$2" haystack="$3"
    ((TEST_COUNT++))
    if [[ "$haystack" != *"$needle"* ]]; then
        printf '%b%s%s\n' "$GREEN" "✓ PASS$NC: $description"
        ((PASS_COUNT++))
    else
        printf '%b%s%s\n' "$RED" "✗ FAIL$NC: $description"
        printf '    unexpected: %q\n' "$needle"
        ((FAIL_COUNT++))
    fi
}

# =========================================
# Harness: a stub curl, a credentials file and a request log
# =========================================
CREDS="$WORK/cloudflare"
cat >"$CREDS" <<'EOF'
CF_TOKEN_TEST=test_token_value
EOF

run_cwr() {
    # run_cwr <entrypoint-mode> <args…>
    local mode=$1
    shift
    : >"$WORK/curl.log"
    PATH="$STUB_DIR:$PATH" \
        NO_COLOR=1 \
        TERM=xterm-256color \
        CWR_CURL_LOG="$WORK/curl.log" \
        CWR_ZONE_JSON="$STUB_DIR/zone.json" \
        CWR_CREATED_JSON="$STUB_DIR/created.json" \
        CWR_ENTRYPOINT_JSON="$ENTRYPOINT_FIXTURE" \
        CWR_ENTRYPOINT_MODE="$mode" \
        bash "$CWR" --config "$CREDS" "$@" >"$WORK/out" 2>"$WORK/err"
    echo "$?"
}

stdout_of() { cat "$WORK/out"; }
stderr_of() { cat "$WORK/err"; }
log_of() { cat "$WORK/curl.log"; }

# =========================================
# 1. Help and argument surface
# =========================================
rc=$(run_cwr missing -h)
assert_eq "help exits 0" "0" "$rc"
assert_eq "help writes nothing to stdout" "" "$(stdout_of)"
assert_contains "help lists the rule commands" "create-rules <profile>" "$(stderr_of)"
assert_contains "help names the vendored library" "bash-ui" "$(stderr_of)"
assert_eq "help is free of ANSI escapes" "0" "$(stderr_of | grep -c "$(printf '\033')")"

rc=$(run_cwr missing -c not-a-command)
assert_eq "unknown command exits 1" "1" "$rc"
assert_contains "unknown command is reported" "Unknown command: not-a-command" "$(stderr_of)"

rc=$(run_cwr missing -c list-rules -d example.com --json --csv)
assert_eq "two output formats are rejected" "2" "$rc"
assert_contains "format conflict is explained" "Choose only one of --json, --csv or --raw" "$(stderr_of)"

rc=$(run_cwr missing -d example.com)
assert_eq "missing command exits 1" "1" "$rc"

# =========================================
# 2. Profile commands (offline)
# =========================================
rc=$(run_cwr missing list-profiles)
assert_eq "list-profiles exits 0" "0" "$rc"
assert_eq "list-profiles keeps stdout empty" "" "$(stdout_of)"
assert_contains "list-profiles lists the profiles" "block-event-calendar.json" "$(stderr_of)"
assert_contains "list-profiles reads the shared profiles dir" "mwp-rules-v207.json" "$(stderr_of)"

rc=$(run_cwr missing print-profile default)
assert_eq "print-profile exits 0" "0" "$rc"
assert_contains "print-profile prints to stdout" "Profile: default" "$(stdout_of)"
assert_contains "print-profile lists rules" "Rule 1:" "$(stdout_of)"
assert_eq "print-profile keeps stderr empty" "" "$(stderr_of)"

rc=$(run_cwr missing validate-profile default)
assert_eq "validate-profile passes for default" "0" "$rc"
assert_eq "validate-profile keeps stdout empty" "" "$(stdout_of)"
assert_contains "validate-profile reports success" "Profile validation passed" "$(stderr_of)"

rc=$(run_cwr missing validate-profile no-such-profile)
assert_eq "validate-profile fails for an unknown profile" "1" "$rc"
assert_contains "unknown profile is reported" "Profile not found" "$(stderr_of)"

# The positional form must behave exactly like -c
run_cwr missing list-profiles >/dev/null
positional=$(stderr_of)
run_cwr missing -c list-profiles >/dev/null
assert_eq "positional and -c forms match" "$(stderr_of)" "$positional"

# =========================================
# 3. list-rules output formats
# =========================================
rc=$(run_cwr present -c list-rules -d example.com)
assert_eq "list-rules table exits 0" "0" "$rc"
assert_eq "table keeps stdout empty" "" "$(stdout_of)"
assert_contains "table renders on stderr" "ACTION" "$(stderr_of)"
assert_contains "table names the zone" "example.com" "$(stderr_of)"

rc=$(run_cwr present -c list-rules -d example.com --long)
assert_eq "list-rules --long exits 0" "0" "$rc"
assert_contains "--long shows expressions" "expression:" "$(stderr_of)"

rc=$(run_cwr present -c list-rules -d example.com --json)
assert_eq "list-rules --json exits 0" "0" "$rc"
assert_eq "--json domain" "example.com" "$(stdout_of | jq -r '.domain')"
assert_eq "--json zone id" "0123456789abcdef0123456789abcdef" "$(stdout_of | jq -r '.zone_id')"
assert_contains "--json carries the rules" "R1V207" "$(stdout_of)"

rc=$(run_cwr present -c list-rules -d example.com --csv)
assert_eq "list-rules --csv exits 0" "0" "$rc"
assert_eq "--csv header" \
    "domain,zone_id,position,rule_id,action,enabled,logging,description,expression" \
    "$(stdout_of | head -1)"
assert_contains "--csv data rows" "example.com" "$(stdout_of | sed -n 2p)"

rc=$(run_cwr present -c list-rules -d example.com --raw)
assert_eq "list-rules --raw exits 0" "0" "$rc"
assert_eq "--raw returns the API body" \
    "$(jq -S . "$ENTRYPOINT_FIXTURE")" \
    "$(stdout_of | jq -S .)"

# =========================================
# 4. create-rules: request payload
# =========================================
rc=$(run_cwr missing -c create-rules default -d example.com)
assert_eq "create-rules exits 0" "0" "$rc"
assert_contains "create-rules creates a ruleset" "POST https://api.cloudflare.com/client/v4/zones/0123456789abcdef0123456789abcdef/rulesets" "$(log_of)"

posted=$(sed -n 's|^POST [^ ]* ||p' "$WORK/curl.log" | tail -1)
assert_eq "create-rules posts a zone ruleset" \
    "zone" \
    "$(printf '%s' "$posted" | jq -r '.kind')"
assert_eq "create-rules uses the WAF custom phase" \
    "http_request_firewall_custom" \
    "$(printf '%s' "$posted" | jq -r '.phase')"
assert_eq "create-rules posts all four rules" \
    "4" \
    "$(printf '%s' "$posted" | jq -r '.rules | length')"
assert_eq "create-rules numbers the rule positions" \
    "0 1 2 3" \
    "$(printf '%s' "$posted" | jq -r '[.rules[].position.index] | join(" ")')"
assert_contains "create-rules keeps the R1 description" \
    "R1V207" \
    "$(printf '%s' "$posted" | jq -r '.rules[0].description')"

# =========================================
# 5. delete-rule: -y skips the prompt
# =========================================
rc=$(run_cwr present -c delete-rule aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa -d example.com -y)
assert_eq "delete-rule -y exits 0" "0" "$rc"
assert_contains "delete-rule asks Cloudflare" "DELETE " "$(log_of)"
assert_not_contains "delete-rule -y does not prompt" "Delete rule" "$(stderr_of)"

# =========================================
# 6. Parity with the v1 script (same stub, same zone)
# =========================================
if [[ -f $V1 ]]; then
    v1_out=$(PATH="$STUB_DIR:$PATH" TERM=xterm-256color \
        CWR_CURL_LOG="$WORK/curl.log" \
        CWR_ZONE_JSON="$STUB_DIR/zone.json" \
        CWR_CREATED_JSON="$STUB_DIR/created.json" \
        CWR_ENTRYPOINT_JSON="$ENTRYPOINT_FIXTURE" \
        CWR_ENTRYPOINT_MODE=present \
        bash "$V1" --config "$CREDS" -c list-rules -d example.com --json 2>/dev/null)
    run_cwr present -c list-rules -d example.com --json >/dev/null
    assert_eq "list-rules --json matches the v1 output" \
        "$(printf '%s' "$v1_out" | jq -S .)" \
        "$(stdout_of | jq -S .)"

    # Same command, same stub: the POST body must be byte-identical
    PATH="$STUB_DIR:$PATH" TERM=xterm-256color \
        CWR_CURL_LOG="$WORK/v1.log" \
        CWR_ZONE_JSON="$STUB_DIR/zone.json" \
        CWR_CREATED_JSON="$STUB_DIR/created.json" \
        CWR_ENTRYPOINT_JSON="$ENTRYPOINT_FIXTURE" \
        CWR_ENTRYPOINT_MODE=missing \
        bash "$V1" --config "$CREDS" -c create-rules default -d example.com >/dev/null 2>&1
    v1_posted=$(sed -n 's|^POST [^ ]* ||p' "$WORK/v1.log" | tail -1)

    run_cwr missing -c create-rules default -d example.com >/dev/null
    v2_posted=$(sed -n 's|^POST [^ ]* ||p' "$WORK/curl.log" | tail -1)
    assert_eq "create-rules payload matches the v1 payload" \
        "$(printf '%s' "$v1_posted" | jq -S .)" \
        "$(printf '%s' "$v2_posted" | jq -S .)"
else
    printf 'Skipping v1 parity: %s not found\n' "$V1" >&2
fi

# =========================================
# Summary
# =========================================
printf '\n%s: %d tests, %d passed, %d failed\n' "$(basename "$0")" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
