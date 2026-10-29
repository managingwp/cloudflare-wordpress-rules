#!/usr/bin/env bash
# =====================================================================
# test-generator.sh
# Offline tests for the static rule generator (website/static/generator).
#
# Covers:
#   * the rule builder and renderers — node --test tests/generator
#   * presets — manifest, schema, `extends` resolution, version drift
#   * static hygiene — no root-absolute paths, no outbound requests,
#     no analytics, CSP present, external ES modules only
#   * optional docs build — /generator/ survives the Docusaurus build
#
# No network access, no Cloudflare credentials; does not modify files.
#
# Usage:
#   bash tests/test-generator.sh
# =====================================================================

set -o pipefail

SCRIPT_DIR=$( cd -- "$( dirname -- "${BASH_SOURCE[0]}" )" &> /dev/null && pwd )
REPO_DIR=$(dirname "$SCRIPT_DIR")

GENERATOR_DIR="$REPO_DIR/website/static/generator"
PROFILES_DIR="$GENERATOR_DIR/profiles"
INDEX_FILE="$PROFILES_DIR/index.json"
HTML_FILE="$GENERATOR_DIR/index.html"
WEBSITE_DIR="$REPO_DIR/website"

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

assert_file() {
    local description="$1" path="$2"
    ((TEST_COUNT++))
    if [[ -f "$path" ]]; then
        echo -e "${GREEN}✓ PASS${NC}: $description"
        ((PASS_COUNT++))
    else
        echo -e "${RED}✗ FAIL${NC}: $description"
        echo -e "  missing: $path"
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

assert_empty() {
    local description="$1" haystack="$2"
    assert_eq "$description" "" "$haystack"
}

command -v node >/dev/null 2>&1 || {
    echo "Error: node is required (>= 20)" >&2
    exit 1
}

# -- node test suite -------------------------------------------------
echo -e "${BLUE}=== rule builder and renderers ===${NC}"
node_test_output="$(node --test "$SCRIPT_DIR"/generator/*.test.mjs 2>&1)"
node_test_status=$?
node_test_summary="$(printf '%s\n' "$node_test_output" | grep -E '^# (tests|pass|fail) ' | tr '\n' ' ')"
assert_eq "node test suite passes (${node_test_summary:-no summary})" "0" "$node_test_status"
if [[ "$node_test_status" -ne 0 ]]; then
    printf '%s\n' "$node_test_output" | grep -E '^not ok|AssertionError|Error:' | head -20
fi

# -- module syntax ---------------------------------------------------
echo ""
echo -e "${BLUE}=== static hygiene ===${NC}"
syntax_errors=""
for file in "$GENERATOR_DIR"/js/*.js; do
    node --check "$file" >/dev/null 2>&1 || syntax_errors+="$(basename "$file") "
done
assert_empty "every js module parses" "$syntax_errors"

assert_file "generator page exists" "$HTML_FILE"
assert_file "preset manifest exists" "$INDEX_FILE"
assert_file "generator package.json exists" "$GENERATOR_DIR/package.json"
assert_contains "generator modules are ES modules" '"type": "module"' "$(cat "$GENERATOR_DIR/package.json")"

root_absolute="$(grep -rnE '(src|href)="/' "$HTML_FILE" "$GENERATOR_DIR/js" 2>/dev/null)"
assert_empty "no root-absolute asset paths (works under a baseUrl)" "$root_absolute"

outbound="$(grep -rnE "fetch\(\s*[\"']https?:" "$GENERATOR_DIR/js" 2>/dev/null)"
assert_empty "no fetch of an absolute URL" "$outbound"

analytics="$(grep -rniE 'googletagmanager|gtag\(|google-analytics|plausible|matomo|segment\.io' \
    "$GENERATOR_DIR" --include='*.js' --include='*.html' 2>/dev/null)"
assert_empty "no analytics snippets" "$analytics"

assert_contains "CSP restricts the page to same-origin assets" \
    "default-src 'self'" "$(cat "$HTML_FILE")"

inline_scripts="$(grep -cE '<script[^>]*>[^<]' "$HTML_FILE")"
assert_eq "external scripts only (CSP-safe)" "0" "$inline_scripts"

inline_styles="$(grep -nE 'style="' "$HTML_FILE" "$GENERATOR_DIR"/js/*.js 2>/dev/null)"
assert_empty "no inline style attributes (style-src 'self')" "$inline_styles"

assert_file "theme boot script exists (pre-paint palette)" "$GENERATOR_DIR/js/theme-boot.js"
assert_file "theme module exists" "$GENERATOR_DIR/js/theme.js"
assert_contains "page offers a theme switch" \
    'data-theme-value="auto"' "$(cat "$HTML_FILE")"
assert_contains "theme switch exposes its pressed state" \
    'aria-pressed' "$(cat "$HTML_FILE")"
assert_contains "stylesheet declares a colour scheme for native controls" \
    "color-scheme: dark" "$(cat "$GENERATOR_DIR/assets/app.css")"

theme_key_module="$(grep -ohE '"cfwpr\.generator\.theme\.v1"' "$GENERATOR_DIR/js/theme.js" | head -1)"
theme_key_boot="$(grep -ohE '"cfwpr\.generator\.theme\.v1"' "$GENERATOR_DIR/js/theme-boot.js" | head -1)"
assert_eq "theme preference key matches in boot script and module" \
    "$theme_key_module" "$theme_key_boot"

assert_contains "page states the client-side guarantee" \
    "No account credentials, no tracking" "$(cat "$HTML_FILE")"

# -- presets ---------------------------------------------------------
echo ""
echo -e "${BLUE}=== presets ===${NC}"
preset_list="$(jq -r '.presets[]' "$INDEX_FILE" 2>/dev/null)"

assert_contains "manifest lists the default preset" "default" "$preset_list"
assert_contains "manifest lists woocommerce" "woocommerce" "$preset_list"
assert_contains "manifest lists strict-geo" "strict-geo" "$preset_list"

missing_presets=""
invalid_presets=""
for name in $preset_list; do
    file="$PROFILES_DIR/$name.json"
    [[ -f "$file" ]] || { missing_presets+="$name "; continue; }
    jq empty "$file" 2>/dev/null || invalid_presets+="$name "
done
assert_empty "every manifest entry has a preset file" "$missing_presets"
assert_empty "every preset file is valid JSON" "$invalid_presets"

template_version="$(jq -r '.templateVersion' "$PROFILES_DIR/default.json")"
profile_version="$(jq -r '.rules[0].rule_version' "$REPO_DIR/profiles/default.json")"
assert_eq "default preset templateVersion tracks profiles/default.json" \
    "$profile_version" "$template_version"

rule_count="$(node -e '
import(process.argv[1]).then(async ({ buildRules }) => {
  const fs = await import("node:fs/promises");
  const preset = JSON.parse(await fs.readFile(process.argv[2], "utf8"));
  console.log(buildRules(preset.options).length);
});
' "$GENERATOR_DIR/js/rules.js" "$PROFILES_DIR/default.json" 2>/dev/null)"
assert_eq "default preset builds four rules" "4" "$rule_count"

# -- optional docs build ---------------------------------------------
echo ""
echo -e "${BLUE}=== docs build passthrough ===${NC}"
docusaurus_bin="$WEBSITE_DIR/node_modules/@docusaurus/core/bin/docusaurus.mjs"
if [[ -f "$WEBSITE_DIR/package.json" && -f "$docusaurus_bin" ]]; then
    # Build into a throwaway directory: never touches website/build, so a local
    # `npm run serve` cannot race the test (and the working tree stays clean).
    # Invoke the CLI through node so a half-written node_modules/.bin shim does
    # not decide the result.
    build_root="$(mktemp -d)"
    trap 'rm -rf "$build_root"' EXIT
    build_dir="$build_root/build"
    build_output="$(cd "$WEBSITE_DIR" && node "$docusaurus_bin" build --out-dir "$build_dir" 2>&1)"
    build_status=$?
    assert_eq "docs site builds with the generator inside static/" "0" "$build_status"
    if [[ "$build_status" -ne 0 ]]; then
        printf '%s\n' "$build_output" | tail -20
    fi
    assert_file "built site contains /generator/ (index)" "$build_dir/generator/index.html"
    assert_file "built site contains /generator/js/app.js" "$build_dir/generator/js/app.js"
    assert_file "built site contains /generator/profiles/index.json" "$build_dir/generator/profiles/index.json"
else
    echo "SKIP: docs site dependencies not installed (run npm --prefix website install to include the build check)"
fi

echo ""
echo -e "${BLUE}=== Results ===${NC}"
echo "Tests: $TEST_COUNT  Passed: $PASS_COUNT  Failed: $FAIL_COUNT"

if [[ "$FAIL_COUNT" -gt 0 ]]; then
    exit 1
fi

exit 0
