# Changelog

All notable changes to AXorcist will be documented in this file.

## Unreleased

### Changed
- Refresh CI to Swift 6.2.4 and SwiftFormat 0.63.0 while retaining the Swift 6.2 and macOS 14 minimums.

## [0.1.9] - 2026-08-31

### Fixed
- Keep global application PID and launch-readiness reads off the main actor and outside KVO callbacks, use workspace membership instead of termination queries, and discard stale metadata across stop, restart, and application replacement.
- Retain each exact application wrapper until its readiness observation finishes unregistering, preventing premature deallocation during queued cleanup and semantic wrapper replacement.
- Return promptly from async timeouts and caller cancellation without joining uncooperative work, and preserve cancellation received before the result gate is installed. Thanks @SebTardif.

## [0.1.8] - 2026-08-30

### Fixed
- Keep Commander pinned to the remote exact 0.2.4 release regardless of checkout or scratch path; use explicit workspace overrides for local development.

## [0.1.7] - 2026-08-28

### Highlights
- Raw JSON path-only locators now work, `path_from_root` is honored, and decode errors identify the exact failing field path.

### Fixed
- Decode documented `path_from_root` locators without requiring `criteria`, preserve their navigation hints, and report precise raw JSON field errors; clarify the CLI and JSON command names. Thanks @pixel-placebo-lab.
- Preserve exact PID targets across CLI command conversion, reject conflicting application and PID selectors, and report point lookup misses as errors.
- Refuse element-scoped typing when native focus cannot be established, preventing keyboard events from reaching an unrelated focused app.
- Traverse menu bars during default searches so their items remain discoverable without `--scan-all`. Thanks @dalsoop.
- Match generic accessibility criteria such as `AXTitle` against their real Core Foundation values. Thanks @dalsoop.
- Discover element actions through the dedicated macOS Accessibility API so supported actions such as `AXPress` work in SwiftUI apps. Thanks @dalsoop.
- Preserve middle and right mouse-button identity across clicks, holds, and drags, and build complete input sequences before posting so allocation failures cannot leave a button held down.
- Keep accessibility-tree traversal state local to each search and honor prefetched children, so repeated lookups cannot skip elements seen by earlier commands.
- Route synchronous and legacy element observation through the shared bounded registration and cleanup state machine, so a wedged Accessibility endpoint cannot block the main actor indefinitely or escape late-result rollback.
- Bound asynchronous AX notification add and remove waits, including removal joins and subscription setup retries, so a wedged Accessibility endpoint cannot hang global observer startup or teardown. Thanks @SebTardif.
- Refuse per-element Accessibility reads when macOS cannot arm their messaging deadline, and report any failure to clear an armed deadline after the protected operation.
- Implement global accessibility notification watching as native per-application observers driven by KVO changes to `NSWorkspace.runningApplications` and application readiness, keep observer creation, registration, and cleanup deadline-bounded off the main actor so a wedged app cannot block startup or teardown, retain semantic application identity across wrapper churn, reset shared observers with unprivileged process-unique identities across PID reuse, recover boundedly from transient registration failures, and reject the invalid PID-zero observer path.
- Keep observation subscriptions in one token registry with exact element ownership and deterministic cleanup across the library and CLI.
- Resolve point-owned applications from one native on-screen window snapshot, avoiding synchronous all-app Accessibility queries while keeping frontmost fallback limited to the compatibility API.
- Preserve attributed-string parameterized results and route both public generic accessors through one native conversion path.
- Route the published `AXSetValue` compatibility command through the native value-attribute setter instead of treating it as a macOS accessibility action.
- Execute accessibility actions directly through one system-call owner, preserving native AX failures without redundant action-discovery round trips.
- Use the native macOS names for parameterized accessibility attributes instead of non-existent `Parameterized`-suffixed raw values.
- Stop probing or linking Apple Events for legacy automation-permission status; deprecated compatibility APIs now return unknown while Accessibility permission checks remain native AX-only.
- Route the visitor, collection, element-search, UI-automation, and deep JSON-path walkers through one identity-aware traversal kernel while preserving their established order, depth, pruning, and match semantics.
- Build both release architectures in one SwiftPM invocation, then verify and package the reported universal binary without assuming a fixed build directory.

### Added
- Add a typed native setter for accessibility selected-text ranges.
- Add immutable per-request accessibility traversal options while keeping the legacy process defaults source-compatible and thread-safe.

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
