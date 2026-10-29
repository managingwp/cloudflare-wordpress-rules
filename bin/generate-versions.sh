#!/usr/bin/env bash
# =============================================================================
# bin/generate-versions.sh — Publish the releases the rule generator can load
#
# Reads every profiles/mwp-rules-v*.json plus profiles/mwp-rules-beta.json and
# writes website/static/generator/profiles/versions.json:
#
#   * value   — the rules version, taken from the filename
#   * label   — what the page shows in the "Start from" picker
#   * note    — current / older release / staging channel
#   * source  — the profile file the rules came from
#   * rules   — the profile's rules, embedded so the page needs no second
#               request and keeps working when opened over file://
#
# profiles/default.json decides which release is "current". The generator page
# treats the rules as read-only source: bin/generate-versions.sh is the only
# writer, and tests/test-generator.sh asserts the output matches profiles/.
#
# Usage:
#   bin/generate-versions.sh [--out <path>]
# =============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR=$(cd "$SCRIPT_DIR/.." && pwd)
PROFILES_DIR="$ROOT_DIR/profiles"
DEFAULT_OUT="$ROOT_DIR/website/static/generator/profiles/versions.json"

OUT="$DEFAULT_OUT"
while [[ $# -gt 0 ]]; do
    case "$1" in
        --out)
            [[ -n "${2:-}" ]] || { echo "Error: --out needs a path" >&2; exit 1; }
            OUT="$2"
            shift 2
            ;;
        -h|--help)
            sed -n '2,22p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'
            exit 0
            ;;
        *)
            echo "Error: unknown argument '$1'" >&2
            exit 1
            ;;
    esac
done

command -v jq >/dev/null 2>&1 || { echo "Error: jq is required" >&2; exit 1; }
[[ -d "$PROFILES_DIR" ]] || { echo "Error: $PROFILES_DIR not found" >&2; exit 1; }

# The release profiles/default.json points at is the current one.
if [[ -L "$PROFILES_DIR/default.json" ]]; then
    current_file=$(basename "$(readlink -f "$PROFILES_DIR/default.json")")
else
    current_file=""
fi

files=()
while IFS= read -r file; do
    files+=("$file")
done < <(ls -1 "$PROFILES_DIR"/mwp-rules-v*.json "$PROFILES_DIR"/mwp-rules-beta.json 2>/dev/null | sort)

(( ${#files[@]} > 0 )) || { echo "Error: no profile files in $PROFILES_DIR" >&2; exit 1; }

current=""
if [[ -n "$current_file" && -f "$PROFILES_DIR/$current_file" ]]; then
    current=$(jq -r '.rules[0].rule_version // empty' "$PROFILES_DIR/$current_file")
fi
if [[ -z "$current" ]]; then
    current=$(jq -r '.rules[0].rule_version // empty' "$PROFILES_DIR/default.json")
fi
[[ -n "$current" ]] || { echo "Error: could not determine the current rules version" >&2; exit 1; }

mkdir -p "$(dirname "$OUT")"

jq -n --arg current "$current" --arg currentFile "$current_file" '
  def version_of($path):
    ($path | split("/") | last | sub("^mwp-rules-"; "") | sub("\\.json$"; "") | sub("^v"; ""));

  [ inputs | { source: input_filename, profile: . } ]
  | map(
      version_of(.source) as $version
      | {
          value: $version,
          label: (if $version == "beta" then "beta (staging)" else "v\($version)" end),
          note: (
            if $version == $current then "current release"
            elif $version == "beta" then "staging channel"
            else "older release"
            end
          ),
          current: ($version == $current),
          source: (.source | sub("^.*/profiles/"; "profiles/")),
          rules: .profile.rules
        }
    )
  | sort_by(
      (if .value == "beta" then 2 elif (.value | test("^[0-9]+$")) then 0 else 1 end),
      (if (.value | test("^[0-9]+$")) then ((.value | tonumber) * -1) else 0 end),
      .value
    )
  | {
      current: $current,
      currentSource: ("profiles/" + $currentFile),
      generatedBy: "bin/generate-versions.sh",
      versions: .
    }
' "${files[@]}" > "$OUT.tmp"

mv "$OUT.tmp" "$OUT"

count=$(jq '.versions | length' "$OUT")
echo "Wrote $OUT ($count versions, current $current)"
