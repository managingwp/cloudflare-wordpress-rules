#!/usr/bin/env bash
# =============================================================================
# bin/generate-md.sh — Render profiles into markdown and docs pages
#
# Reads JSON profiles in profiles/ and:
#   * injects rendered rule sections into profiles/<profile>.md templates
#     (markers <!-- RULES-START --> / <!-- RULES-END -->)
#   * regenerates docs/reference/beta-rules.md from the beta profile
#   * regenerates docs/reference/stable-rules.md from the default profile
#   * refreshes the short beta pointer in README.md
#     (markers <!-- BETA-RULES-START --> / <!-- BETA-RULES-END -->)
#
# Prerequisites: jq
# =============================================================================

set -euo pipefail
shopt -s nullglob

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PROFILES_DIR="$ROOT_DIR/profiles"
DOCS_DIR="$ROOT_DIR/docs/reference"
README_FILE="$ROOT_DIR/README.md"
BETA_JSON="$PROFILES_DIR/mwp-rules-beta.json"
DEFAULT_JSON="$PROFILES_DIR/default.json"
REPO_URL="https://github.com/managingwp/cloudflare-wordpress-rules/blob/main"

[[ -d "$PROFILES_DIR" ]] || { echo "Directory $PROFILES_DIR not found" >&2; exit 1; }
command -v jq >/dev/null 2>&1 || { echo "jq is required" >&2; exit 1; }

# Render a rules section (heading level ##) for a profile .md template.
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

# Render the rules body (heading level ###) used by the docs pages.
render_rules_body() {
    local json_file="$1"

    if jq -e 'has("rules")' "$json_file" >/dev/null; then
        jq -r '.rules[] as $r |
            "### R\($r.rule_number)V\($r.rule_version) – \($r.description)\n* Action: \($r.action | gsub("_"; " ") | ascii_upcase)\n```\n\($r.expression)\n```"' "$json_file"
    elif jq -e 'has("clouflare_api")' "$json_file" >/dev/null; then
        jq -r '.clouflare_api[] as $r |
            "### R\($r.priority) – \($r.profile_name)\n* Action: \($r.action | gsub("_"; " ") | ascii_upcase)\n```\n\($r.filter)\n```"' "$json_file"
    else
        echo "Error: no rules or clouflare_api array in $json_file" >&2
        return 1
    fi
}

# Replace a file with a temp file only when the content changed.
write_if_changed() {
    local target="$1"
    local tmp="$2"

    if [[ -f "$target" ]] && cmp -s "$tmp" "$target"; then
        rm -f "$tmp"
    else
        mv "$tmp" "$target"
        echo "Updated $target"
    fi
}

render_beta_page() {
    local tmp body
    tmp=$(mktemp)
    body=$(render_rules_body "$BETA_JSON") || exit 1

    {
        cat <<'EOF'
---
title: Beta rules (staging)
description: Generated reference for the rules in profiles/mwp-rules-beta.json.
---

# Beta rules (staging)

> **Unreleased** — generated from
> [`profiles/mwp-rules-beta.json`](https://github.com/managingwp/cloudflare-wordpress-rules/blob/main/profiles/mwp-rules-beta.json)
> by `bin/build.sh generate-md`; not part of a numbered release yet.

Deploy them with:

```bash
./cloudflare-wordpress-rules -d staging.example.com -c create-rules mwp-rules-beta
```

<!-- RULES-START -->
EOF
        printf '%s\n' "$body"
        cat <<'EOF'
<!-- RULES-END -->
EOF
    } > "$tmp"

    write_if_changed "$DOCS_DIR/beta-rules.md" "$tmp"
}

render_stable_page() {
    local tmp body target version title
    tmp=$(mktemp)
    body=$(render_rules_body "$DEFAULT_JSON") || exit 1

    target=$(readlink -f "$DEFAULT_JSON")
    version=$(basename "$target" .json | sed -n 's/.*-v\([0-9][0-9]*\)$/\1/p')
    if [[ -n "$version" ]]; then
        title="Stable rules (v${version})"
    else
        title="Stable rules"
    fi

    {
        cat <<EOF
---
title: ${title}
description: Generated reference for the rules the default selector deploys.
---

# ${title}

> Generated from \`profiles/default.json\` by \`bin/build.sh generate-md\`.

Deploy them with:

\`\`\`bash
./cloudflare-wordpress-rules -d example.com -c create-rules default
\`\`\`

<!-- RULES-START -->
EOF
        printf '%s\n' "$body"
        cat <<'EOF'
<!-- RULES-END -->
EOF
    } > "$tmp"

    write_if_changed "$DOCS_DIR/stable-rules.md" "$tmp"
}

# Refresh the short beta pointer at the top of README.md
update_readme_beta_block() {
    local start_marker='<!-- BETA-RULES-START -->'
    local end_marker='<!-- BETA-RULES-END -->'
    local tmp_block tmp_readme

    [[ -f "$README_FILE" ]] || { echo "Error: $README_FILE not found" >&2; exit 1; }

    if ! grep -qF "$start_marker" "$README_FILE" || ! grep -qF "$end_marker" "$README_FILE"; then
        echo "Error: $README_FILE must contain $start_marker and $end_marker" >&2
        exit 1
    fi

    tmp_block=$(mktemp) || exit 1
    tmp_readme=$(mktemp) || exit 1

    {
        printf '%s\n' "$start_marker"
        cat <<EOF
## Beta rules (staging)

Unreleased rule changes live in [\`profiles/mwp-rules-beta.json\`](profiles/mwp-rules-beta.json);
the generated rules are on the [Beta rules page](https://managingwp.github.io/cloudflare-wordpress-rules/reference/beta-rules).

\`\`\`bash
./cloudflare-wordpress-rules -d staging.example.com -c create-rules mwp-rules-beta
\`\`\`
EOF
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
    ' "$README_FILE" > "$tmp_readme"

    write_if_changed "$README_FILE" "$tmp_readme"
    rm -f "$tmp_block"
}

# -- Main loop: process each JSON profile into profiles/<name>.md
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

# -- Generated documentation pages and the README pointer
mkdir -p "$DOCS_DIR"
render_beta_page
render_stable_page
update_readme_beta_block
