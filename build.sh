#!/bin/bash

################################################################################
# SensibleSideButtons Build Script
#
# This script builds the SensibleSideButtons application with various options
# including Debug, Release, Archive, and Distribution builds.
################################################################################

set -e  # Exit on error

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Project configuration
PROJECT_NAME="SwipeSimulator.xcodeproj"
SCHEME_NAME="SensibleSideButtons"
APP_NAME="SensibleSideButtons.app"
BUILD_DIR="./build"

################################################################################
# Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}════════════════════════════════════════════════════════════${NC}"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}→ $1${NC}"
}

show_usage() {
    cat << EOF
Usage: $0 [COMMAND] [OPTIONS]

Commands:
    debug           Build Debug configuration
    release         Build Release configuration (default)
    clean           Clean build artifacts
    archive         Create distributable archive
    install         Build Release and install to /Applications
    verify          Verify code signing and architecture
    show            Show build output locations
    help            Show this help message

Options:
    --no-clean      Skip cleaning before build
    --verbose       Show detailed build output

Examples:
    $0 release              # Build Release configuration
    $0 debug                # Build Debug configuration
    $0 install              # Build and install to /Applications
    $0 archive              # Create archive for distribution
    $0 clean release        # Clean and build Release

EOF
}

clean_build() {
    print_header "Cleaning Build Artifacts"

    if [ -d "$BUILD_DIR" ]; then
        print_info "Removing $BUILD_DIR directory..."
        rm -rf "$BUILD_DIR"
        print_success "Local build directory cleaned"
    fi

    print_info "Cleaning Xcode build artifacts..."
    xcodebuild -project "$PROJECT_NAME" \
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

    print_info "Building universal binary (ARM64 + x86_64)..."
    print_info "Output: $build_output"

    # Convert to absolute path
    local abs_build_dir=$(cd "$BUILD_DIR" && pwd)

    if [ "$verbose" = true ]; then
        xcodebuild -project "$PROJECT_NAME" \
                   -scheme "$SCHEME_NAME" \
                   -configuration "$config" \
                   -arch arm64 -arch x86_64 \
                   ONLY_ACTIVE_ARCH=NO \
                   CONFIGURATION_BUILD_DIR="$abs_build_dir/$config" \
                   build
    else
        xcodebuild -project "$PROJECT_NAME" \
                   -scheme "$SCHEME_NAME" \
                   -configuration "$config" \
                   -arch arm64 -arch x86_64 \
                   ONLY_ACTIVE_ARCH=NO \
                   CONFIGURATION_BUILD_DIR="$abs_build_dir/$config" \
                   build 2>&1 | grep -E "(BUILD|error:|warning:)" || true
    fi

    if [ $? -eq 0 ]; then
        print_success "$config build completed successfully"

        local app_path="$build_output/$APP_NAME"

        if [ -d "$app_path" ]; then
            print_info "Build location: $app_path"

            # Get binary size and verify architectures
            local binary_path="$app_path/Contents/MacOS/SensibleSideButtons"
            if [ -f "$binary_path" ]; then
                local size=$(du -h "$binary_path" | cut -f1)
                print_info "Binary size: $size"

                echo ""
                print_info "Verifying architectures..."
                local arch_info=$(file "$binary_path")

                if echo "$arch_info" | grep -q "universal binary"; then
                    print_success "Universal binary detected"
                    if echo "$arch_info" | grep -q "arm64" && echo "$arch_info" | grep -q "x86_64"; then
                        print_success "✓ arm64 (Apple Silicon)"
                        print_success "✓ x86_64 (Intel)"
                    else
                        print_error "Missing architectures!"
                        file "$binary_path"
                    fi
                else
                    print_error "Not a universal binary!"
                    file "$binary_path"
                    print_error "Build may have failed to include all architectures"
                fi
            fi
        fi
    else
        print_error "$config build failed"
        exit 1
    fi
}

create_archive() {
    print_header "Creating Archive"

    local archive_path="$BUILD_DIR/Archive/SensibleSideButtons.xcarchive"

    mkdir -p "$BUILD_DIR/Archive"

    print_info "Creating archive (this may take a moment)..."

    # Convert to absolute path
    local abs_archive_path=$(cd "$BUILD_DIR/Archive" && pwd)/SensibleSideButtons.xcarchive

    xcodebuild -project "$PROJECT_NAME" \
               -scheme "$SCHEME_NAME" \
               -configuration Release \
               -arch arm64 -arch x86_64 \
               ONLY_ACTIVE_ARCH=NO \
               archive \
               -archivePath "$abs_archive_path" \
               | grep -E "(BUILD|ARCHIVE|error:|warning:)" || true

    if [ -d "$archive_path" ]; then
        print_success "Archive created successfully"
        print_info "Archive location: $archive_path"

        # Copy the app from archive to build/Release directory
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

install_app() {
    print_header "Installing to /Applications"

    # First build release
    build_configuration "Release" false

    # Use the built app from local build directory
    local built_app="$BUILD_DIR/Release/$APP_NAME"

    if [ ! -d "$built_app" ]; then
        print_error "Could not find built application at $built_app"
        exit 1
    fi

    # Check if app already exists
    if [ -d "/Applications/$APP_NAME" ]; then
        print_info "Removing existing app from /Applications..."
        rm -rf "/Applications/$APP_NAME"
    fi

    print_info "Copying app to /Applications..."
    cp -R "$built_app" /Applications/

    print_success "App installed to /Applications/$APP_NAME"

    # Verify the installation
    if [ -d "/Applications/$APP_NAME" ]; then
        print_info "Opening /Applications folder..."
        open /Applications
    fi
}

verify_build() {
    print_header "Verifying Build"

    # Look in local build directory first
    local app_path="$BUILD_DIR/Release/$APP_NAME"

    if [ ! -d "$app_path" ]; then
        # Try Debug
        app_path="$BUILD_DIR/Debug/$APP_NAME"
    fi

    if [ ! -d "$app_path" ]; then
        print_error "No build found to verify. Run './build.sh release' first."
        exit 1
    fi

    print_info "Verifying: $app_path"
    echo ""

    local binary_path="$app_path/Contents/MacOS/SensibleSideButtons"

    # Check architecture
    print_info "Architecture:"
    file "$binary_path" | grep -o "Mach-O.*" || true
    echo ""

    # Check with lipo for detailed arch info
    print_info "Architectures (lipo):"
    lipo -info "$binary_path" 2>/dev/null || echo "  Unable to get lipo info"
    echo ""

    # Check code signing
    print_info "Code Signing:"
    codesign -dvvv "$app_path" 2>&1 | grep -E "(Identifier|Authority|TeamIdentifier)" || true
    echo ""

    # Verify signature
    print_info "Signature Verification:"
    if codesign --verify --deep --strict "$app_path" 2>/dev/null; then
        print_success "Signature is valid"
    else
        print_error "Signature verification failed"
    fi
    echo ""

    # Check bundle info
    print_info "Bundle Information:"
    if [ -f "$app_path/Contents/Info.plist" ]; then
        echo "  Bundle ID: $(plutil -extract CFBundleIdentifier raw "$app_path/Contents/Info.plist")"
        echo "  Version: $(plutil -extract CFBundleShortVersionString raw "$app_path/Contents/Info.plist")"
        echo "  Build: $(plutil -extract CFBundleVersion raw "$app_path/Contents/Info.plist")"
    fi
}

show_output_locations() {
    print_header "Build Output Locations"

    # Check local build directory
    local has_build=false

    if [ -d "$BUILD_DIR/Release/$APP_NAME" ]; then
        print_success "Release Build Found"
        echo "  $BUILD_DIR/Release/$APP_NAME"

        local binary="$BUILD_DIR/Release/$APP_NAME/Contents/MacOS/SensibleSideButtons"
        if [ -f "$binary" ]; then
            local size=$(du -h "$binary" | cut -f1)
            print_info "Size: $size"
            print_info "Architectures:"
            file "$binary" | grep -o "Mach-O.*" | sed 's/^/  /'
        fi
        echo ""
        has_build=true
    fi

    if [ -d "$BUILD_DIR/Debug/$APP_NAME" ]; then
        print_success "Debug Build Found"
        echo "  $BUILD_DIR/Debug/$APP_NAME"
        echo ""
        has_build=true
    fi

    if [ -d "$BUILD_DIR/Archive/SensibleSideButtons.xcarchive" ]; then
        print_success "Archive Found"
        echo "  $BUILD_DIR/Archive/SensibleSideButtons.xcarchive"
        echo ""
        has_build=true
    fi

    if [ "$has_build" = false ]; then
        print_error "No local builds found"
        echo "  Run: ./build.sh release"
        echo ""
    fi

    # Check if installed
    if [ -d "/Applications/$APP_NAME" ]; then
        print_success "Installed Version"
        echo "  /Applications/$APP_NAME"
        local version=$(plutil -extract CFBundleShortVersionString raw "/Applications/$APP_NAME/Contents/Info.plist" 2>/dev/null)
        echo "  Version: $version"
        echo ""
    else
        print_info "Not installed (run: ./build.sh install)"
        echo ""
    fi

    # Quick actions
    if [ "$has_build" = true ]; then
        print_header "Quick Actions"
        echo "Open build folder:"
        echo "  open '$BUILD_DIR'"
        echo ""
        if [ -d "$BUILD_DIR/Release/$APP_NAME" ]; then
            echo "Copy to Desktop:"
            echo "  cp -R '$BUILD_DIR/Release/$APP_NAME' ~/Desktop/"
            echo ""
        fi
    fi
}

################################################################################
# Main Script
################################################################################

# Parse arguments
COMMAND=""
NO_CLEAN=false
VERBOSE=false

while [[ $# -gt 0 ]]; do
    case $1 in
        debug|release|clean|archive|install|verify|show|help)
            COMMAND=$1
            shift
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

# Default to release if no command specified
if [ -z "$COMMAND" ]; then
    COMMAND="release"
fi

# Show header
echo ""
print_header "SensibleSideButtons Build Script"
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
        if [ "$NO_CLEAN" = false ]; then
            clean_build
        fi
        build_configuration "Debug" $VERBOSE
        ;;
    release)
        if [ "$NO_CLEAN" = false ]; then
            clean_build
        fi
        build_configuration "Release" $VERBOSE
        ;;
    archive)
        if [ "$NO_CLEAN" = false ]; then
            clean_build
        fi
        create_archive
        verify_build
        ;;
    install)
        if [ "$NO_CLEAN" = false ]; then
            clean_build
        fi
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
