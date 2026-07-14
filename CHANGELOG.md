# Changelog

All notable changes to AXorcist will be documented in this file.

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
