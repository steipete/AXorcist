# Changelog

All notable changes to AXorcist will be documented in this file.

## [Unreleased]

### Added
- Add a typed native setter for accessibility selected-text ranges.

### Fixed
- Traverse menu bars during default searches so their items remain discoverable without `--scan-all`. Thanks @dalsoop.
- Match generic accessibility criteria such as `AXTitle` against their real Core Foundation values. Thanks @dalsoop.
- Discover element actions through the dedicated macOS Accessibility API so supported actions such as `AXPress` work in SwiftUI apps. Thanks @dalsoop.

## [0.1.6] - 2026-07-15

### Added
- Add discoverable `permissions`, `find`, `tree`, and `raw` CLI commands with help, version, stable JSON output, signed universal artifact tooling, and a Homebrew formula template.

### Fixed
- Return nonzero exit codes for failed raw commands, keep routine CLI output free of library logs, resolve applications by name, PID, bundle ID, or focus, return real requested attribute values, repair documented examples, and let `collectAll` filters match descendants below nonmatching parents.

## [0.1.5] - 2026-07-15

### Changed
- Update the released Commander dependency to 0.2.4.

## [0.1.4] - 2026-07-14

### Fixed
- Keep the public swift-log convenience overloads nonisolated so importing AXorcist does not impose main-actor isolation on downstream log calls.

## [0.1.3] - 2026-07-14

### Fixed
- Keep `AXError.localizedDescription` callable from nonisolated code when clients enable Swift 6.2 strict concurrency.
- Printable ASCII typing now derives physical key events from the active macOS keyboard layout before falling back to Unicode events, improving VM and headless reliability without producing incorrect text on non-US layouts.
- Hotkey automation now builds complete event sequences before emitting and releasing physical modifier key events, preventing modifiers from remaining stuck after shortcuts or event-creation failures.
- Unsupported command dispatch now returns an `unknown_command` error instead of trapping, and JSON path hint parsing no longer writes warnings to stdout for unknown attributes.
- Preserve CFRange-backed AXValue attributes such as selected text ranges instead of misclassifying raw value 4 as a boolean. Thanks @WinnCook.

## [0.1.2] - 2026-04-28

### Fixed
- Avoid treating SwiftPM's `.build/checkouts` cache as a vendored workspace when resolving Commander.

## [0.1.1] - 2026-04-28

### Changed
- Prefer a vendored local Commander checkout when present, while keeping the external release dependency exact.
- Refresh SwiftLog dependency pins.

## [0.1.0] - 2026-01-18

### Added
- Initial release of AXorcist, a Swift wrapper over macOS Accessibility with async/await-friendly APIs.
- Type-safe element querying and attribute access, plus action execution helpers.
- Permission helpers for checking/requesting Accessibility access and monitoring changes.
