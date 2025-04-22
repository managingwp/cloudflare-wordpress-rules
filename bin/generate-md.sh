#!/usr/bin/env bash

# This script reads JSON profiles in "profiles" and injects rule sections into existing .md templates.
# Templates must have markers:
#   <!-- RULES-START -->
#   <!-- RULES-END -->
# Prerequisites: jq

set -euo pipefail
shopt -s nullglob

PROFILES_DIR="../profiles"
[[ -d "$PROFILES_DIR" ]] || { echo "Directory $PROFILES_DIR not found"; exit 1; }

# Generate the Markdown section for rules & optional changelog
generate_rules_section() {
    local json_file="$1"
    local section=""
    local entries

    # Optional: include changelog
    local changelog_file="${json_file%.json}-change.md"
    if [[ -f "$changelog_file" ]]; then
        section+="## Changelog\n"
        while IFS= read -r line; do
            section+="* $line\n"
        done < "$changelog_file"
        section+="\n"
    fi

    section+="# Rules Data\n"

    # Build entries based on JSON structure
    if jq -e 'has("rules")' "$json_file" >/dev/null; then
        entries=$(jq -r '.rules[] as $r |
            "## R\($r.rule_number)V\($r.rule_version) – \($r.description)\n* Action: \($r.action | gsub("_"; " ") | ascii_upcase)\n```\n\($r.expression)\n```"
        ' "$json_file")
    elif jq -e 'has("clouflare_api")' "$json_file" >/dev/null; then
        entries=$(jq -r '.clouflare_api[] as $r |
            "## R\($r.priority) – \($r.profile_name)\n* Action: \($r.action | gsub("_"; " ") | ascii_upcase)\n```\n\($r.filter)\n```"
        ' "$json_file")
    else
        echo "Warning: no rules or clouflare_api array in $json_file" >&2
        return
    fi

    section+="$entries\n"
    printf "%s" "$section"
}

# Main loop: process each JSON profile
for json in "$PROFILES_DIR"/*.json; do
    echo "Processing $json"
    base=$(basename "$json" .json)
    md_file="$PROFILES_DIR/${base}.md"

    if [[ ! -f "$md_file" ]]; then
        echo "Skipping: $md_file not found (template missing)" >&2
        continue
    fi

    # Generate the combined block
    rules_block=$(generate_rules_section "$json")

    # Inject between markers
    awk -v block="$rules_block" '
        $0 ~ /<!-- RULES-START -->/ { print; print block; inblock=1; next }
        $0 ~ /<!-- RULES-END -->/ { inblock=0 }
        !inblock { print }
    ' "$md_file" > "${md_file}.tmp"

    mv "${md_file}.tmp" "$md_file"
    echo "Updated $md_file"
done
