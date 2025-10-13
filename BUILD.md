# SensibleSideButtons Build Guide

This document explains how to build SensibleSideButtons using the included build script.

## Quick Start

```bash
# Build Release version (recommended)
./build.sh release

# Build and install to /Applications
./build.sh install

# Clean and rebuild
./build.sh clean release
```

---

## Build Script Usage

### Commands

#### `./build.sh release`
Builds the Release configuration (optimized, production-ready)
- Creates universal binary (Intel + Apple Silicon)
- Applies optimizations
- Signs the app with your developer certificate
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

#### `./build.sh archive`
Creates a distributable archive
- Builds Release configuration
- Creates .xcarchive for distribution
- Copies app to `./build/` directory
- Runs verification automatically

#### `./build.sh dmg`
Creates a DMG disk image for distribution
- Builds Release if needed
- Creates compressed DMG with Applications symlink
- Ready for distribution to users
- Output: `./build/SensibleSideButtons-VERSION.dmg`

#### `./build.sh install`
Builds and installs to /Applications
- Builds Release configuration
- Removes old version from /Applications
- Installs new version
- Opens /Applications folder

#### `./build.sh verify`
Verifies the most recent build
- Checks architecture (universal binary)
- Verifies code signing
- Shows bundle information
- Validates signature

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

### Local Build Directory (Primary Location)
All builds now output to the local `./build` directory for easy access:

```
./build/
├── Debug/
│   ├── SensibleSideButtons.app       # Debug build
│   └── SensibleSideButtons.app.dSYM  # Debug symbols
├── Release/
│   ├── SensibleSideButtons.app       # Release build (optimized)
│   └── SensibleSideButtons.app.dSYM  # Debug symbols
└── Archive/
    └── SensibleSideButtons.xcarchive # Archive (created by ./build.sh archive)
```

**Note:** Xcode DerivedData is no longer used. All builds go directly to `./build/`.

---

## Common Workflows

### Development Build
```bash
# Quick debug build without cleaning
./build.sh debug --no-clean
```

### Production Build
```bash
# Clean build with verification
./build.sh clean release
./build.sh verify
```

### Distribution Build
```bash
# Create DMG ready for distribution (recommended)
./build.sh dmg

# Output: ./build/SensibleSideButtons-VERSION.dmg

# Or create archive
./build.sh archive

# Output: ./build/Archive/SensibleSideButtons.xcarchive
```

### Install for Testing
```bash
# Build, install, and verify
./build.sh install
./build.sh verify
```

---

## Build Requirements

### System Requirements
- macOS 10.15+ (for building)
- Xcode Command Line Tools installed
- Valid Apple Developer certificate (for code signing)

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

### Current Settings
- **Bundle ID:** `com.miacloud.sensible-side-buttons`
- **Version:** 1.0.6
- **Build:** 5
- **Minimum macOS:** 11.0 (Big Sur)
- **Architectures:** arm64, x86_64 (Universal)

### Code Signing
The app is automatically signed with your "Apple Development" certificate:
- **Developer:** Jose Israel Graziani
- **Team ID:** 7DLRYPB8WK

---

## Troubleshooting

### Build Fails with Code Signing Error
```bash
# List available signing identities
security find-identity -v -p codesigning

# Check project signing settings
xcodebuild -project SwipeSimulator.xcodeproj -showBuildSettings | grep -i sign
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

### "No build found to verify"
```bash
# Build first
./build.sh release

# Then verify
./build.sh verify
```

---

## Distribution Checklist

Before distributing the app:

1. **Build Release version**
   ```bash
   ./build.sh clean release
   ```

2. **Verify the build**
   ```bash
   ./build.sh verify
   ```

3. **Test the app**
   ```bash
   ./build.sh install
   # Test all functionality
   ```

4. **Create archive** (optional, for formal distribution)
   ```bash
   ./build.sh archive
   ```

5. **For public distribution** (requires additional steps):
   - Sign with "Developer ID Application" certificate
   - Notarize with Apple
   - Staple notarization ticket
   - Create DMG or PKG installer

---

## Advanced: Manual Build Commands

If you prefer to use xcodebuild directly:

### Debug Build
```bash
xcodebuild -project SwipeSimulator.xcodeproj \
           -scheme SensibleSideButtons \
           -configuration Debug \
           build
```

### Release Build
```bash
xcodebuild -project SwipeSimulator.xcodeproj \
           -scheme SensibleSideButtons \
           -configuration Release \
           build
```

### Archive
```bash
xcodebuild -project SwipeSimulator.xcodeproj \
           -scheme SensibleSideButtons \
           -configuration Release \
           archive \
           -archivePath ./build/SensibleSideButtons.xcarchive
```

### Clean
```bash
xcodebuild -project SwipeSimulator.xcodeproj \
           -scheme SensibleSideButtons \
           clean
```

---

## Support

For issues or questions:
- Check the main README.md
- Review techsteps.txt for release notes
- Open an issue on GitHub

---

**Build Script Version:** 1.0
**Last Updated:** October 2025
