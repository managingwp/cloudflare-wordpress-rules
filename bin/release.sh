#!/usr/bin/env bash
# =============================================================================
# bin/release.sh — Promote beta to a numbered release
#
# Snapshots mwp-rules-beta.json into a versioned release file, updates
# the default symlink, regenerates all outputs, and bumps VERSION.
#
# Usage:
#   bin/release.sh 208                  # Create release v208
#   bin/release.sh 208 --tag            # Same + create git tag
#   bin/release.sh --dry-run 208        # Preview without making changes
#   bin/release.sh --help               # Show this message
# =============================================================================

set -euo pipefail

SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT_DIR="$SCRIPT_DIR/.."
PROFILES_DIR="$ROOT_DIR/profiles"
BETA_JSON="$PROFILES_DIR/mwp-rules-beta.json"
VERSION_FILE="$ROOT_DIR/VERSION"
DRY_RUN=0
CREATE_TAG=0

usage() {
    echo "Usage: $(basename "$0") <version> [--tag] [--dry-run]"
    echo ""
    echo "Promote beta profile to a numbered release."
    echo ""
    echo "Arguments:"
    echo "  <version>    Release number (e.g., 208)"
    echo ""
    echo "Options:"
    echo "  --tag        Create git tag for the release"
    echo "  --dry-run    Preview changes without modifying files"
    echo "  --help, -h   Show this message"
    echo ""
    echo "Examples:"
    echo "  bin/release.sh 208              # Create v208 release"
    echo "  bin/release.sh 208 --tag        # Create v208 release + git tag"
    echo "  bin/release.sh --dry-run 208    # Preview only"
}

# -- Parse arguments
POSITIONAL=()
while [[ $# -gt 0 ]]; do
    case "$1" in
        --tag)
            CREATE_TAG=1
            shift
            ;;
        --dry-run)
            DRY_RUN=1
            shift
            ;;
        --help|-h)
            usage
            exit 0
            ;;
        -*)
            echo "Error: Unknown option '$1'"
            echo ""
            usage
            exit 1
            ;;
        *)
            POSITIONAL+=("$1")
            shift
            ;;
    esac
done

# Restore positional arguments
set -- "${POSITIONAL[@]}"

if [[ $# -lt 1 ]]; then
    echo "Error: Missing version number"
    echo ""
    usage
    exit 1
fi

VER="$1"

# -- Validate version format (numeric)
if ! [[ "$VER" =~ ^[0-9]+$ ]]; then
    echo "Error: Version must be a number (e.g., 208)"
    exit 1
fi

# -- Validate beta source exists
if [[ ! -f "$BETA_JSON" ]]; then
    echo "Error: Beta profile not found at $BETA_JSON"
    exit 1
fi

RELEASE_NAME="mwp-rules-v${VER}"
RELEASE_JSON="$PROFILES_DIR/${RELEASE_NAME}.json"
RELEASE_MD="$PROFILES_DIR/${RELEASE_NAME}.md"

# -- Check if release already exists
if [[ -f "$RELEASE_JSON" ]]; then
    echo "Error: Release already exists at $RELEASE_JSON"
    echo "If you want to recreate it, delete the file first."
    exit 1
fi

echo "=== Promoting beta → ${RELEASE_NAME} ==="
echo "  Source:  mwp-rules-beta.json"
echo "  Target:  ${RELEASE_NAME}.json"
echo "  Version: v${VER}"
echo ""

# -- Step 1: Copy beta to release
echo "[1/6] Copying beta to ${RELEASE_NAME}.json..."
if [[ $DRY_RUN -eq 0 ]]; then
    cp "$BETA_JSON" "$RELEASE_JSON"
fi

# -- Step 2: Substitute version numbers
echo "[2/6] Setting rule versions to v${VER}..."
if [[ $DRY_RUN -eq 0 ]]; then
    jq "
        .name = \"${RELEASE_NAME}\" |
        .description = \"Managing WP v${VER} Cloudflare Rules\" |
        .profiles_version = \"3.1.0\" |
        .rules |= map(
            .rule_version = \"${VER}\" |
            .description |= gsub(\"VBETA\"; \"V${VER}\") |
            .description |= gsub(\"beta\"; \"${VER}\")
        )
    " "$RELEASE_JSON" > "${RELEASE_JSON}.tmp" && mv "${RELEASE_JSON}.tmp" "$RELEASE_JSON"
fi

# -- Step 3: Create .md template and generate
echo "[3/6] Creating .md template..."
if [[ $DRY_RUN -eq 0 ]]; then
    cat > "$RELEASE_MD" <<EOF
<!-- RULES-START -->
<!-- RULES-END -->

# Changelog
## Release ${VER}
* Released from beta channel.
EOF
fi

echo "[3/6] Regenerating all profile .md files..."
if [[ $DRY_RUN -eq 0 ]]; then
    bash "$SCRIPT_DIR/build.sh" generate-md
fi

# -- Step 4: Update default symlinks
echo "[4/6] Updating default symlinks → ${RELEASE_NAME}..."
if [[ $DRY_RUN -eq 0 ]]; then
    ln -sf "${RELEASE_NAME}.json" "$PROFILES_DIR/default.json"
    ln -sf "${RELEASE_NAME}.md" "$PROFILES_DIR/default.md"
fi

# -- Step 5: Bump VERSION
echo "[5/6] Bumping VERSION..."
if [[ $DRY_RUN -eq 0 ]]; then
    CURRENT_VERSION=$(cat "$VERSION_FILE")
    # Bump minor version (X.Y.Z → X.Y+1.0)
    MAJOR=$(echo "$CURRENT_VERSION" | cut -d. -f1)
    MINOR=$(echo "$CURRENT_VERSION" | cut -d. -f2)
    PATCH=0
    NEW_MINOR=$((MINOR + 1))
    echo "${MAJOR}.${NEW_MINOR}.${PATCH}" > "$VERSION_FILE"
    echo "  ${CURRENT_VERSION} → ${MAJOR}.${NEW_MINOR}.${PATCH}"
fi

# -- Step 6: Optional git tag
if [[ $CREATE_TAG -eq 1 && $DRY_RUN -eq 0 ]]; then
    echo "[6/6] Creating git tag v${VER}..."
    RELEASE_TAG="v${VER}"
    if git -C "$ROOT_DIR" rev-parse "$RELEASE_TAG" >/dev/null 2>&1; then
        echo "  Warning: Tag $RELEASE_TAG already exists, skipping."
    else
        git -C "$ROOT_DIR" tag -a "$RELEASE_TAG" -m "Release ${RELEASE_NAME}"
        echo "  Created tag: $RELEASE_TAG"
    fi
elif [[ $CREATE_TAG -eq 1 && $DRY_RUN -eq 1 ]]; then
    echo "[6/6] Would create git tag: v${VER} (dry run, skipped)"
fi

echo ""
echo "=== Release ${RELEASE_NAME} complete ==="
if [[ $DRY_RUN -eq 1 ]]; then
    echo "(dry run — no files were modified)"
fi
echo ""
echo "Next steps:"
echo "  git add profiles/${RELEASE_NAME}.* profiles/default.* VERSION"
echo "  git commit -m \"feat: release ${RELEASE_NAME}\""
if [[ $CREATE_TAG -eq 0 ]]; then
    echo "  git tag v${VER}  (optional)"
fi
echo "  bin/build.sh generate-readme  # Update README changelog"
