import AppKit
import ApplicationServices
import Foundation
// GlobalAXLogger is expected to be available

// Global constant for backwards compatibility - removed, now using AXMiscConstants.defaultMaxDepthSearch

// Placeholder for the actual accessibility logic.
// For now, this module is very thin and AXorcist.swift is the main public API.
// Other files like Element.swift, Models.swift, Search.swift, etc. are in Core/ Utils/ etc.

public class AXorcist {

    let focusedAppKeyValue = "focused"
    // Removed recursiveCallDebugLogs, as GlobalAXLogger handles accumulation

    // MARK: - Focus Tracking State (used by AXorcist+FocusTracking.swift)
    internal var focusTrackingObserver: AXObserver?
    internal var focusTrackingPID: pid_t = 0
    internal var focusTrackingCallback: AXFocusChangeCallback?

    // Default values for collection and search if not provided by the command
    public static let defaultMaxDepthCollectAll = 7 // Default recursion depth for collectAll
    public static let defaultMaxDepthSearch = 15 // Default recursion depth for search operations
    public static let defaultMaxDepthPathResolution = 15 // Max depth for resolving path hints
    public static let defaultMaxDepthDescribe = 5 // ADDED: Default for description recursion
    public static let defaultTimeoutPerElementCollectAll = 0.5 // seconds

    // Default attributes to fetch if none are specified by the command.
    public static let defaultAttributesToFetch: [String] = [
        "AXRole",
        "AXTitle",
        "AXSubrole",
        "AXIdentifier",
        "AXDescription",
        "AXValue",
        "AXSelectedText",
        "AXEnabled",
        "AXFocused"
    ]

    public init() {
        // Logging is now managed by GlobalAXLogger and per-call startCollecting/stopCollecting logic
    }

    // Removed static func formatDebugLogMessage - GlobalAXLogger handles formatting

    // Handler methods are implemented in extension files:
    // - handlePerformAction: AXorcist+ActionHandlers.swift
    // - handleExtractText: AXorcist+ActionHandlers.swift
    // - handleCollectAll: AXorcist+ActionHandlers.swift
    // - handleBatchCommands: AXorcist+BatchHandler.swift

    // handleExtractText method is implemented in AXorcist+ActionHandlers.swift

    // handleBatchCommands method is implemented in AXorcist+BatchHandler.swift

    // handleCollectAll method is implemented in AXorcist+ActionHandlers.swift

    // MARK: - Path Navigation

    // MARK: - Search Operations

    @MainActor
    public func search(
        element: Element, // This is the starting element for the search
        locator: Locator,
        requireAction: String?,
        depth: Int, // Initial depth, usually 0 from external call
        maxDepth: Int
    ) -> Element? { // Returns Element? directly
        // Initial log for this AXorcist-level search call
        axDebugLog("AXorcist.search called with locator: \(locator.criteria), path_hint: \(locator.rootElementPathHint ?? []) starting from \(element.briefDescription(option: .short))")

        // Call the global findElementViaPathAndCriteria
        // This function is already refactored to use GlobalAXLogger and return Element?.
        let foundElement = findElementViaPathAndCriteria(
            application: element,
            locator: locator,
            maxDepth: maxDepth
        )

        if foundElement != nil {
            axDebugLog("AXorcist.search: findElementViaPathAndCriteria found an element.")
        } else {
            axDebugLog("AXorcist.search: findElementViaPathAndCriteria did NOT find an element.")
        }
        return foundElement
    }
}

// NOTE: The global function `findElementViaPathAndCriteria` (likely in a different file)
// still needs to be refactored to use GlobalAXLogger and remove its logging parameters.
// The call above anticipates this change.
