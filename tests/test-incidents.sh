#!/usr/bin/env bash
# =====================================================================
# test-incidents.sh
# Offline tests for the incident registry (docs/incidents).
#
# Covers:
#   * the registry index exists and every record is listed in it
#   * every record has front matter with the required keys
#   * incident_id format, and its year/month match the filename
#   * the status / severity / confidence / attack_class enums
#   * the anonymisation contract — no `sites:` key, only `site-a`..`site-z`
#   * the eight body sections, present and in schema order
#   * every rule id in `rules:` resolves to a stable or beta profile
#   * the domain sweep — no hostname outside the documentation allowlist
#
# No network access, no Cloudflare credentials; does not modify files.
#
# Usage:
#   bash tests/test-incidents.sh
#   bash tests/test-incidents.sh --self-test                # prove the guard trips
#   INCIDENTS_DIR=/tmp/fixture bash tests/test-incidents.sh  # run against a fixture
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

INCIDENTS_DIR="${INCIDENTS_DIR:-$REPO_DIR/docs/incidents}"
INDEX_FILE="$INCIDENTS_DIR/index.md"
PROFILES_DIR="$REPO_DIR/profiles"

# Closed vocabularies — see docs/reference/incident-schema.md.
STATUS_VALUES="active contained historical"
SEVERITY_VALUES="low medium high critical"
CONFIDENCE_VALUES="observed provider-reported inferred"
ATTACK_CLASSES="cache-busting-flood credential-stuffing scraper-flood referral-flood xmlrpc-abuse upload-probe comment-spam crawler-misbehaviour other"

# Hostnames that may legitimately appear in a record: documentation
# examples and the platforms whose links started the traffic.
HOST_ALLOWLIST="example\.com|linkedin\.com|cloudflare\.com"

REQUIRED_KEYS="title description incident_id status attack_class first_seen last_seen severity instances confidence tags"

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

# Print only the front matter block of a Markdown file.
front_matter() {
    awk 'NR == 1 && $0 != "---" { exit }
         NR == 1 { next }
         $0 == "---" { exit }
         { print }' "$1"
}

# Print the value of one front-matter key, trimmed.
fm_value() {
    front_matter "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | sed 's/[[:space:]]*$//'
}

# Membership test against a space-separated vocabulary.
in_vocab() {
    local value="$1" vocab="$2"
    [[ " $vocab " == *" $value "* ]]
}

# --self-test: prove the guard rejects a record that names a hostname.
# Builds a fixture from the live registry, injects a violation, and expects
# this same script to fail against it. Exits 0 when the guard trips.
if [[ "${1:-}" == "--self-test" ]]; then
    fixture=$(mktemp -d)
    trap 'rm -rf "$fixture"' EXIT
    cp "$INCIDENTS_DIR"/*.md "$fixture"/ 2>/dev/null || true
    cat > "$fixture/2026-01-bad.md" <<'FIXTURE'
---
title: Bad fixture
description: A record that names a hostname instead of a placeholder.
incident_id: INC-2026-01-01-01
status: active
attack_class: scraper-flood
first_seen: 2026-01-01
last_seen: 2026-01-01
severity: low
instances:
  - { date: 2026-01-01, site_ref: acme-corp.org }
confidence: observed
tags: [fixture]
---

## Summary

Fixture.
FIXTURE
    if INCIDENTS_DIR="$fixture" "$BASH" "$0" >/dev/null 2>&1; then
        echo "FAIL: the guard accepted a record with a hostname in site_ref"
        exit 1
    fi
    echo "ok: the guard rejects a hostname in site_ref"
    exit 0
fi

echo -e "${BLUE}=== registry ===${NC}"
assert_file "the incident index exists" "$INDEX_FILE"

records=()
if [[ -d "$INCIDENTS_DIR" ]]; then
    while IFS= read -r record; do
        records+=("$record")
    done < <(find "$INCIDENTS_DIR" -maxdepth 1 -name '*.md' ! -name 'index.md' | sort)
fi

if [[ "${#records[@]}" -eq 0 ]]; then
    pass "the registry has no records yet (nothing to validate)"
else
    pass "the registry holds ${#records[@]} record(s)"
fi

echo ""
echo -e "${BLUE}=== front matter ===${NC}"

missing_front_matter=""
missing_keys=""
bad_id=""
bad_filename=""
bad_status=""
bad_severity=""
bad_confidence=""
bad_class=""
sites_key=""
bad_site_ref=""
bad_sections=""
bad_rules=""
missing_from_index=""

for file in "${records[@]}"; do
    name=$(basename "$file")
    fm=$(front_matter "$file")

    if [[ "$(head -1 "$file")" != "---" ]] || [[ -z "$fm" ]]; then
        missing_front_matter+="$name "
        continue
    fi

    for key in $REQUIRED_KEYS; do
        printf '%s\n' "$fm" | grep -q "^$key:" || missing_keys+="$name:$key "
    done

    id=$(fm_value "$file" "incident_id")
    if [[ ! "$id" =~ ^INC-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}$ ]]; then
        bad_id+="$name($id) "
    else
        # INC-YYYY-MM-DD-NN must agree with the <YYYY>-<MM> filename prefix.
        if [[ "${id:4:4}-${id:9:2}" != "${name:0:7}" ]]; then
            bad_filename+="$name($id) "
        fi
    fi

    in_vocab "$(fm_value "$file" status)" "$STATUS_VALUES" || bad_status+="$name($(fm_value "$file" status)) "
    in_vocab "$(fm_value "$file" severity)" "$SEVERITY_VALUES" || bad_severity+="$name($(fm_value "$file" severity)) "
    in_vocab "$(fm_value "$file" confidence)" "$CONFIDENCE_VALUES" || bad_confidence+="$name($(fm_value "$file" confidence)) "
    in_vocab "$(fm_value "$file" attack_class)" "$ATTACK_CLASSES" || bad_class+="$name($(fm_value "$file" attack_class)) "

    # A client identifies as a placeholder, never as a domain.
    printf '%s\n' "$fm" | grep -q '^sites:' && sites_key+="$name "
    if ! printf '%s\n' "$fm" | grep -q '^[[:space:]]*\(instances:\|-\|{\)'; then
        bad_site_ref+="$name(no instances) "
    elif ! printf '%s\n' "$fm" | grep -q 'site_ref: *site-[a-z]'; then
        bad_site_ref+="$name "
    elif printf '%s\n' "$fm" | grep 'site_ref:' | grep -qv 'site_ref: *site-[a-z][^a-z]'; then
        bad_site_ref+="$name(non-placeholder) "
    fi

    # The eight sections, as a subsequence of the record's ## headings.
    order_ok=$(awk '
        BEGIN { n = split("Summary;Signature;Evidence;Why it worked;Mitigation;Do not block;Origin fix;Detection", want, ";"); i = 1 }
        /^## / {
            heading = substr($0, 4)
            sub(/[[:space:]]+$/, "", heading)
            if (i <= n && heading == want[i]) i++
        }
        END { print (i > n) ? "ok" : "bad" }
    ' "$file")
    [[ "$order_ok" == "ok" ]] || bad_sections+="$name "

    # `rules:` is a list of ids that must exist in a profile.
    rule_line=$(printf '%s\n' "$fm" | grep '^rules:' | head -1)
    if [[ -n "$rule_line" ]] && [[ "$rule_line" != *"[]"* ]]; then
        for rule_id in $(printf '%s\n' "$rule_line" | grep -oE '[A-Z][0-9]+V[0-9A-Za-z]+'); do
            if ! grep -q "\"$rule_id\"" "$PROFILES_DIR/default.json" "$PROFILES_DIR/mwp-rules-beta.json" 2>/dev/null; then
                bad_rules+="$name:$rule_id "
            fi
        done
    fi

    if [[ -f "$INDEX_FILE" ]]; then
        grep -qF "$name" "$INDEX_FILE" || missing_from_index+="$name "
        [[ -n "$id" ]] && { grep -qF "$id" "$INDEX_FILE" || missing_from_index+="$name(id) "; }
    fi
done

assert_eq "every record has front matter" "" "$missing_front_matter"
assert_eq "every record has the required keys" "" "$missing_keys"
assert_eq "every incident_id matches INC-YYYY-MM-DD-NN" "" "$bad_id"
assert_eq "every incident_id agrees with its filename" "" "$bad_filename"
assert_eq "every status is allowed" "" "$bad_status"
assert_eq "every severity is allowed" "" "$bad_severity"
assert_eq "every confidence is allowed" "" "$bad_confidence"
assert_eq "every attack_class is in the closed list" "" "$bad_class"
assert_eq "no record carries a sites: key" "" "$sites_key"
assert_eq "every record identifies as a site-a..site-z placeholder" "" "$bad_site_ref"
assert_eq "every record carries the eight sections in order" "" "$bad_sections"
assert_eq "every rule id resolves to a profile" "" "$bad_rules"
assert_eq "every record is listed in the index" "" "$missing_from_index"

echo ""
echo -e "${BLUE}=== index ===${NC}"

orphan_index=""
if [[ -f "$INDEX_FILE" ]]; then
    for id in $(grep -oE 'INC-[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}' "$INDEX_FILE" | sort -u); do
        found=0
        for file in "${records[@]}"; do
            [[ "$(fm_value "$file" incident_id)" == "$id" ]] && found=1
        done
        [[ "$found" -eq 1 ]] || orphan_index+="$id "
    done
fi
assert_eq "every id in the index resolves to a record" "" "$orphan_index"

echo ""
echo -e "${BLUE}=== confidentiality ===${NC}"

offending_hosts=""
if [[ -d "$INCIDENTS_DIR" ]]; then
    offending_hosts=$(grep -rnoE '\b[a-z0-9-]+\.(com|org|net|io|ca|co\.uk)\b' "$INCIDENTS_DIR" \
        | grep -vE ":(${HOST_ALLOWLIST})$")
fi
if [[ -n "$offending_hosts" ]]; then
    echo -e "${RED}hostnames outside the allowlist:${NC}"
    printf '%s\n' "$offending_hosts" | while IFS= read -r hit; do echo "  $hit"; done
fi
assert_eq "no hostname outside the documentation allowlist" "" "$offending_hosts"

echo ""
echo -e "${BLUE}=== Results ===${NC}"
echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
