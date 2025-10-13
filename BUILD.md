# SensibleSideButtons Build Guide

This document explains how to build SensibleSideButtons using the generic build system.

## Quick Start

```bash
# Build Release version (recommended)
./build.sh release

# Build and verify
./build.sh release
./build.sh verify

# Create distribution DMG
./build.sh dmg

# Complete workflow: build, sign, create DMG, and notarize
./build.sh package --keychain $NOTARIZATION_KEYCHAIN_PROFILE 
```

---

## Configuration

The build system uses `.env` for all project-specific configuration. This file is gitignored and contains:

```bash
# Project Configuration
PROJECT_NAME=SwipeSimulator
SCHEME_NAME=SensibleSideButtons
APP_NAME=SensibleSideButtons.app
INFO_PLIST_PATH=SideButtonFixer/Info.plist

# GitHub Configuration (for releases)
GITHUB_OWNER=grazij
GITHUB_REPO=sensible-side-buttons

# Notarization
NOTARIZATION_KEYCHAIN_PROFILE=<KEYCHAIN_PROFILE>

# Build Configuration
BUILD_DIR=./build
BUILD_ARCHS="arm64 x86_64"
```

**Note:** The version number is automatically read from `Info.plist` (CFBundleShortVersionString). You don't need to update it in multiple places.

### First-Time Setup

If `.env` doesn't exist:

```bash
cp .env.example .env
# Edit .env with your settings (already done for this project)
```

---

## Build Script Usage

The build script (`build.sh`) is a generic, reusable build automation tool. All configuration comes from `.env`.

### Commands

#### `./build.sh release`
Builds the Release configuration (optimized, production-ready)
- Creates universal binary (Intel + Apple Silicon)
- Applies optimizations
- Signs the app automatically
- Version read from Info.plist
- **Default command if none specified**

#### `./build.sh debug`
Builds the Debug configuration (for development)
- Includes debug symbols
- No optimizations
- Faster build times

#### `./build.sh clean`
Cleans all build artifacts
- Removes `./build` directory
- Cleans Xcode DerivedData

#### `./build.sh sign`
Signs the app with Developer ID for distribution
- Auto-detects "Developer ID Application" certificate
- Applies hardened runtime
- Adds secure timestamp
- Required before notarization

#### `./build.sh dmg`
Creates a DMG disk image for distribution
- Builds Release if needed
- Creates compressed DMG with Applications symlink
- Auto-names: `SensibleSideButtons-VERSION.dmg` (version from Info.plist)
- Output: `./build/SensibleSideButtons-<version>.dmg`

#### `./build.sh notarize`
Notarizes the DMG with Apple
- Submits to Apple for notarization (required for macOS 10.15+)
- Waits for approval (usually 1-5 minutes)
- Automatically staples notarization ticket when complete
- Verifies the stapled ticket

**Options:**
- `--keychain PROFILE` - Use stored keychain profile (recommended)
- `--apple-id EMAIL` - Apple ID email
- `--team-id TEAM_ID` - Apple Developer Team ID
- `--password PASSWORD` - App-specific password
- `--wait` - Wait for notarization to complete (default)

**Examples:**
```bash
# Notarize DMG using keychain profile (recommended)
./build.sh notarize --keychain $NOTARIZATION_KEYCHAIN_PROFILE

# Notarize using credentials directly
./build.sh notarize --apple-id user@example.com --team-id TEAM123 --password xxxx-xxxx-xxxx-xxxx
```

**Setup keychain profile (first time only):**
```bash
xcrun notarytool store-credentials "$NOTARIZATION_KEYCHAIN_PROFILE" \
  --apple-id "your-email@example.com" \
  --team-id "7DLRYPB8WK"
```

#### `./build.sh package`
Complete distribution workflow (all-in-one)
- Builds Release
- Signs with Developer ID
- Creates DMG
- Notarizes with Apple
- Staples notarization ticket
- Verifies everything

**Example:**
```bash
./build.sh package --keychain $NOTARIZATION_KEYCHAIN_PROFILE
```

This is the recommended command for creating a distribution build.

#### `./build.sh install`
Builds and installs to /Applications
- Builds Release configuration
- Removes old version from /Applications
- Installs new version
- Opens /Applications folder

#### `./build.sh verify`
Verifies the most recent build
- Shows version from Info.plist
- Checks architecture (universal binary)
- Verifies code signing
- Shows bundle information
- Validates signature

#### `./build.sh show`
Shows build output locations and paths

#### `./build.sh help`
Shows usage information

---

### Options

#### `--no-clean`
Skip cleaning before build
```bash
./build.sh release --no-clean
```

#### `--verbose`
Show detailed build output
```bash
./build.sh release --verbose
```

---

## Build Output Locations

All builds output to the local `./build` directory:

```
./build/
├── Debug/
│   ├── SensibleSideButtons.app       # Debug build
│   └── SensibleSideButtons.app.dSYM  # Debug symbols
├── Release/
│   ├── SensibleSideButtons.app       # Release build (optimized)
│   └── SensibleSideButtons.app.dSYM  # Debug symbols
└── SensibleSideButtons-<version>.dmg # Distribution DMG
```

The version in the DMG filename is automatically read from `SideButtonFixer/Info.plist`.

---

## Common Workflows

### Development Build
```bash
# Quick debug build without cleaning
./build.sh debug --no-clean

# Or use make
make debug
```

### Production Build
```bash
# Clean build with verification
./build.sh clean release
./build.sh verify

# Or use make
make clean
make release
make verify
```

### Distribution Build (Recommended)
```bash
# Complete workflow: build, sign, DMG, notarize (all-in-one)
./build.sh package --keychain $NOTARIZATION_KEYCHAIN_PROFILE

# Or step-by-step:
./build.sh clean release   # Build
./build.sh sign             # Sign with Developer ID
./build.sh dmg              # Create DMG
./build.sh notarize --keychain $NOTARIZATION_KEYCHAIN_PROFILE  # Notarize

# Using make:
make package
```

### Create GitHub Release
```bash
# After creating and notarizing the DMG:
./release.sh

# This will:
# - Read version from Info.plist
# - Create git tag (v<version>)
# - Push to GitHub
# - Create GitHub release
# - Upload the DMG
# - Calculate SHA256 for Homebrew
```

### Install for Testing
```bash
# Build, install, and verify
./build.sh install
./build.sh verify

# Or use make
make install
```

---

## Makefile Targets

For convenience, you can also use `make`:

```bash
make                # Build Release (default)
make debug          # Build Debug
make clean          # Clean artifacts
make install        # Build and install to /Applications
make verify         # Verify build
make sign           # Sign with Developer ID
make dmg            # Create DMG
make notarize       # Notarize DMG
make package        # Complete workflow (build, sign, DMG, notarize)
make release-github # Create GitHub release
make help           # Show all targets
```

**Note:** `make notarize` and `make package` use the `NOTARIZATION_KEYCHAIN_PROFILE` from `.env`.

---

## Build Requirements

### System Requirements
- macOS 10.15+ (for building)
- Xcode Command Line Tools installed
- Valid Apple Developer certificate (for code signing)
- Apple Developer account (for notarization)

### Verify Prerequisites
```bash
# Check Xcode command line tools
xcode-select -p

# Check available schemes
xcodebuild -list -project SwipeSimulator.xcodeproj

# Check code signing identities
security find-identity -v -p codesigning
```

---

## Build Configuration

### Current Settings (from .env)
- **Project:** SwipeSimulator
- **Scheme:** SensibleSideButtons
- **App Name:** SensibleSideButtons.app
- **Version:** Auto-detected from Info.plist
- **Architectures:** arm64, x86_64 (Universal)
- **Build Directory:** ./build

### Version Management
The version is stored in ONE place: `SideButtonFixer/Info.plist`

```xml
<key>CFBundleShortVersionString</key>
<string>1.0.6-grazij.1</string>
```

All build scripts automatically read this version. No need to update version numbers in multiple files.

---

## Code Signing

### Development Signing (Automatic)
The build script automatically finds and uses your "Apple Development" certificate for local builds.

### Distribution Signing (./build.sh sign)
For distribution, use:
```bash
./build.sh sign
```

This will:
- Auto-detect your "Developer ID Application" certificate
- Sign with hardened runtime
- Add secure timestamp
- Prepare for notarization

You can override the certificate in `.env`:
```bash
DIST_SIGNING_IDENTITY="Developer ID Application: Your Name (TEAM_ID)"
```

---

## Troubleshooting

### "Configuration file not found"
```bash
cp .env.example .env
# Edit .env with your settings
```

### "Could not read version from Info.plist"
Check that `INFO_PLIST_PATH` in `.env` points to the correct file:
```bash
# Verify the path
cat SideButtonFixer/Info.plist | grep CFBundleShortVersionString
```

### Build Fails with Code Signing Error
```bash
# List available signing identities
security find-identity -v -p codesigning

# The build script will automatically use:
# - "Apple Development" for local builds
# - "Developer ID Application" for distribution (./build.sh sign)
```

### Build Succeeds but App Won't Run
```bash
# Verify the build
./build.sh verify

# Check for Accessibility permissions
# System Settings > Privacy & Security > Accessibility
```

### Clean Build Issues
```bash
# Deep clean
./build.sh clean
rm -rf ~/Library/Developer/Xcode/DerivedData/SwipeSimulator-*

# Rebuild
./build.sh release
```

### Notarization Fails
```bash
# View submission history
xcrun notarytool history --keychain-profile $NOTARIZATION_KEYCHAIN_PROFILE

# View detailed log for a specific submission
xcrun notarytool log SUBMISSION_ID --keychain-profile $NOTARIZATION_KEYCHAIN_PROFILE
```

**Common issues:**
- **Not signed with Developer ID**: Run `./build.sh sign` first
- **Missing hardened runtime**: The sign command handles this
- **Invalid entitlements**: Check your entitlements file

### DMG has Wrong Version
The version is read from Info.plist at build time. To update:

1. Edit `SideButtonFixer/Info.plist`
2. Update `CFBundleShortVersionString`
3. Clean and rebuild:
   ```bash
   ./build.sh clean release
   ./build.sh dmg
   ```

The DMG will now have the new version in its filename.

---

## Distribution Checklist

Before distributing the app:

1. **Update version in Info.plist**
   ```bash
   # Edit SideButtonFixer/Info.plist
   # Update CFBundleShortVersionString to new version
   ```

2. **Run complete distribution workflow**
   ```bash
   ./build.sh package --keychain $NOTARIZATION_KEYCHAIN_PROFILE
   ```

   This automatically:
   - Cleans previous builds
   - Builds Release version
   - Signs with Developer ID
   - Creates DMG with version in filename
   - Submits for notarization
   - Waits for approval
   - Staples notarization ticket
   - Verifies everything

3. **Test the notarized DMG**
   ```bash
   # Open the DMG (version will be in filename)
   open ./build/SensibleSideButtons-*.dmg

   # Verify Gatekeeper accepts it
   ./build.sh verify
   ```

4. **Create GitHub release**
   ```bash
   ./release.sh
   ```

   This automatically:
   - Reads version from Info.plist
   - Creates git tag (v<version>)
   - Pushes to GitHub
   - Creates GitHub release
   - Uploads the notarized DMG
   - Calculates SHA256 for Homebrew

5. **Update Homebrew cask** (optional)
   - Use the SHA256 from release.sh output
   - Submit PR to homebrew-cask

---

## Generic Build System

This build system is **generic and reusable**. To adapt it to another macOS project:

1. Copy these files to your project:
   - `build-config.sh`
   - `build.sh`
   - `release.sh`
   - `Makefile`
   - `.env.example`

2. Create `.env` from the template:
   ```bash
   cp .env.example .env
   ```

3. Edit `.env` with your project settings:
   ```bash
   PROJECT_NAME=YourProject
   SCHEME_NAME=YourProject
   APP_NAME=YourProject.app
   INFO_PLIST_PATH=YourProject/Info.plist
   ```

4. Build:
   ```bash
   ./build.sh release
   ```

Everything adapts automatically! See **GENERIC-BUILD-SYSTEM.md** and **EXAMPLE-ADAPTATION.md** for complete details.

---

## Support

For issues or questions:
- **Generic build system**: See GENERIC-BUILD-SYSTEM.md
- **Adaptation guide**: See EXAMPLE-ADAPTATION.md
- **Configuration options**: See .env.example
- **Quick reference**: See QUICK-START.md
- **Project-specific**: Check the main README.md
- **GitHub issues**: https://github.com/grazij/sensible-side-buttons/issues

---

**Build System Version:** 1.0
**Last Updated:** October 2025
