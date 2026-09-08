#!/usr/bin/env bash

################################################################################
# Generic macOS Build System - Configuration Library
################################################################################

# Color codes for output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m' # No Color

################################################################################
# Output Helper Functions
################################################################################

print_header() {
    echo -e "${BLUE}================================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================================${NC}"
}

print_success() { echo -e "${GREEN}✓ $1${NC}"; }
print_error() { echo -e "${RED}✗ $1${NC}"; }
print_info() { echo -e "${YELLOW}→ $1${NC}"; }
print_debug() { [ "${DEBUG:-false}" = "true" ] && echo -e "${BLUE}[DEBUG] $1${NC}" || true; }

################################################################################
# Configuration Loading
################################################################################

PROJECT_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT
ENV_FILE="$PROJECT_ROOT/.env"

if [ ! -f "$ENV_FILE" ]; then
    print_error "Configuration file not found: $ENV_FILE"
    echo "Please create .env from the template: cp .env.example .env"
    exit 1
fi

set -a && source "$ENV_FILE" && set +a

################################################################################
# Project Information
################################################################################

# Read a version-ish key, preferring the source Info.plist and falling back to
# the built app's resolved one.
#
# The source plist is authoritative wherever it actually carries the key: it is
# the file a human edits, and it is right even when build/ holds a stale or
# half-finished build. But a target with GENERATE_INFOPLIST_FILE = YES keeps the
# version in the MARKETING_VERSION / CURRENT_PROJECT_VERSION build settings and
# injects it at build time, so its source plist has no such key and a bare read
# yields the placeholder — which would name the DMG and the git tag after a
# version that does not exist. Hence: source first, built app second, and treat
# an unexpanded $(…) reference as absent in both.
_plist_value() {
    local key="$1"
    local value="" config candidate

    value=$(plutil -extract "$key" raw "$PROJECT_ROOT/$INFO_PLIST_PATH" 2>/dev/null)
    if _plist_value_is_literal "$value"; then
        echo "$value"
        return 0
    fi

    for config in Release Debug; do
        candidate="$(get_absolute_build_dir)/$config/$APP_NAME/Contents/Info.plist"
        [ -f "$candidate" ] || continue
        value=$(plutil -extract "$key" raw "$candidate" 2>/dev/null) || continue
        if _plist_value_is_literal "$value"; then
            echo "$value"
            return 0
        fi
    done

    return 1
}

_plist_value_is_literal() {
    case "$1" in
        ""|*'$('*) return 1 ;;
        *) return 0 ;;
    esac
}

get_version() {
    _plist_value CFBundleShortVersionString || echo "0.0.1"
}

get_bundle_id() {
    # The source plist usually holds $(PRODUCT_BUNDLE_IDENTIFIER); the built
    # app's Info.plist has it resolved. Prefer that, then the source plist,
    # then a placeholder.
    local bundle_id=""
    local config built_plist
    for config in Release Debug; do
        built_plist="$(get_absolute_build_dir)/$config/$APP_NAME/Contents/Info.plist"
        if [ -f "$built_plist" ]; then
            bundle_id=$(plutil -extract CFBundleIdentifier raw "$built_plist" 2>/dev/null) && break
        fi
    done
    if [ -z "$bundle_id" ]; then
        bundle_id=$(plutil -extract CFBundleIdentifier raw "$PROJECT_ROOT/$INFO_PLIST_PATH" 2>/dev/null)
    fi
    if [ -z "$bundle_id" ] || [[ "$bundle_id" == *"\$("* ]]; then
        echo "com.${APP_NAME_NO_EXT:-app}"
    else
        echo "$bundle_id"
    fi
}

get_build_number() {
    _plist_value CFBundleVersion || echo "1"
}

get_app_name_no_ext() {
    echo "${APP_NAME%.app}"
}

################################################################################
# Build Configuration
################################################################################

export BUILD_DIR="${BUILD_DIR:-./build}"
export BUILD_ARCHS="${BUILD_ARCHS:-arm64 x86_64}"

# Convert BUILD_DIR to absolute path if it's relative
get_absolute_build_dir() {
    if [[ "$BUILD_DIR" = /* ]]; then
        echo "$BUILD_DIR"
    else
        echo "$PROJECT_ROOT/$BUILD_DIR"
    fi
}

################################################################################
# Code Signing
################################################################################

get_dist_signing_identity() {
    if [ -n "${DIST_SIGNING_IDENTITY:-}" ]; then
        echo "$DIST_SIGNING_IDENTITY"
        return
    fi
    security find-identity -v -p codesigning | grep "Developer ID Application" | head -1 | sed "s/.*\\\"\\(.*\\)\\\".*/\\1/"
}

################################################################################
# GitHub
################################################################################

get_github_repo_url() {
    if [ -n "${GITHUB_OWNER:-}" ] && [ -n "${GITHUB_REPO:-}" ]; then
        echo "https://github.com/${GITHUB_OWNER}/${GITHUB_REPO}"
    else
        git remote get-url origin 2>/dev/null | sed "s/git@github.com:/https:\\/\\/github.com\\//" | sed "s/.git$//" || echo ""
    fi
}

################################################################################
# DMG
################################################################################

get_dmg_volume_name() {
    echo "${DMG_VOLUME_NAME:-$APP_NAME_NO_EXT}"
}

get_dmg_filename() {
    local version="${1:-$(get_version)}"
    echo "${APP_NAME_NO_EXT}-${version}.dmg"
}

get_dmg_path() {
    local version="${1:-$(get_version)}"
    echo "${BUILD_DIR}/${APP_NAME_NO_EXT}-${version}.dmg"
}

################################################################################
# Paths
################################################################################

get_app_path() {
    local config="${1:-Release}"
    echo "${BUILD_DIR}/${config}/${APP_NAME}"
}

################################################################################
# Initialize
################################################################################

# Calculate commonly used values (lazy evaluation to avoid hangs)
export APP_NAME_NO_EXT="${APP_NAME%.app}"

# These are functions that will be called when needed, not at source time
# Calling them here with command substitution can cause hangs
# Scripts should call these functions directly when needed

export BUILD_CONFIG_LOADED=true
print_debug "Build config loaded for: $APP_NAME_NO_EXT"
