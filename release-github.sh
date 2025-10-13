#!/bin/bash

################################################################################
# Generic macOS Release Script
#
# Automates creating GitHub releases with notarized DMG
# Configuration loaded from .env via build-config.sh
################################################################################

set -e

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-config.sh"

# Check if gh CLI is installed
if ! command -v gh &> /dev/null; then
    print_error "GitHub CLI (gh) not found"
    echo ""
    echo "Install with: brew install gh"
    echo "Then authenticate: gh auth login"
    exit 1
fi

DMG_PATH="$(get_dmg_path)"

echo ""
print_header "Release Script - $APP_NAME_NO_EXT v$VERSION"
echo ""

# Verify DMG exists and is notarized
if [ ! -f "$DMG_PATH" ]; then
    print_error "DMG not found at $DMG_PATH"
    print_info "Run './build.sh package --keychain $NOTARIZATION_KEYCHAIN_PROFILE' first"
    exit 1
fi

print_info "Verifying notarization..."
if xcrun stapler validate "$DMG_PATH" > /dev/null 2>&1; then
    print_success "DMG is notarized and stapled"
else
    print_error "DMG is not properly notarized"
    print_info "Run './build.sh notarize --keychain $NOTARIZATION_KEYCHAIN_PROFILE' first"
    exit 1
fi

# Calculate SHA256
print_info "Calculating SHA256..."
SHA256=$(shasum -a 256 "$DMG_PATH" | cut -d' ' -f1)
print_success "SHA256: $SHA256"

# Get DMG size
DMG_SIZE=$(du -h "$DMG_PATH" | cut -f1)
print_info "DMG size: $DMG_SIZE"

echo ""

# Check if tag already exists
TAG="v$VERSION"
if git rev-parse "$TAG" >/dev/null 2>&1; then
    print_error "Tag $TAG already exists"
    echo ""
    read -p "Delete existing tag and continue? (y/N) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        print_info "Deleting local tag..."
        git tag -d "$TAG"
        print_info "Deleting remote tag..."
        git push origin ":refs/tags/$TAG" 2>/dev/null || true
    else
        exit 1
    fi
fi

# Create release notes
print_info "Creating release notes..."
RELEASE_NOTES_FILE="/tmp/${APP_NAME_NO_EXT}-release-${VERSION}.md"

# Get repo URL
REPO_URL=$(get_github_repo_url)
PREV_TAG=$(git describe --tags --abbrev=0 2>/dev/null || echo "")

cat > "$RELEASE_NOTES_FILE" << EOF
## What's New in ${VERSION}

### Features
- Universal binary support (Apple Silicon + Intel)
- Notarized for seamless installation on macOS 10.15+

### Installation

#### Manual Installation (Recommended)
1. Download **${APP_NAME_NO_EXT}-${VERSION}.dmg** below
2. Open the DMG
3. Drag **${APP_NAME}** to your **Applications** folder
4. Launch the app

#### Via Homebrew Cask
\`\`\`bash
brew tap ${GITHUB_OWNER}/tap
brew install --cask ${APP_NAME_NO_EXT}
\`\`\`

## Requirements
- **macOS 11.0 (Big Sur)** or later

## Verification

**DMG File**: ${APP_NAME_NO_EXT}-${VERSION}.dmg
**Size**: ${DMG_SIZE}
**SHA256**: \`${SHA256}\`

This release is **notarized by Apple** and will install without warnings.

---

EOF

if [ -n "$PREV_TAG" ] && [ -n "$REPO_URL" ]; then
    echo "**Full Changelog**: ${REPO_URL}/compare/${PREV_TAG}...v${VERSION}" >> "$RELEASE_NOTES_FILE"
fi

print_success "Release notes created"

# Show preview
echo ""
print_header "Release Notes Preview"
echo ""
cat "$RELEASE_NOTES_FILE"
echo ""

# Confirm
read -p "Create release v${VERSION}? (y/N) " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_info "Release cancelled"
    rm -f "$RELEASE_NOTES_FILE"
    exit 0
fi

# Create git tag
print_info "Creating git tag v${VERSION}..."
git tag -a "v${VERSION}" -m "Release version ${VERSION}"

# Push tag
print_info "Pushing tag to GitHub..."
git push origin "v${VERSION}"

print_success "Tag pushed"

# Create GitHub release
echo ""
print_info "Creating GitHub release..."
gh release create "v${VERSION}" \
  "$DMG_PATH" \
  --title "${APP_NAME_NO_EXT} ${VERSION}" \
  --notes-file "$RELEASE_NOTES_FILE"

if [ $? -eq 0 ]; then
    print_success "Release created successfully!"
    echo ""
    print_header "Release Published"
    echo ""
    echo "  Version: ${VERSION}"
    echo "  DMG: ${APP_NAME_NO_EXT}-${VERSION}.dmg"
    echo "  Size: ${DMG_SIZE}"
    echo "  SHA256: ${SHA256}"
    echo ""
    if [ -n "$REPO_URL" ]; then
        echo "  View at: ${REPO_URL}/releases/tag/v${VERSION}"
    fi
    echo ""

    print_header "Next Steps"
    echo ""
    echo "1. Update Homebrew cask SHA256 in ${APP_NAME_NO_EXT}.rb:"
    echo "   sha256 \"${SHA256}\""
    echo ""
    echo "2. Test download:"
    if [ -n "$REPO_URL" ]; then
        echo "   curl -L -o test.dmg ${REPO_URL}/releases/download/v${VERSION}/${APP_NAME_NO_EXT}-${VERSION}.dmg"
    fi
    echo ""
else
    print_error "Failed to create release"
    exit 1
fi

# Clean up
rm -f "$RELEASE_NOTES_FILE"

echo ""
print_success "Done!"
echo ""
