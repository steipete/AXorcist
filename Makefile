# Makefile for axorc helper

# Define the output binary name
BINARY_NAME = axorc
UNIVERSAL_BINARY_PATH = ./$(BINARY_NAME)

# Build and ad-hoc sign a universal local binary.
all:
	@echo "Cleaning old binary..."
	rm -f $(UNIVERSAL_BINARY_PATH)
	./scripts/build-universal-binary.sh $(UNIVERSAL_BINARY_PATH) --adhoc
	@echo "Build complete: $(UNIVERSAL_BINARY_PATH)"
	@ls -l $(UNIVERSAL_BINARY_PATH)


clean:
	@echo "Cleaning build artifacts..."
	swift package clean
	rm -f $(UNIVERSAL_BINARY_PATH)
	@echo "Clean complete."

release-artifact:
	@test -n "$(VERSION)" || (echo "VERSION is required" >&2; exit 2)
	@if test "$(ADHOC)" = "1"; then \
		./scripts/build-release-artifact.sh "$(VERSION)" --adhoc; \
	else \
		./scripts/build-release-artifact.sh "$(VERSION)"; \
	fi

# Format code with SwiftFormat
format:
	@echo "Formatting code with SwiftFormat..."
	swiftformat .
	@echo "Code formatting complete."

# Check code formatting (for CI)
format-check:
	@echo "Checking code formatting with SwiftFormat..."
	swiftformat --lint .
	@echo "Code formatting check complete."

# Lint code with SwiftLint
lint:
	@echo "Linting code with SwiftLint..."
	swiftlint lint --strict
	@echo "Code linting complete."

native-only:
	@bash scripts/test-native-ax-only.sh
	@bash scripts/test-native-ax-only-policy.sh

.PHONY: test-commander-dependency
test-commander-dependency:
	python3 scripts/test-commander-dependency.py

# Run formatting, linting, native-only policy, and dependency checks
check: format-check lint native-only test-commander-dependency
	@echo "All code checks complete."

# Default target
.DEFAULT_GOAL := all
