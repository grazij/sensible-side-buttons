# SensibleSideButtons Makefile
# Simple wrapper around build.sh for users who prefer make

.PHONY: all debug release clean install verify archive help

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

# Help target
help:
	@echo "SensibleSideButtons Makefile"
	@echo ""
	@echo "Targets:"
	@echo "  make             - Build Release (default)"
	@echo "  make release     - Build Release configuration"
	@echo "  make debug       - Build Debug configuration"
	@echo "  make clean       - Clean build artifacts"
	@echo "  make install     - Build and install to /Applications"
	@echo "  make verify      - Verify build"
	@echo "  make archive     - Create distributable archive"
	@echo "  make help        - Show this help"
	@echo ""
	@echo "For more options, use ./build.sh directly"
	@echo "See BUILD.md for detailed documentation"
