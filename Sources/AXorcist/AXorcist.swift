import AppKit
import ApplicationServices
import Foundation
// GlobalAXLogger is expected to be available

// Global constant for backwards compatibility - removed, now using AXMiscConstants.defaultMaxDepthSearch

// Placeholder for the actual accessibility logic.
// For now, this module is very thin and AXorcist.swift is the main public API.
// Other files like Element.swift, Models.swift, Search.swift, etc. are in Core/ Utils/ etc.

public class AXorcist {

    // let focusedAppKeyValue = "focused" // Replaced by AXMiscConstants.focusedApplicationKey
    // Removed recursiveCallDebugLogs, as GlobalAXLogger handles accumulation

    // MARK: - Focus Tracking State (used by AXorcist+FocusTracking.swift)
    internal var focusTrackingObserver: AXObserver?
    internal var focusTrackingPID: pid_t = 0
    internal var focusTrackingCallback: AXFocusChangeCallback?
    internal var focusedUIElementToken: AXObserverCenter.SubscriptionToken?
    internal var focusedWindowToken: AXObserverCenter.SubscriptionToken?
    internal var systemWideFocusToken: AXObserverCenter.SubscriptionToken? // For system-wide tracking

    // Default values for collection and search if not provided by the command
    // These are now primarily defined in AXMiscConstants and can be referenced from there.
    // Public static let defaultMaxDepthCollectAll = AXMiscConstants.defaultMaxDepthCollectAll
    // Public static let defaultMaxDepthSearch = AXMiscConstants.defaultMaxDepthSearch
    // Public static let defaultMaxDepthPathResolution = AXMiscConstants.defaultMaxDepthPathResolution
    // Public static let defaultMaxDepthDescribe = AXMiscConstants.defaultMaxDepthDescribe
    // Public static let defaultTimeoutPerElementCollectAll = AXMiscConstants.defaultTimeoutPerElementCollectAll

    // Default attributes to fetch if none are specified by the command.
    // This can also be moved to AXMiscConstants if it's a shared default, or kept here if specific to AXorcist class logic.
    public static let defaultAttributesToFetch: [String] = [
        AXAttributeNames.kAXRoleAttribute,
        AXAttributeNames.kAXTitleAttribute,
        AXAttributeNames.kAXSubroleAttribute,
        AXAttributeNames.kAXIdentifierAttribute,
        AXAttributeNames.kAXDescriptionAttribute,
        AXAttributeNames.kAXValueAttribute,
        AXAttributeNames.kAXSelectedTextAttribute,
        AXAttributeNames.kAXEnabledAttribute,
        AXAttributeNames.kAXFocusedAttribute
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
