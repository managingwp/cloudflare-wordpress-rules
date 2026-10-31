#!/usr/bin/env bash
# =====================================================================
# test-cfwr-wrapper.sh
# Offline tests for cfwr.sh — the version chooser in front of
# cfwrv1.sh (stable) and cfwrv2.sh (the refactor).
#
# No credentials and no network: every case stops before Cloudflare is
# contacted, and the profile commands read the repo's profiles/.
#
# Usage:
#   bash tests/test-cfwr-wrapper.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")
CFWR="$REPO_DIR/cfwr.sh"

TEST_COUNT=0
PASS_COUNT=0
FAIL_COUNT=0

NC='\033[0m'
GREEN='\033[0;32m'
RED='\033[0;31m'

WORK=$(mktemp -d "${TMPDIR:-/tmp}/cfwr-test.XXXXXX")
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

# run_cfwr [env assignments…] -- <args…> : stdin is never a TTY here, so the
# chooser takes its non-interactive path.
run_cfwr() {
    local -a env_args=()
    while [[ $1 != "--" ]]; do
        env_args+=("$1")
        shift
    done
    shift
    env "${env_args[@]}" NO_COLOR=1 TERM=xterm-256color \
        bash "$CFWR" "$@" >"$WORK/out" 2>"$WORK/err" </dev/null
    echo "$?"
}

stdout_of() { cat "$WORK/out"; }
stderr_of() { cat "$WORK/err"; }

# =========================================
# 1. The chooser's own help
# =========================================
rc=$(run_cfwr -- -h)
assert_eq "help exits 0" "0" "$rc"
assert_eq "help keeps stdout empty" "" "$(stdout_of)"
assert_contains "help names v1" "cfwrv1.sh" "$(stderr_of)"
assert_contains "help names v2" "cfwrv2.sh" "$(stderr_of)"
assert_contains "help documents the forcing flag" "-v2, --v2" "$(stderr_of)"
assert_contains "help documents the env override" "CWR_VERSION=1|2" "$(stderr_of)"
assert_contains "help says v2 is in progress" "refactor" "$(stderr_of)"
assert_eq "help is free of ANSI escapes" "0" "$(stderr_of | grep -c "$(printf '\033')")"

# =========================================
# 2. Forced routing
# =========================================
rc=$(run_cfwr -- -v2 list-profiles)
assert_eq "-v2 exits 0" "0" "$rc"
assert_eq "-v2 keeps stdout empty (v2 writes to stderr)" "" "$(stdout_of)"
assert_contains "-v2 reaches v2" "mwp-rules-v207.json" "$(stderr_of)"

rc=$(run_cfwr -- -v1 -c list-profiles)
assert_eq "-v1 exits 0" "0" "$rc"
assert_contains "-v1 reaches v1" "mwp-rules-v207.json" "$(stdout_of)"

rc=$(run_cfwr -- --v2 validate-profile no-such-profile)
assert_eq "arguments pass through to v2" "1" "$rc"
assert_contains "v2 reported the missing profile" "Profile not found" "$(stderr_of)"

# v1 has no positional command form; the chooser supplies -c
rc=$(run_cfwr -- -v1 list-profiles)
assert_eq "-v1 accepts the positional command form" "0" "$rc"
assert_contains "-v1 positional form resolved the command" "mwp-rules-v207.json" "$(stdout_of)"

# -h after a version flag belongs to that script
rc=$(run_cfwr -- -v2 -h)
assert_eq "-v2 -h exits 0" "0" "$rc"
assert_contains "-v2 -h shows the v2 command list" "create-rules <profile>" "$(stderr_of)"
assert_eq "-v2 -h stdout is empty" "" "$(stdout_of)"

rc=$(run_cfwr -- -v1 -h)
assert_eq "-v1 -h exits 0" "0" "$rc"
# v1 prints its help on stdout; the stdout-is-data split arrives with v2
assert_contains "-v1 -h shows the v1 usage" "cfwrv1" "$(stdout_of)"

# =========================================
# 3. Environment override and the quiet default
# =========================================
rc=$(run_cfwr CWR_VERSION=2 -- list-profiles)
assert_eq "CWR_VERSION=2 exits 0" "0" "$rc"
assert_eq "CWR_VERSION=2 keeps stdout empty" "" "$(stdout_of)"
assert_contains "CWR_VERSION=2 reaches v2" "mwp-rules-v207.json" "$(stderr_of)"

rc=$(run_cfwr CWR_VERSION=9 -- list-profiles)
assert_eq "an invalid CWR_VERSION exits 2" "2" "$rc"
assert_contains "an invalid CWR_VERSION is explained" "CWR_VERSION must be 1 or 2" "$(stderr_of)"

rc=$(run_cfwr -- list-profiles)
assert_eq "no version flag exits 0" "0" "$rc"
assert_contains "the default run reaches v1" "mwp-rules-v207.json" "$(stdout_of)"
assert_contains "the default run says how to force v2" "force v2 with -v2" "$(stderr_of)"

# =========================================
# 4. Rejections
# =========================================
rc=$(run_cfwr -- -v3 list-profiles)
assert_eq "an unknown version exits 2" "2" "$rc"
assert_contains "an unknown version is named" "Unknown version: -v3" "$(stderr_of)"
assert_eq "an unknown version writes nothing to stdout" "" "$(stdout_of)"

# =========================================
# 5. The symlinked entry point still routes
# =========================================
rc=$(NO_COLOR=1 bash "$REPO_DIR/cloudflare-wordpress-rules" -v2 validate-profile default >"$WORK/out" 2>"$WORK/err" </dev/null; echo $?)
assert_eq "the cloudflare-wordpress-rules symlink exits 0" "0" "$rc"
assert_contains "the symlink reaches v2" "Profile validation passed" "$(stderr_of)"

rc=$(NO_COLOR=1 bash "$REPO_DIR/cfwpr" -h >"$WORK/out" 2>"$WORK/err" </dev/null; echo $?)
assert_eq "the cfwpr symlink exits 0" "0" "$rc"
assert_contains "the cfwpr symlink shows the chooser help" "cfwrv2.sh" "$(stderr_of)"

# =========================================
# Summary
# =========================================
printf '\n%s: %d tests, %d passed, %d failed\n' "$(basename "$0")" "$TEST_COUNT" "$PASS_COUNT" "$FAIL_COUNT"
[[ $FAIL_COUNT -eq 0 ]]
