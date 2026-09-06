# Generic macOS Project Makefile
# Simple wrapper around build.sh for users who prefer make
# Configuration loaded from .env

.PHONY: all debug release clean install verify archive sign dmg notarize package release-github help

# Default target
all: release

# Build targets
debug:
	@./build.sh debug

release:
	@./build.sh release

# Utility targets
clean:
	@./build.sh clean

install: release
	@./build.sh install

verify:
	@./build.sh verify

archive:
	@./build.sh archive

# Distribution targets
sign:
	@./build.sh sign

dmg:
	@./build.sh dmg

# build.sh reads NOTARIZATION_KEYCHAIN_PROFILE from .env itself; make does not
notarize:
	@./build.sh notarize

package:
	@./build.sh package

release-github:
	@./release-github.sh

# Help target
help:
	@echo "Generic macOS Project Makefile"
	@echo ""
	@echo "Configuration loaded from .env"
	@echo ""
	@echo "Build Targets:"
	@echo "  make             - Build Release (default)"
	@echo "  make release     - Build Release configuration"
	@echo "  make debug       - Build Debug configuration"
	@echo "  make clean       - Clean build artifacts"
	@echo ""
	@echo "Distribution Targets:"
	@echo "  make sign        - Sign with Developer ID for distribution"
	@echo "  make dmg         - Create DMG"
	@echo "  make notarize    - Notarize DMG (requires NOTARIZATION_KEYCHAIN_PROFILE in .env)"
	@echo "  make package     - Complete workflow: build, sign, dmg, notarize"
	@echo "  make release-github - Create GitHub release"
	@echo ""
	@echo "Utility Targets:"
	@echo "  make install     - Build and install to /Applications"
	@echo "  make verify      - Verify build"
	@echo "  make archive     - Create Xcode archive"
	@echo "  make help        - Show this help"
	@echo ""
	@echo "For more options, use ./build.sh directly"
	@echo "See BUILD.md for detailed documentation"
