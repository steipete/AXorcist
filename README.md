# AXorcist 🧙‍♂️ - The power of Swift compels your UI to obey!

![AXorcist banner](docs/assets/readme-banner.jpg)

<p align="center">
  <img src="assets/logo.png" alt="AXorcist Logo">
</p>

<p align="center">
  <strong>Swift wrapper for macOS Accessibility—chainable, fuzzy-matched queries<br>that read, click, and inspect any UI. The dark arts meet modern Swift!</strong>
</p>

---

> **Platform target:** macOS 14.0 and later. AXorcist sits on top of the Accessibility APIs that only ship on macOS, so CI and releases intentionally stay macOS-only.

**AXorcist** harnesses the supernatural powers of macOS Accessibility APIs to give you mystical control over any application's interface. Whether you're automating workflows, testing applications, or building assistive technologies, AXorcist provides the incantations you need to make UI elements bend to your will.

## Overview

AXorcist enables developers to create sophisticated automation tools, testing frameworks, and accessibility utilities by providing:

- **Type-safe API**: Compile-time safety for accessibility attributes and operations
- **Modern Swift Patterns**: Async/await, structured concurrency, and error handling
- **Comprehensive Command System**: Query, action, observation, and batch operations
- **Element Management**: Efficient UI element discovery and interaction
- **Permission Handling**: Streamlined accessibility permission workflows

---

*This document provides a comprehensive overview of all AXorcist classes and their usage patterns. For interactive API documentation, run `../view-docs.sh` to open the DocC archives.*

## Core Classes Reference

### AXorcist (Main Class)

The central orchestrator for all accessibility operations.

```swift
@MainActor
public class AXorcist {
    static let shared = AXorcist()
    public func runCommand(_ commandEnvelope: AXCommandEnvelope) -> AXResponse
}
```

**Key Features:**
- Singleton pattern for consistent state management
- Command-based architecture for all operations
- MainActor isolation for thread safety
- Comprehensive error handling

**Usage Example:**
```swift
import AXorcist

let axorcist = AXorcist.shared
let query = QueryCommand(
    appIdentifier: "Safari",
    locator: Locator(criteria: [Criterion(attribute: "AXRole", value: "AXButton")]))
let command = AXCommandEnvelope(
    commandID: "find-button",
    command: .query(query)
)
let response = axorcist.runCommand(command)
```

### Element

Swift wrapper around `AXUIElement` providing modern API patterns.

```swift
public struct Element: Equatable, Hashable {
    public let underlyingElement: AXUIElement
    public var attributes: [String: AttributeValue]?
    public var prefetchedChildren: [Element]?
    public var actions: [String]?
}
```

**Key Features:**
- Type-safe property access with computed properties
- Automatic value conversion between CF and Swift types
- Hierarchy navigation with caching support
- Action execution with error handling
- Batch attribute fetching for performance

**Common Operations:**
```swift
// Create element wrapper
let element = Element(axUIElement)

// Access properties safely
let title = element.title()
let role = element.role()
let isEnabled = element.isEnabled()

// Perform a native action
try element.performAction(.press)

// Set the native value attribute
try element.setValue("Hello World")

// Navigate hierarchy
let children = element.children()
let parent = element.parent()
```

### AXPermissionHelpers

Modern async/await API for accessibility permissions.

```swift
public struct AXPermissionHelpers {
    static func hasAccessibilityPermissions() -> Bool
    static func requestPermissions() async -> Bool
    static func permissionChanges(interval: TimeInterval = 1.0) -> AsyncStream<Bool>
    static func isSandboxed() -> Bool
}
```

**Key Features:**
- Async/await permission handling
- Real-time permission monitoring with AsyncStream
- Sandbox detection for permission strategy
- Non-blocking permission requests

**Usage Patterns:**
```swift
// Check current status
let hasPermissions = AXPermissionHelpers.hasAccessibilityPermissions()

// Request permissions asynchronously
let granted = await AXPermissionHelpers.requestPermissions()

// Monitor permission changes
for await hasPermissions in AXPermissionHelpers.permissionChanges() {
    if hasPermissions {
        print("Permissions granted!")
        // Enable accessibility features
    } else {
        print("Permissions revoked!")
        // Disable accessibility features
    }
}
```

## Table of Contents

- [Features](#features)
- [Installation](#installation)
- [Quick Start](#quick-start)
- [Element Search and Matching](#element-search-and-matching)
- [Available Commands](#available-commands)
- [Actions](#actions)
- [Notifications and Observing](#notifications-and-observing)
- [Command-Line Usage](#command-line-usage)
- [Advanced Examples](#advanced-examples)
- [Architecture](#architecture)
- [Troubleshooting](#troubleshooting)

## Features

- 🔍 **Powerful Search**: Find UI elements using multiple criteria with flexible matching
- 🎯 **Precise Navigation**: Navigate UI hierarchies with path-based locators
- 🎬 **Actions**: Perform clicks, set values, and trigger UI interactions
- 👁️ **Observation**: Monitor UI changes in real-time with notifications
- 🚀 **Batch Operations**: Execute multiple commands efficiently
- 📊 **Rich Attributes**: Access all accessibility attributes and computed properties
- 🔧 **CLI Tool**: Full command-line interface for scripting and automation
- 📝 **Comprehensive Logging**: Debug support with detailed operation logs

## Installation

### Swift Package Manager

Add to your `Package.swift`:

```swift
dependencies: [
    .package(url: "https://github.com/openclaw/AXorcist.git", from: "0.1.7")
]
```

### Command Line Tool

Install the signed, notarized universal CLI with Homebrew:

```bash
brew install openclaw/tap/axorc
```

Or build and install it from source:

```bash
swift build -c release --product axorc
install -m 755 .build/release/axorc /usr/local/bin/axorc
```

Run `axorc permissions` after installation. macOS will need Accessibility permission for inspection and automation.

Maintainers: see [docs/releasing.md](docs/releasing.md) for the artifact and tap workflow.

### Local Development

AXorcist always declares the remote Commander dependency at exactly `0.2.4`, regardless of checkout location or sibling folders. To work on a sibling Commander checkout, explicitly override it from your root workspace (the AXorcist checkout, or the package consuming AXorcist):

```bash
swift package resolve
swift package edit Commander --path ../Commander
# Develop against the local checkout, then restore the released dependency:
swift package unedit Commander
```

The edit belongs to that workspace and leaves AXorcist's manifest unchanged. A consuming package can also explicitly add `.package(path: "../Commander")` to its root manifest's dependencies; remove that entry to restore versioned resolution. Keep these local overrides out of published manifests.

Run `make test-commander-dependency` for offline manifest and dependency-graph regression checks. They use disposable Git fixtures and isolated SwiftPM configuration and caches, including default and custom scratch paths, without building or running the app.

## Quick Start

### Swift API

```swift
import AXorcist

// Initialize AXorcist
let axorcist = AXorcist()

// Create a query command
let query = QueryCommand(
    appIdentifier: "com.apple.TextEdit",
    locator: Locator(criteria: [
        Criterion(attribute: "AXRole", value: "AXTextArea")
    ]),
    attributesToReturn: ["AXValue", "AXRole"]
)

// Execute the command
let response = axorcist.runCommand(AXCommandEnvelope(
    commandID: "query-1",
    command: .query(query)
))
```

### Command Line

```bash
# Print a shallow accessibility tree
axorc tree --app Safari --depth 3

# Find the Back button
axorc find --app Safari --role AXButton --title Back

# Use the full JSON protocol for actions and advanced queries
echo '{"command_id":"back","command":"performAction","application":"Safari","locator":{"criteria":[{"attribute":"AXTitle","value":"Back"}]},"action_name":"AXPress"}' | axorc raw --stdin
```

## Element Search and Matching

### Matching Types

AXorcist supports multiple matching strategies:

- **`exact`** - Exact string match (default)
- **`contains`** - Case-insensitive substring match
- **`regex`** - Regular expression match
- **`containsAny`** - Matches if any comma-separated value is contained
- **`prefix`** - String starts with the expected value
- **`suffix`** - String ends with the expected value

### Searchable Attributes

#### Core Attributes
- `role` / `AXRole` - Element's role (e.g., "AXButton", "AXWindow")
- `subrole` / `AXSubrole` - Additional role information
- `identifier` / `id` / `AXIdentifier` - Developer-assigned unique ID
- `title` / `AXTitle` - Element's title
- `value` / `AXValue` - Element's value
- `description` / `AXDescription` - Detailed description
- `help` / `AXHelp` - Tooltip/help text
- `placeholder` / `AXPlaceholderValue` - Placeholder text

#### State Attributes
- `enabled` / `AXEnabled` - Is element enabled?
- `focused` / `AXFocused` - Is element focused?
- `hidden` / `AXHidden` - Is element hidden?
- `busy` / `AXElementBusy` - Is element busy?

#### Special Attributes
- `pid` - Process ID (exact match only)
- `domclasslist` / `AXDOMClassList` - Web element classes
- `domid` / `AXDOMIdentifier` - DOM element ID
- `computedname` / `name` - Computed accessible name

### Search Examples

#### Find button by exact title
```json
{
  "criteria": [
    {"attribute": "role", "value": "AXButton"},
    {"attribute": "title", "value": "Submit"}
  ]
}
```

#### Find text field containing "email"
```json
{
  "criteria": [
    {"attribute": "role", "value": "AXTextField"},
    {"attribute": "title", "value": "email", "match_type": "contains"}
  ]
}
```

#### Find element by multiple classes (web content)
```json
{
  "criteria": [
    {"attribute": "domclasslist", "value": "btn-primary", "match_type": "contains"}
  ]
}
```

#### Using OR logic
```json
{
  "criteria": [
    {"attribute": "title", "value": "Save"},
    {"attribute": "title", "value": "Submit"},
    {"attribute": "title", "value": "OK"}
  ],
  "matchAll": false
}
```

### Path Navigation

Navigate through UI hierarchies with path hints:

```json
{
  "path_from_root": [
    {"attribute": "role", "value": "AXWindow", "depth": 1},
    {"attribute": "identifier", "value": "main-content", "depth": 3},
    {"attribute": "role", "value": "AXButton"}
  ]
}
```

Each path component supports:
- `attribute` - What to match
- `value` - Expected value
- `depth` - Max search depth for this step (default: 3)
- `match_type` - How to match (default: exact)

## Available Commands

### 1. Query
Find elements and retrieve their attributes.

```json
{
  "command_id": "find-text-area",
  "command": "query",
  "application": "com.apple.TextEdit",
  "locator": {
    "criteria": [{"attribute": "AXRole", "value": "AXTextArea"}]
  },
  "attributes": ["AXValue", "AXRole", "AXTitle"],
  "max_depth": 10
}
```

### 2. Perform Action
Execute actions on elements.

```json
{
  "command_id": "press-back",
  "command": "performAction",
  "application": "Safari",
  "locator": {
    "criteria": [{"attribute": "AXTitle", "value": "Back"}]
  },
  "action_name": "AXPress"
}
```

### 3. Get Focused Element
Retrieve the currently focused element.

```json
{
  "command_id": "focused-element",
  "command": "getFocusedElement",
  "attributes": ["AXRole", "AXTitle", "AXValue"]
}
```

### 4. Get Element at Point
Find element at specific screen coordinates.

```json
{
  "command_id": "element-at-point",
  "command": "getElementAtPoint",
  "point": [500, 300],
  "attributes": ["AXRole", "AXTitle"]
}
```

### 5. Batch Commands
Execute multiple commands in sequence.

```json
{
  "command_id": "inspect-and-fill",
  "command": "batch",
  "sub_commands": [
    {
      "command_id": "find-text-area",
      "command": "query",
      "application": "TextEdit",
      "locator": {"criteria": [{"attribute": "AXRole", "value": "AXTextArea"}]}
    },
    {
      "command_id": "fill-text-area",
      "command": "setFocusedValue",
      "application": "TextEdit",
      "locator": {"criteria": [{"attribute": "AXRole", "value": "AXTextArea"}]},
      "action_value": "Hello, World!"
    }
  ]
}
```

### 6. Observe Notifications
Monitor UI changes in real-time.

```json
{
  "command_id": "watch-text-edit",
  "command": "observe",
  "application": "com.apple.TextEdit",
  "notifications": ["AXValueChanged", "AXFocusedUIElementChanged"],
  "include_element_details": ["AXRole", "AXTitle", "AXValue"],
  "watch_children": false
}
```

### 7. Collect All
Recursively collect all elements.

```json
{
  "command_id": "collect-buttons",
  "command": "collectAll",
  "application": "Safari",
  "attributes": ["AXRole", "AXTitle"],
  "max_depth": 5,
  "filter_criteria": {"AXRole": "AXButton"}
}
```

## Actions

Available actions to perform on elements:

- **AXPress** - Click/activate an element
- **AXIncrement** - Increment value (sliders, steppers)
- **AXDecrement** - Decrement value
- **AXConfirm** - Confirm action
- **AXCancel** - Cancel action
- **AXShowMenu** - Show context menu
- **AXPick** - Pick/select element
- **AXRaise** - Bring element to front

### Setting Text Values

Setting `AXValue` is an attribute mutation, not a native accessibility action. Use `setFocusedValue` when the target
may need focus:

```json
{
  "command_id": "replace-text",
  "command": "setFocusedValue",
  "application": "TextEdit",
  "locator": {"criteria": [{"attribute": "AXRole", "value": "AXTextArea"}]},
  "action_value": "New text content"
}
```

The published `performAction` spelling with `"action_name": "AXSetValue"` remains a compatibility alias. It requires
a string `action_value` and writes `AXValue` directly without invoking an accessibility action or changing focus.

## Notifications and Observing

Monitor UI changes with these notifications:

- **AXFocusedUIElementChanged** - Focus changes
- **AXValueChanged** - Value changes
- **AXUIElementDestroyed** - Element destruction
- **AXWindowCreated** - Window creation
- **AXWindowResized** - Window resizing
- **AXTitleChanged** - Title changes
- **AXSelectedTextChanged** - Text selection changes
- **AXLayoutChanged** - Layout updates

Observe and `stopObservation` commands executed by the same `AXorcist` instance share one subscription registry, so a
successful stop clears the observations that instance started.

Accessibility observers are application-scoped on macOS; PID `0` and the system-wide AX element cannot receive
notifications. `NotificationWatcher(globalNotification:)` implements global watching by registering one observer for
each running user application and observing native KVO changes to `NSWorkspace.runningApplications` to keep that set
current, including menu-bar agents and background applications:

```swift
let watcher = NotificationWatcher(globalNotification: .focusedUIElementChanged) {
    pid, notification, element, userInfo in
    print("\(pid): \(notification.rawValue)")
}
try watcher.start()
```

Complete workspace snapshots are reconciled in order after KVO delivery. PID and launch-readiness reads, readiness
subscription, and its cleanup run on one serial background queue; a blocked metadata read leaves the main actor and
stop responsive. Membership supplies termination state without querying `isTerminated`. Session and membership
generations discard late results after stop, restart, or replacement, including removal and re-addition of the same
application. A blocked native read can delay subsequent metadata work until it returns; it does not spawn extra workers.
Each readiness observation retains its exact application wrapper until invalidation completes, including queued cleanup
after stop or wrapper replacement.

Applications that do not support the requested notification are skipped. Starting installs lifecycle tracking and
returns without waiting for per-application Accessibility endpoints; observer creation, registration, and cleanup run
off the main actor with bounded native messaging timeouts, so one wedged app cannot block startup or teardown. The
source-compatible
nil-PID `AXObserverCenter.subscribe` entry point returns an explicit setup failure instead of attempting to construct an
invalid PID-zero observer. A transient registration failure after an application lifecycle event receives three bounded
retries over 10.5 seconds, and an `isFinishedLaunching` readiness transition triggers an immediate fresh attempt.
Termination cancels pending registration and retry work, so this recovery never becomes a polling loop.

### Observer Example

```json
{
  "command_id": "watch-text",
  "command": "observe",
  "application": "TextEdit",
  "notifications": ["AXValueChanged", "AXFocusedUIElementChanged"],
  "locator": {"criteria": [{"attribute": "AXRole", "value": "AXTextArea"}]},
  "include_element_details": ["AXRole", "AXTitle", "AXValue"]
}
```

## Command-Line Usage

`axorc` has human-readable inspection commands and a stable JSON mode for scripts and advanced automation.

### Inspect Applications

```bash
# Check permission and recovery instructions
axorc permissions

# Print a hierarchy; use a bundle identifier when names are ambiguous
axorc tree --app com.apple.dock --depth 3

# Limit a tree to one role and emit JSON for scripts
axorc tree --app com.apple.dock --role AXDockItem --json

# Find one element with exact matching
axorc find --app Safari --role AXButton --title Back

# Use case-insensitive substring matching
axorc find --app Safari --title address --contains
```

Run `axorc --help` or `axorc help find` for the complete terminal reference. Human-readable output goes to stdout, diagnostics go to stderr, and failures return nonzero exit codes.

### JSON Protocol

Every JSON command requires `command_id` and `command`. JSON command names and fields differ from the human-readable CLI:

| CLI | JSON protocol |
| --- | --- |
| `tree --app <app> --depth 3` | `"command":"collectAll", "application":"<app>", "max_depth":3` |
| `find --app <app> --role AXButton` | `"command":"query", "application":"<app>", "locator":{"criteria":[{"attribute":"AXRole","value":"AXButton"}]}` |

`tree` and `find` are not JSON command names. Use `application` and `max_depth`, not `app` and `depth`. For example, the raw equivalent of `axorc tree --app com.apple.mail --depth 3 --json` is:

```bash
axorc raw --json '{"command_id":"mail-tree","command":"collectAll","application":"com.apple.mail","max_depth":3,"attributes":["AXRole","AXTitle","AXDescription","AXIdentifier","AXValue"]}'
```

Protocol commands are `ping`, `query`, `getAttributes`, `describeElement`, `getElementAtPoint`, `getFocusedElement`, `performAction`, `batch`, `observe`, `collectAll`, `stopObservation`, `isProcessTrusted`, `isAXFeatureEnabled`, `setFocusedValue`, and `extractText`. The reserved names `setNotificationHandler`, `removeNotificationHandler`, and `getElementDescription` decode but return a not-implemented error.

Locators may contain `criteria`, `path_from_root`, or both; omitted `criteria` defaults to an empty list. Invalid payloads return a nonzero exit code and a JSON error with the failing field path. An application-not-found or Accessibility error means decoding succeeded and the command reached execution.

Input can come from standard input, a file, an argument, or the legacy root-level syntax:

```bash
# Standard input
echo '{
  "command_id": "enabled-button",
  "command": "query",
  "application": "Safari",
  "locator": {
    "criteria": [
      {"attribute": "AXRole", "value": "AXButton"},
      {"attribute": "AXEnabled", "value": "true"}
    ]
  }
}' | axorc raw --stdin

# File
axorc raw --file command.json

# Argument
axorc raw --json '{"command_id":"health","command":"ping"}'

# Action using path navigation
echo '{
  "command_id": "press-back",
  "command": "performAction",
  "application": "com.apple.Safari",
  "locator": {
    "path_from_root": [
      {"attribute": "AXRole", "value": "AXWindow"},
      {"attribute": "AXIdentifier", "value": "toolbar"}
    ],
    "criteria": [{"attribute": "AXTitle", "value": "Back"}]
  },
  "action_name": "AXPress"
}' | axorc raw --stdin
```

Existing invocations such as `axorc --stdin` and `axorc '{...}'` remain supported. Prefer the explicit `raw` subcommand in new scripts.

## Advanced Examples

### Complex Search with Path Navigation

```json
{
  "command_id": "find-submit",
  "command": "query",
  "application": "com.apple.Safari",
  "locator": {
    "path_from_root": [
      {"attribute": "AXRole", "value": "AXWindow", "depth": 1},
      {"attribute": "AXRole", "value": "AXWebArea", "depth": 5}
    ],
    "criteria": [
      {"attribute": "AXRole", "value": "AXButton"},
      {"attribute": "AXDOMClassList", "value": "submit-button primary", "match_type": "contains"}
    ]
  },
  "attributes": ["AXTitle", "AXValue", "AXEnabled", "AXPosition", "AXSize"]
}
```

### Automated Form Filling

```json
{
  "command_id": "fill-form",
  "command": "batch",
  "sub_commands": [
    {
      "command_id": "fill-email",
      "command": "setFocusedValue",
      "application": "Safari",
      "locator": {
        "criteria": [
          {"attribute": "AXRole", "value": "AXTextField"},
          {"attribute": "AXPlaceholderValue", "value": "Email", "match_type": "contains"}
        ]
      },
      "action_value": "user@example.com"
    },
    {
      "command_id": "fill-password",
      "command": "setFocusedValue",
      "application": "Safari",
      "locator": {
        "criteria": [
          {"attribute": "AXRole", "value": "AXTextField"},
          {"attribute": "AXPlaceholderValue", "value": "Password", "match_type": "contains"}
        ]
      },
      "action_value": "example-value"
    },
    {
      "command_id": "submit-form",
      "command": "performAction",
      "application": "Safari",
      "locator": {
        "criteria": [
          {"attribute": "AXRole", "value": "AXButton"},
          {"attribute": "AXTitle", "value": "Sign In", "match_type": "contains"}
        ]
      },
      "action_name": "AXPress"
    }
  ]
}
```

### Monitoring Text Changes

```json
{
  "command_id": "watch-text",
  "command": "observe",
  "application": "com.apple.TextEdit",
  "notifications": ["AXValueChanged", "AXSelectedTextChanged"],
  "locator": {
    "criteria": [{"attribute": "AXRole", "value": "AXTextArea"}]
  },
  "include_element_details": ["AXRole", "AXTitle", "AXValue"],
  "watch_children": true
}
```

## Architecture

### Core Components

- **AXorcist** - Main orchestrator class
- **Element** - Wrapper around AXUIElement with convenience methods
- **ElementSearch** - Tree traversal and matching engine
- **AXElementMatcher** - Criteria matching logic
- **PathNavigator** - Hierarchical navigation
- **AXObserverCenter** - Notification management

### Thread Safety

All operations are MainActor-isolated for thread safety when interacting with the Accessibility API.

### Performance Optimizations

- Early termination on first match
- Depth-limited searches
- Efficient tree traversal with visitor pattern
- Caching of frequently accessed attributes

## Troubleshooting

### Permission Issues

Check Accessibility permission and print recovery instructions:

```bash
axorc permissions
```

### Finding Elements

Use the debug flag to see detailed search logs:

```bash
axorc raw --file command.json --debug
```

### Common Issues

1. **Element not found**: Try broader criteria or increase search depth
2. **Action failed**: Ensure element is enabled and supports the action
3. **Observer not working**: Check notification names and app identifier

### Debug Mode

Enable debug logging in commands:

```json
{
  "command_id": "debug-query",
  "command": "query",
  "debug_logging": true,
  ...
}
```

## License

AXorcist is released under the MIT License. See [LICENSE](LICENSE) for details.

## Contributing

Please follow the main Peekaboo contributing guidelines and open pull requests against this repository when proposing AXorcist changes.

## Coverage

| Date       | Command                                                                                           | Scope                            | Line Coverage |
| ---------- | ------------------------------------------------------------------------------------------------- | -------------------------------- | ------------- |
| 2025-11-13 | `swift test --package-path AXorcist --enable-code-coverage --filter AXorcistTests.PingIntegrationTests` | Ping integration suite only      | 2.39 %        |
| 2025-11-12 | `swift test --package-path AXorcist --enable-code-coverage --filter AXorcistTests.PingIntegrationTests` | Ping integration suite only      | 2.39 %        |

> Only the `PingIntegrationTests` subset currently runs in this headless environment; the automation-tagged suites require interactive UI access. Coverage is produced with `xcrun llvm-cov report AXorcist/.build/debug/axPackagePackageTests.xctest/Contents/MacOS/axPackagePackageTests -instr-profile AXorcist/.build/debug/codecov/default.profdata`.
