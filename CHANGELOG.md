# Changelog

All notable changes to AXorcist will be documented in this file.

## [0.1.1] - 2026-04-28

### Changed
- Prefer a vendored local Commander checkout when present, while keeping the external release dependency exact.
- Refresh SwiftLog dependency pins.

## [0.1.0] - 2026-01-18

### Added
- Initial release of AXorcist, a Swift wrapper over macOS Accessibility with async/await-friendly APIs.
- Type-safe element querying and attribute access, plus action execution helpers.
- Permission helpers for checking/requesting Accessibility access and monitoring changes.
