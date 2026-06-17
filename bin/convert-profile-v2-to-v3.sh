#!/usr/bin/env bash
# =====================================================================
# convert-profile-v2-to-v3.sh
# Convert a v2 profile JSON to v3 (Rulesets API) format.
#
# Usage:
#   ./bin/convert-profile-v2-to-v3.sh <input.json> [output.json]
#
# If output file is omitted, the v3 profile is printed to stdout.
#
# v2 → v3 changes:
#   - Adds "version": 3, "profiles_version": "3.0.0", "phase" at top level
#   - Removes "priority" from each rule (order is array position)
#   - Adds "enabled": true to each rule
#   - Adds "logging": { "enabled": true } to each rule
#   - Converts "allow" action → "skip" with action_parameters
#   - Converts "bypass" action → "skip" with action_parameters.phases
#   - Preserves all other fields (rule_number, rule_version, description, expression)
# =====================================================================

usage () {
    echo "Usage: $(basename "$0") <input.json> [output.json]"
    echo ""
    echo "Convert a v2 profile JSON to v3 (Rulesets API) format."
    echo ""
    echo "Arguments:"
    echo "  input.json    Path to v2 profile JSON file"
    echo "  output.json   Optional output file (default: stdout)"
    echo ""
    echo "Examples:"
    echo "  $(basename "$0") profiles/default.json"
    echo "  $(basename "$0") profiles/default.json profiles/default-v3.json"
    exit 1
}

# -- Parse arguments
if [[ $# -lt 1 ]]; then
    usage
fi

INPUT_FILE="$1"
OUTPUT_FILE="$2"

# -- Validate input file
if [[ ! -f "$INPUT_FILE" ]]; then
    echo "Error: Input file not found: $INPUT_FILE" >&2
    exit 1
fi

# -- Validate JSON syntax
if ! jq empty "$INPUT_FILE" 2>/dev/null; then
    echo "Error: Invalid JSON in $INPUT_FILE" >&2
    exit 1
fi

# -- Check if already v3
SCHEMA_VERSION=$(jq -r '.version // 2' "$INPUT_FILE")
if [[ "$SCHEMA_VERSION" -ge 3 ]]; then
    echo "Warning: Profile is already v3 (version=$SCHEMA_VERSION). No conversion needed." >&2
    if [[ -n "$OUTPUT_FILE" ]]; then
        cp "$INPUT_FILE" "$OUTPUT_FILE"
        echo "Copied to $OUTPUT_FILE" >&2
    else
        cat "$INPUT_FILE"
    fi
    exit 0
fi

echo "Converting v2 profile ($SCHEMA_VERSION) to v3..." >&2

# -- Perform conversion using jq
V3_JSON=$(jq '
{
    # Copy top-level fields
    name: .name,
    description: .description,
    # Add v3 metadata
    version: 3,
    profiles_version: "3.0.0",
    phase: "http_request_firewall_custom",
    # Convert rules
    rules: [
        .rules[] | {
            # Preserve existing fields
            rule_number: .rule_number,
            rule_version: .rule_version,
            description: .description,
            expression: .expression,
            # Convert action
            action: (
                if .action == "allow" then "skip"
                elif .action == "bypass" then "skip"
                else .action
                end
            ),
            # Add enabled flag
            enabled: true,
            # Add logging (default enabled, disabled for skip to avoid noise)
            logging: {
                enabled: (if .action == "allow" or .action == "bypass" then false else true end)
            },
            # Add action_parameters based on action
            action_parameters: (
                if .action == "allow" then
                    { "ruleset": "current" }
                elif .action == "bypass" then
                    { "phases": ["http_request_firewall_managed", "http_ratelimit", "http_request_firewall_custom"] }
                else
                    {}
                end
            )
        }
    ]
}' "$INPUT_FILE")

JQ_EXIT=$?
if [[ $JQ_EXIT -ne 0 ]]; then
    echo "Error: Conversion failed (jq exit code $JQ_EXIT)" >&2
    exit 1
fi

# -- Validate the converted JSON
if ! echo "$V3_JSON" | jq empty 2>/dev/null; then
    echo "Error: Converted JSON is invalid" >&2
    exit 1
fi

# -- Output
if [[ -n "$OUTPUT_FILE" ]]; then
    echo "$V3_JSON" > "$OUTPUT_FILE"
    RULE_COUNT=$(echo "$V3_JSON" | jq '.rules | length')
    echo "Done. Converted $RULE_COUNT rules to v3 format." >&2
    echo "Output: $OUTPUT_FILE" >&2
else
    echo "$V3_JSON"
fi
