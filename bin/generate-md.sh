#!/usr/bin/env bash
SCRIPT_DIR="$(dirname "$(readlink -f "$0")")"

# This script reads JSON profiles in "profiles" and injects rule sections into existing .md templates.
# It also refreshes the beta rules block near the top of README.md.
# Templates must have markers:
#   <!-- RULES-START -->
#   <!-- RULES-END -->
# README.md must have markers:
#   <!-- BETA-RULES-START -->
#   <!-- BETA-RULES-END -->
# Prerequisites: jq

set -euo pipefail
shopt -s nullglob

PROFILES_DIR="$SCRIPT_DIR/../profiles"
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

# Render the beta profile block near the top of README.md
update_readme_beta_block() {
    local readme_file="$SCRIPT_DIR/../README.md"
    local beta_md="$PROFILES_DIR/mwp-rules-beta.md"
    local start_marker='<!-- BETA-RULES-START -->'
    local end_marker='<!-- BETA-RULES-END -->'
    local tmp_block
    local tmp_readme

    [[ -f "$readme_file" ]] || { echo "Error: $readme_file not found" >&2; exit 1; }
    [[ -f "$beta_md" ]] || { echo "Error: $beta_md not found" >&2; exit 1; }

    if ! grep -qF "$start_marker" "$readme_file" || ! grep -qF "$end_marker" "$readme_file"; then
        echo "Error: $readme_file must contain $start_marker and $end_marker" >&2
        exit 1
    fi

    local beta_body
    beta_body=$(awk '
        /<!-- RULES-START -->/ { inblock=1; next }
        /<!-- RULES-END -->/   { inblock=0; next }
        inblock {
            if ($0 == "# Rules Data") next
            if ($0 ~ /^## R/) sub(/^## /, "### ")
            print
        }
    ' "$beta_md")

    if [[ -z "$beta_body" ]]; then
        echo "Error: no rules found between RULES markers in $beta_md" >&2
        exit 1
    fi

    tmp_block=$(mktemp) || exit 1
    tmp_readme=$(mktemp) || exit 1
    trap 'rm -f "$tmp_block" "$tmp_readme"' RETURN

    {
        printf '%s\n' "$start_marker"
        printf '## Beta Rules (Staging)\n\n'
        printf '> **Unreleased** — generated from [`profiles/mwp-rules-beta.json`](profiles/mwp-rules-beta.json); not part of a numbered release yet.\n'
        printf '> See [Profile Management](#profile-management). Deploy with `cloudflare-wordpress-rules -c create-rules mwp-rules-beta`.\n\n'
        printf '### Rules Data\n\n'
        printf '%s\n' "$beta_body"
        printf '%s\n' "$end_marker"
    } > "$tmp_block"

    awk -v block_file="$tmp_block" '
        $0 == "<!-- BETA-RULES-START -->" {
            while ((getline line < block_file) > 0) print line
            close(block_file)
            skip=1
            next
        }
        $0 == "<!-- BETA-RULES-END -->" { skip=0; next }
        !skip { print }
    ' "$readme_file" > "$tmp_readme"

    cp "$tmp_readme" "$readme_file"
    echo "Updated $readme_file (beta rules block)"
}

# Main loop: process each JSON profile
for json in "$PROFILES_DIR"/*.json; do
    # Skip symlinks — the real file will be processed directly
    if [[ -L "$json" ]]; then
        echo "Skipping symlink: $(basename "$json") (resolves to $(readlink "$json"))"
        continue
    fi

    echo "Processing $json"
    base=$(basename "$json" .json)
    md_file="$PROFILES_DIR/${base}.md"

    if [[ ! -f "$md_file" ]]; then
        echo "Skipping: $md_file not found (template missing)" >&2
        continue
    fi

    # Generate the combined block
    rules_block=$(generate_rules_section "$json")

    # Inject between markers (use cp to preserve symlinks)
    awk -v block="$rules_block" '
        $0 ~ /<!-- RULES-START -->/ { print; print block; inblock=1; next }
        $0 ~ /<!-- RULES-END -->/ { inblock=0 }
        !inblock { print }
    ' "$md_file" > "${md_file}.tmp"

    cp "${md_file}.tmp" "$md_file"
    rm "${md_file}.tmp"
    echo "Updated $md_file"
done

# Refresh the beta block at the top of README.md
update_readme_beta_block
