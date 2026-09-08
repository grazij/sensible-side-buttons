#!/usr/bin/env bash

################################################################################
# Generic macOS Build Script
#
# This script provides comprehensive build automation for macOS applications.
# Configuration is loaded from .env via build-config.sh
################################################################################

set -e  # Exit on error

# Load configuration
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/build-config.sh"

# The version lives in the MARKETING_VERSION build setting, so get_version has
# to read it back out of the built app. A snapshot taken here would be the
# *previous* build's version — or 0.0.1 on a clean tree — and every display
# below would then disagree with the DMG the same run produces. Re-read it at
# each use instead; the getter is cheap and always current.
version_now() { get_version; }
BUNDLE_ID=$(get_bundle_id)
export BUNDLE_ID
BUILD_NUMBER=$(get_build_number)
export BUILD_NUMBER

# Ensure BUILD_DIR is absolute
BUILD_DIR="$(get_absolute_build_dir)"
export BUILD_DIR

################################################################################
# Usage
################################################################################

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    debug           Build Debug configuration
    release         Build Release configuration (default)
    clean           Clean build artifacts
    archive         Create distributable archive
    sign            Sign with Developer ID for distribution
    dmg             Create DMG for distribution
    notarize        Notarize the app/DMG with Apple
    package         Complete workflow: build, sign, dmg, notarize
    install         Build Release and install to /Applications
    verify          Verify code signing and architecture
    show            Show build output locations
    help            Show this help message

Options:
    --no-clean      Skip cleaning before build
    --verbose       Show detailed build output

Notarization Options (for 'notarize' and 'package' commands):
    --keychain PROFILE      Use keychain profile (recommended)
    --apple-id EMAIL        Apple ID email
    --team-id TEAM_ID       Apple Developer Team ID
    --password PASSWORD     App-specific password
    --app                   Notarize app bundle instead of DMG

Examples:
    $0 release                          # Build Release
    $0 package --keychain PROFILE       # Complete distribution build
    $0 notarize --keychain PROFILE      # Notarize existing DMG
    $0 clean release                    # Clean and build

Configuration:
    Project settings loaded from .env
    Current project: $PROJECT_NAME
    Version: $(version_now)

EOF
}

################################################################################
# Build Functions
################################################################################

clean_build() {
    print_header "Cleaning Build Artifacts"

    if [ -d "$BUILD_DIR" ]; then
        print_info "Removing $BUILD_DIR directory..."
        rm -rf "$BUILD_DIR"
        print_success "Local build directory cleaned"
    fi

    print_info "Cleaning Xcode build artifacts..."
    xcodebuild -project "${PROJECT_NAME}.xcodeproj" \
               -scheme "$SCHEME_NAME" \
               clean > /dev/null 2>&1

    print_success "Xcode build artifacts cleaned"
}

build_configuration() {
    local config=$1
    local verbose=$2

    print_header "Building $config Configuration"

    # Create build directory structure
    local build_output="$BUILD_DIR/$config"
    mkdir -p "$build_output"

    print_info "Building universal binary ($BUILD_ARCHS)..."
    print_info "Output: $build_output"

    # Build the xcodebuild argument list with set -- so each -arch is its
    # own word without an unquoted expansion.
    set -- -project "${PROJECT_NAME}.xcodeproj" \
           -scheme "$SCHEME_NAME" \
           -configuration "$config"
    local arch
    for arch in $BUILD_ARCHS; do
        set -- "$@" -arch "$arch"
    done
    set -- "$@" ONLY_ACTIVE_ARCH=NO \
                CONFIGURATION_BUILD_DIR="$build_output" \
                -allowProvisioningUpdates \
                build

    # Capture xcodebuild's own status. Piping into grep would report grep's
    # status, and a failed build with no "error:" line would look successful.
    local rc=0
    local build_log="$BUILD_DIR/xcodebuild-$config.log"

    if [ "$verbose" = true ]; then
        xcodebuild "$@" || rc=$?
    else
        xcodebuild "$@" > "$build_log" 2>&1 || rc=$?
        grep -E "(BUILD|error:|warning:)" "$build_log" || true
        [ "$rc" -eq 0 ] || print_info "Full log: $build_log"
    fi

    if [ "$rc" -eq 0 ]; then
        print_success "$config build completed successfully"

        local app_path
        app_path="$(get_app_path "$config")"

        if [ -d "$app_path" ]; then
            print_info "Build location: $app_path"

            # Verify architectures
            local binary_path="$app_path/Contents/MacOS/$APP_NAME_NO_EXT"
            if [ -f "$binary_path" ]; then
                local size
                size=$(du -h "$binary_path" | cut -f1)
                print_info "Binary size: $size"

                echo ""
                print_info "Verifying architectures..."
                if file "$binary_path" | grep -q "universal binary"; then
                    print_success "Universal binary detected"
                    if file "$binary_path" | grep -q "arm64" && file "$binary_path" | grep -q "x86_64"; then
                        print_success "✓ arm64 (Apple Silicon)"
                        print_success "✓ x86_64 (Intel)"
                    fi
                else
                    print_error "Not a universal binary!"
                    file "$binary_path"
                fi
            fi
        fi
    else
        print_error "$config build failed"
        exit 1
    fi
}

# Sign the nested code listed in NESTED_CODE_PATHS, in the order given.
#
# codesign seals a bundle by hashing everything inside it, so anything nested
# must already carry its final signature when the enclosing bundle is signed.
# Signing outside-in, or signing only the app, leaves the inner Mach-O files
# with whatever signature the vendor shipped — for Sparkle that is an ad-hoc
# one, which notarization rejects with "The signature of the binary is invalid"
# for each of Autoupdate, Updater.app, Downloader.xpc and Installer.xpc.
#
# --deep is not the fix. Apple documents it as unsuitable for distribution: it
# applies the app's own entitlements and identifier rules to nested code and
# cannot express per-item options. The supported answer is an explicit
# inside-out list, which is what NESTED_CODE_PATHS is.
#
# --preserve-metadata=entitlements keeps each helper's own entitlements, which
# --force would otherwise drop. Sparkle's Downloader.xpc needs its network
# entitlement; Installer.xpc ships with none and must stay unsandboxed, so
# preserving "nothing" is correct there too.
sign_nested_code() {
    local app_path="$1"
    local identity="$2"

    if [ -z "${NESTED_CODE_PATHS:-}" ]; then
        # An empty list is only legitimate for an app that embeds no code. If
        # Frameworks/ exists, the vendored bundles are still ad-hoc signed and
        # notarization will reject every one of them -- after a full build, a
        # DMG and an upload. Fail here instead, where the cause is obvious.
        if [ -d "$app_path/Contents/Frameworks" ]; then
            print_error "NESTED_CODE_PATHS is empty but $APP_NAME embeds frameworks"
            print_info "List them innermost-first in .env; see .env.example"
            ls "$app_path/Contents/Frameworks"
            exit 1
        fi
        return 0
    fi

    print_info "Signing nested code (inside-out)..."
    local rel abs
    # Unquoted on purpose, to word-split the list; same pattern as BUILD_ARCHS.
    for rel in $NESTED_CODE_PATHS; do
        abs="$app_path/$rel"
        if [ ! -e "$abs" ]; then
            print_error "Nested code path not found: $rel"
            print_info "Fix NESTED_CODE_PATHS in .env, or the app layout changed"
            exit 1
        fi
        print_info "  $rel"
        codesign --force \
                 --sign "$identity" \
                 --options runtime \
                 --timestamp \
                 --preserve-metadata=entitlements \
                 "$abs" 2>&1 | grep -E "(replacing|signed)" || true
    done
    print_success "Nested code signed"
    echo ""
}

sign_for_distribution() {
    print_header "Signing for Distribution"

    local app_path
    app_path="$(get_app_path Release)"

    if [ ! -d "$app_path" ]; then
        print_error "Release build not found at $app_path"
        print_info "Run '$0 release' first"
        exit 1
    fi

    # Find Developer ID certificate
    print_info "Looking for Developer ID Application certificate..."
    local dev_id_cert
    dev_id_cert=$(get_dist_signing_identity)

    if [ -z "$dev_id_cert" ]; then
        print_error "No Developer ID Application certificate found!"
        echo ""
        echo "Create certificate in Xcode > Settings > Accounts > Manage Certificates"
        exit 1
    fi

    print_success "Found certificate: $dev_id_cert"
    echo ""

    # Re-signing with --force drops the entitlements Xcode embedded. Carry
    # them over, minus get-task-allow, which Xcode adds for debugging and
    # notarization rejects.
    local ent_dir
    ent_dir=$(mktemp -d "${TMPDIR:-/tmp}/build-sign.XXXXXX")
    local ent_file="$ent_dir/entitlements.plist"
    codesign -d --entitlements - --xml "$app_path" > "$ent_file" 2>/dev/null || true
    if [ -s "$ent_file" ]; then
        # plutil key paths split on ".", so the dots must be escaped
        plutil -remove 'com\.apple\.security\.get-task-allow' "$ent_file" > /dev/null 2>&1 || true
    fi
    set -- --force --verify --verbose \
        --sign "$dev_id_cert" \
        --options runtime \
        --timestamp
    if [ -s "$ent_file" ] && grep -q "<key>" "$ent_file"; then
        set -- "$@" --entitlements "$ent_file"
        print_info "  - Entitlements preserved from Xcode build"
    fi

    print_info "Signing with Developer ID for distribution..."
    print_info "  - Hardened runtime enabled"
    print_info "  - Secure timestamp enabled"
    echo ""

    # --deep is deliberately not used: Apple discourages it. Nested code
    # (frameworks, helpers) must be signed inside-out before this step.
    sign_nested_code "$app_path" "$dev_id_cert"

    local rc=0
    codesign "$@" "$app_path" 2>&1 | grep -E "(replacing|signed)" || true
    # --deep on *verify* is correct and wanted: it walks the nested code that
    # sign_nested_code just signed. It is only --deep on *signing* that Apple
    # warns against.
    codesign --verify --deep --strict "$app_path" || rc=$?
    rm -rf "$ent_dir"

    if [ "$rc" -eq 0 ]; then
        print_success "Successfully signed for distribution"
        echo ""

        print_info "Verifying signature..."
        codesign -dvvv "$app_path" 2>&1 | grep "Authority" | head -3

        echo ""
        print_success "App is now signed for distribution"
        echo ""
        print_info "Next steps:"
        echo "  $0 dmg                    # Create DMG"
        echo "  $0 notarize --keychain PROFILE  # Notarize"
    else
        print_error "Code signing failed"
        exit 1
    fi
}

# Sign the disk image with the same Developer ID used for the app.
#
# hdiutil emits an unsigned image, and notarizing plus stapling it does not add
# a signature: `spctl -a -t open` still reports "no usable signature". Signing
# it before submission is what makes the downloaded DMG itself assessable.
sign_dmg() {
    print_header "Signing DMG"

    local dmg_path identity
    dmg_path="$(get_dmg_path)"
    identity="$(get_dist_signing_identity)"

    if [ ! -f "$dmg_path" ]; then
        print_error "DMG not found: $dmg_path"
        exit 1
    fi

    print_info "Identity: $identity"
    codesign --force --sign "$identity" --timestamp "$dmg_path"
    codesign --verify --strict "$dmg_path"
    print_success "DMG signed"
    echo ""
}

create_dmg() {
    print_header "Creating DMG"

    local dmg_path
    dmg_path="$(get_dmg_path)"
    local app_path
    app_path="$(get_app_path Release)"

    # Check if Release build exists
    if [ ! -d "$app_path" ]; then
        print_info "Release build not found. Building first..."
        build_configuration "Release" false
    fi

    if [ ! -d "$app_path" ]; then
        print_error "Failed to find or build Release app"
        exit 1
    fi

    print_info "Creating DMG: $(basename "$dmg_path")"
    print_info "Source: $app_path"

    # Remove old DMG if exists
    if [ -f "$dmg_path" ]; then
        print_info "Removing old DMG..."
        rm "$dmg_path"
    fi

    # Create temporary directory for DMG contents
    local temp_dmg_dir
    temp_dmg_dir=$(mktemp -d)
    print_info "Preparing DMG contents..."

    cp -R "$app_path" "$temp_dmg_dir/"
    ln -s /Applications "$temp_dmg_dir/Applications"

    print_info "Creating disk image..."

    local dmg_volume_name
    dmg_volume_name=$(get_dmg_volume_name)
    hdiutil create -volname "$dmg_volume_name" \
                   -srcfolder "$temp_dmg_dir" \
                   -ov \
                   -format UDZO \
                   -imagekey zlib-level=9 \
                   "$dmg_path" > /dev/null 2>&1

    rm -rf "$temp_dmg_dir"

    if [ -f "$dmg_path" ]; then
        print_success "DMG created successfully"
        print_info "Location: $dmg_path"

        local dmg_size
        dmg_size=$(du -h "$dmg_path" | cut -f1)
        print_info "Size: $dmg_size"

        echo ""
        print_header "DMG Information"
        echo "  Filename: $(basename "$dmg_path")"
        echo "  Version: $(version_now)"
        echo "  Location: $dmg_path"
        echo "  Size: $dmg_size"
        echo ""
    else
        print_error "Failed to create DMG"
        exit 1
    fi
}

notarize_build() {
    print_header "Notarizing with Apple"

    # Parse notarization-specific options
    local apple_id=""
    local team_id=""
    local password=""
    local keychain_profile=""
    local notarize_app=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            --apple-id) apple_id="$2"; shift 2 ;;
            --team-id) team_id="$2"; shift 2 ;;
            --password) password="$2"; shift 2 ;;
            --keychain) keychain_profile="$2"; shift 2 ;;
            --app) notarize_app=true; shift ;;
            *) shift ;;
        esac
    done

    # Use config if not provided
    keychain_profile="${keychain_profile:-${NOTARIZATION_KEYCHAIN_PROFILE:-}}"
    apple_id="${apple_id:-${NOTARIZATION_APPLE_ID:-}}"
    team_id="${team_id:-${NOTARIZATION_TEAM_ID:-}}"
    password="${password:-${NOTARIZATION_PASSWORD:-}}"

    # Determine what to notarize
    local file_to_notarize=""

    if [ "$notarize_app" = true ]; then
        file_to_notarize="$(get_app_path Release)"
        if [ ! -d "$file_to_notarize" ]; then
            print_error "App not found. Run '$0 release' first"
            exit 1
        fi
        # Create ZIP for notarization
        local zip_path
        zip_path="$BUILD_DIR/$(get_app_name_no_ext)-notarize.zip"
        print_info "Creating ZIP for notarization..."
        ditto -c -k --keepParent "$file_to_notarize" "$zip_path"
        file_to_notarize="$zip_path"
    else
        file_to_notarize="$(get_dmg_path)"
        if [ ! -f "$file_to_notarize" ]; then
            print_error "DMG not found. Run '$0 dmg' first"
            exit 1
        fi
    fi

    print_info "File to notarize: $file_to_notarize"

    # Check credentials
    if [ -z "$keychain_profile" ] && [ -z "$apple_id" ]; then
        print_error "Missing credentials!"
        echo ""
        echo "Set in .env: NOTARIZATION_KEYCHAIN_PROFILE=your_profile"
        echo "Or use: $0 notarize --keychain PROFILE"
        exit 1
    fi

    # Build the argument list with set -- so a password containing quotes,
    # spaces, or globs is passed intact and never re-parsed by eval.
    set -- submit "$file_to_notarize"

    if [ -n "$keychain_profile" ]; then
        print_info "Using keychain profile: $keychain_profile"
        set -- "$@" --keychain-profile "$keychain_profile"
    else
        set -- "$@" --apple-id "$apple_id" --team-id "$team_id" --password "$password"
    fi

    set -- "$@" --wait

    print_info "Submitting for notarization..."
    echo ""

    # notarytool exits 0 as long as the *submission* succeeded, even when the
    # verdict is Invalid -- so the exit status alone would report a rejected
    # build as notarized, and stapling would then fail with a confusing
    # "Record not found". Read the verdict out of the output as well.
    local result=0 submit_log
    submit_log="$BUILD_DIR/notarytool-submit.log"
    set -o pipefail
    xcrun notarytool "$@" 2>&1 | tee "$submit_log" || result=$?
    set +o pipefail

    if [ $result -eq 0 ] && ! grep -q "status: Accepted" "$submit_log"; then
        result=1
        print_error "Notarization was rejected by Apple"
        local submission_id
        submission_id=$(grep -m1 "  id: " "$submit_log" | awk '{print $2}')
        if [ -n "$submission_id" ]; then
            print_info "Read the rejection with:"
            echo "  xcrun notarytool log $submission_id --keychain-profile ${keychain_profile:-PROFILE}"
        fi
    fi

    echo ""

    if [ $result -eq 0 ]; then
        print_success "Notarization completed!"

        print_info "Stapling notarization ticket..."

        if [ "$notarize_app" = true ]; then
            xcrun stapler staple "$(get_app_path Release)"
            rm -f "$zip_path"
            print_success "Ticket stapled to app"
        else
            xcrun stapler staple "$file_to_notarize"
            print_success "Ticket stapled to DMG"
        fi

        echo ""
        print_header "Notarization Complete"
        print_success "Your build is now notarized and ready for distribution!"
    else
        print_error "Notarization failed"
        echo ""
        echo "Check the log with:"
        echo "  xcrun notarytool history --keychain-profile $keychain_profile"
        exit 1
    fi
}

verify_build() {
    print_header "Verifying Build"

    local app_path
    app_path="$(get_app_path Release)"
    [ ! -d "$app_path" ] && app_path="$(get_app_path Debug)"

    if [ ! -d "$app_path" ]; then
        print_error "No build found. Run '$0 release' first"
        exit 1
    fi

    print_info "Verifying: $app_path"
    echo ""

    local binary_path="$app_path/Contents/MacOS/$APP_NAME_NO_EXT"

    print_info "Architecture:"
    file "$binary_path" | grep -o "Mach-O.*" || true
    echo ""

    print_info "Architectures (lipo):"
    lipo -info "$binary_path" 2>/dev/null || echo "  Unable to get lipo info"
    echo ""

    print_info "Code Signing:"
    codesign -dvvv "$app_path" 2>&1 | grep -E "(Identifier|Authority|TeamIdentifier)" || true
    echo ""

    print_info "Signature Verification:"
    if codesign --verify --deep --strict "$app_path" 2>/dev/null; then
        print_success "Signature is valid"
    else
        print_error "Signature verification failed"
    fi
    echo ""

    print_info "Bundle Information:"
    echo "  Bundle ID: $BUNDLE_ID"
    echo "  Version: $(version_now)"
    echo "  Build: $BUILD_NUMBER"
}

install_app() {
    print_header "Installing to /Applications"

    build_configuration "Release" false

    local built_app
    built_app="$(get_app_path Release)"

    if [ ! -d "$built_app" ]; then
        print_error "Could not find built application"
        exit 1
    fi

    if [ -d "/Applications/$APP_NAME" ]; then
        print_info "Removing existing app from /Applications..."
        rm -rf "/Applications/$APP_NAME"
    fi

    print_info "Copying app to /Applications..."
    cp -R "$built_app" /Applications/

    print_success "App installed to /Applications/$APP_NAME"

    if [ -d "/Applications/$APP_NAME" ]; then
        print_info "Opening /Applications folder..."
        open /Applications
    fi
}

show_output_locations() {
    print_header "Build Output Locations"

    local has_build=false

    if [ -d "$(get_app_path Release)" ]; then
        print_success "Release Build Found"
        echo "  $(get_app_path Release)"
        has_build=true
        echo ""
    fi

    if [ -d "$(get_app_path Debug)" ]; then
        print_success "Debug Build Found"
        echo "  $(get_app_path Debug)"
        has_build=true
        echo ""
    fi

    local dmg_path
    dmg_path="$(get_dmg_path)"
    if [ -f "$dmg_path" ]; then
        print_success "DMG Found"
        echo "  $dmg_path"
        has_build=true
        echo ""
    fi

    if [ "$has_build" = false ]; then
        print_error "No builds found"
        echo "  Run: $0 release"
        echo ""
    fi

    if [ -d "/Applications/$APP_NAME" ]; then
        print_success "Installed Version"
        echo "  /Applications/$APP_NAME"
        echo "  Version: $(version_now)"
        echo ""
    fi
}

create_archive() {
    print_header "Creating Archive"

    local archive_path="$BUILD_DIR/Archive/${APP_NAME_NO_EXT}.xcarchive"
    mkdir -p "$BUILD_DIR/Archive"

    print_info "Creating archive..."

    set -- -project "${PROJECT_NAME}.xcodeproj" \
           -scheme "$SCHEME_NAME" \
           -configuration Release
    local arch
    for arch in $BUILD_ARCHS; do
        set -- "$@" -arch "$arch"
    done
    set -- "$@" ONLY_ACTIVE_ARCH=NO \
                archive \
                -archivePath "$archive_path"

    xcodebuild "$@" | grep -E "(BUILD|ARCHIVE|error:|warning:)" || true

    if [ -d "$archive_path" ]; then
        print_success "Archive created successfully"
        print_info "Archive location: $archive_path"

        # Copy app from archive
        local app_in_archive="$archive_path/Products/Applications/$APP_NAME"
        if [ -d "$app_in_archive" ]; then
            mkdir -p "$BUILD_DIR/Release"
            cp -R "$app_in_archive" "$BUILD_DIR/Release/"
            print_success "App copied to $BUILD_DIR/Release/$APP_NAME"
        fi
    else
        print_error "Archive creation failed"
        exit 1
    fi
}

################################################################################
# Main Script
################################################################################

# Parse arguments
COMMAND=""
NO_CLEAN=false
VERBOSE=false
NOTARIZE_ARGS=()

while [[ $# -gt 0 ]]; do
    case $1 in
        debug|release|clean|archive|sign|dmg|install|verify|show|help)
            COMMAND=$1
            shift
            ;;
        notarize|package)
            COMMAND=$1
            shift
            NOTARIZE_ARGS=("$@")
            break
            ;;
        --no-clean)
            NO_CLEAN=true
            shift
            ;;
        --verbose)
            VERBOSE=true
            shift
            ;;
        *)
            echo "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

# Default to release
[ -z "$COMMAND" ] && COMMAND="release"

# Show header
echo ""
print_header "Build Script - $APP_NAME_NO_EXT v$(version_now)"
echo ""

# Execute command
case $COMMAND in
    help)
        show_usage
        ;;
    clean)
        clean_build
        ;;
    debug)
        [ "$NO_CLEAN" = false ] && clean_build
        build_configuration "Debug" $VERBOSE
        ;;
    release)
        [ "$NO_CLEAN" = false ] && clean_build
        build_configuration "Release" $VERBOSE
        ;;
    archive)
        [ "$NO_CLEAN" = false ] && clean_build
        create_archive
        verify_build
        ;;
    sign)
        sign_for_distribution
        ;;
    dmg)
        [ "$NO_CLEAN" = false ] && clean_build
        create_dmg
        ;;
    notarize)
        notarize_build "${NOTARIZE_ARGS[@]}"
        ;;
    package)
        [ "$NO_CLEAN" = false ] && clean_build
        build_configuration "Release" $VERBOSE
        sign_for_distribution
        # Notarize the app first and staple the ticket to it, so the .app is
        # self-sufficient once Homebrew copies it out of the DMG. Stapling only
        # the DMG leaves the app relying on an online check with Apple, which
        # fails on a machine that is offline or behind a filtered network.
        notarize_build --app "${NOTARIZE_ARGS[@]}"
        # Build the DMG from the now-stapled app, then sign it: an unsigned DMG
        # is rejected by spctl even after its own ticket is stapled.
        create_dmg
        sign_dmg
        notarize_build "${NOTARIZE_ARGS[@]}"
        ;;
    install)
        [ "$NO_CLEAN" = false ] && clean_build
        install_app
        ;;
    verify)
        verify_build
        ;;
    show)
        show_output_locations
        ;;
    *)
        print_error "Unknown command: $COMMAND"
        show_usage
        exit 1
        ;;
esac

echo ""
print_success "Done!"
echo ""
