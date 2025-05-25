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

    // Handler methods are implemented in extension files:
    // - handleExtractText: AXorcist+ActionHandlers.swift
    // - handleBatchCommands: AXorcist+BatchHandler.swift
    // - handleCollectAll: AXorcist+CollectAllHandler.swift

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

    // MARK: - Observe Command Handler

    @MainActor
    public func handleObserve(
        for appIdentifierOrNil: String?,
        notifications: [String], // These are AXNotification strings
        includeElementDetails: [String],
        watchChildren: Bool, // Parameter not used yet
        commandId: String,
        debugCLI: Bool
    ) async -> Bool {
        let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
        axInfoLog("[AXorcist.handleObserve][CmdID: \(commandId)] Starting observe for app: \(appIdentifier), notifications: \(notifications.joined(separator: ", ")), details: \(includeElementDetails.joined(separator: ", "))")

        guard let appElement = applicationElement(for: appIdentifier) else {
            axErrorLog("[AXorcist.handleObserve][CmdID: \(commandId)] Application not found: \(appIdentifier)")
            return false
        }

        var subscriptionTokens: [AXObserverCenter.SubscriptionToken] = []

        // This callback now captures necessary variables from the outer scope.
        // It matches the AXNotificationSubscriptionHandler signature.
        let observerCallback: AXNotificationSubscriptionHandler = {
            // Captured: commandId, includeElementDetails, appIdentifier, appElement
            obsPid, notificationNameString, rawObservedElement, nsUserInfo in 

            let observedElement = Element(rawObservedElement)
            // Ensure appElement is valid for path generation, otherwise path might be too long/incorrect
            let elementPath = observedElement.generatePathArray(upTo: appElement.pid() == obsPid ? appElement : nil)

            let (attributes, _) = getElementAttributes(
                element: observedElement,
                attributes: includeElementDetails, // Captured
                outputFormat: .smart
            )


            // Build a raw element dictionary (sanitized) using plain Swift types
            var sanitizedElement: [String: Any] = [:]
            if !attributes.isEmpty {
                var sanitizedAttrs: [String: Any] = [:]
                for (k, v) in attributes {
                    sanitizedAttrs[k] = sanitizeValue(v.value)
                }
                sanitizedElement["attributes"] = sanitizedAttrs
            }
            if !elementPath.isEmpty {
                sanitizedElement["path"] = elementPath
            }

            // Build overall payload with primitive types after sanitization
            let payloadRaw: [String: Any] = [
                "timestamp": Date().timeIntervalSince1970,
                "commandId": commandId,
                "notification": notificationNameString.rawValue,
                "pid": obsPid,
                "application": appIdentifier,
                "element": sanitizedElement.mapValues { $0 }
            ]


            let safePayload = makeJSONCompatible(payloadRaw) as! [String: Any]

            if let data = try? JSONSerialization.data(withJSONObject: safePayload, options: []),
               let jsonStr = String(data: data, encoding: .utf8) {
                fputs("\(jsonStr)\n", stdout)
                fflush(stdout)
            } else {
                fputs("{\"error\": \"Unencodable payload\"}\n", stderr)
                fflush(stderr)
            }
        }

        var allSubscriptionsSuccessful = true
        for notificationNameString in notifications {
            // Ensure axNotificationName is valid before using it
            guard let axNotificationName = AXNotification(rawValue: notificationNameString) else {
                axErrorLog("[AXorcist.handleObserve][CmdID: \(commandId)] Invalid notification name string: \(notificationNameString). Skipping.")
                continue // Skip to the next notification string
            }
            
            guard let targetPid = appElement.pid() else {
                axErrorLog("[AXorcist.handleObserve][CmdID: \(commandId)] Could not get PID for appElement: \(appIdentifier)")
                allSubscriptionsSuccessful = false
                break
            }
            
            let result = AXObserverCenter.shared.subscribe(
                pid: targetPid, 
                element: appElement, // Observe the application element itself
                notification: axNotificationName, // Now safely unwrapped
                handler: observerCallback
            )

            switch result {
            case .success(let token):
                subscriptionTokens.append(token)
                axDebugLog("[AXorcist.handleObserve][CmdID: \(commandId)] Subscribed to \(notificationNameString) for \(appIdentifier) (PID: \(targetPid))")
            case .failure(let error):
                axErrorLog("[AXorcist.handleObserve][CmdID: \(commandId)] Error subscribing to \(notificationNameString) for \(appIdentifier): \(error.description)")
                allSubscriptionsSuccessful = false
                break 
            }
            if !allSubscriptionsSuccessful { break }
        }

        if !allSubscriptionsSuccessful || subscriptionTokens.isEmpty {
            axErrorLog("[AXorcist.handleObserve][CmdID: \(commandId)] Failed to subscribe to one or more notifications for \(appIdentifier). Cleaning up...")
            for token in subscriptionTokens {
                do {
                    try AXObserverCenter.shared.unsubscribe(token: token)
                    axDebugLog("[AXorcist.handleObserve][CmdID: \(commandId)] Unsubscribed token \(token.id) during cleanup.")
                } catch {
                    axErrorLog("[AXorcist.handleObserve][CmdID: \(commandId)] Error unsubscribing token \(token.id) during cleanup: \(error.localizedDescription)")
                }
            }
            return false
        }

        axInfoLog("[AXorcist.handleObserve][CmdID: \(commandId)] Successfully subscribed to \(subscriptionTokens.count) notifications for \(appIdentifier). Streaming output to stdout.")
        return true
    }
}

// NOTE: The global function `findElementViaPathAndCriteria`