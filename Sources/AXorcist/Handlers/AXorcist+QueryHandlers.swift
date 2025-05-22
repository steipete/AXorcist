// AXorcist+QueryHandlers.swift - Query and search operation handlers

import AppKit
import ApplicationServices
import Foundation

// MARK: - Query & Search Handlers Extension
extension AXorcist {

    // MARK: - handleQuery
    
    @MainActor
    internal func handleQuery(
        for appIdentifierOrNil: String?,
        locator: Locator,
        pathHint: [String]?,
        maxDepth: Int?,
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) async -> HandlerResponse {
        
        func dLog(_ message: String) { if isDebugLoggingEnabled { currentDebugLogs.append(message) } }

        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        dLog("Handling query for app: \(appIdentifier)")

        // Pass logging parameters to applicationElement
        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            return HandlerResponse(
                data: nil,
                error: "Application not found: \(appIdentifier)",
                debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
            )
        }

        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            dLog("Navigating with path_hint: \(pathHint.joined(separator: " -> "))")
            // Pass logging parameters to navigateToElement
            if let navigatedElement = self.navigateToElement(
                from: effectiveElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                effectiveElement = navigatedElement
            } else {
                return HandlerResponse(
                    data: nil,
                    error: "Element not found via path hint: \(pathHint.joined(separator: " -> "))",
                    debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
                )
            }
        }

        let appSpecifiers = ["application", "bundle_id", "pid", "path"]
        let criteriaKeys = locator.criteria.keys
        let isAppOnlyLocator = criteriaKeys.allSatisfy { appSpecifiers.contains($0) } && criteriaKeys.count == 1

        var foundElement: Element?

        if isAppOnlyLocator {
            dLog("Locator is app-only (criteria: \(locator.criteria)). Using appElement directly.")
            foundElement = effectiveElement
        } else {
            dLog("Locator contains element-specific criteria or is complex. Proceeding with search.")
            var searchStartElementForLocator = appElement
            if let rootPathHint = locator.root_element_path_hint, !rootPathHint.isEmpty {
                dLog(
                    "Locator has root_element_path_hint: \(rootPathHint.joined(separator: " -> ")). Navigating from app element first."
                )
                // Pass logging parameters to navigateToElement
                guard let containerElement = self.navigateToElement(
                    from: appElement,
                    pathHint: rootPathHint,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                ) else {
                    return HandlerResponse(
                        data: nil,
                        error: "Container for locator not found via root_element_path_hint: \(rootPathHint.joined(separator: " -> "))",
                        debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
                    )
                }
                searchStartElementForLocator = containerElement
                dLog(
                    "Searching with locator within container found by root_element_path_hint: \(searchStartElementForLocator.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
                )
            } else {
                searchStartElementForLocator = effectiveElement
                dLog(
                    "Searching with locator from element (determined by main path_hint or app root): \(searchStartElementForLocator.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
                )
            }

            let finalSearchTarget = (pathHint != nil && !pathHint!.isEmpty) ? effectiveElement :
                searchStartElementForLocator

            // Pass logging parameters to search
            foundElement = search(
                element: finalSearchTarget,
                locator: locator,
                requireAction: locator.requireAction,
                maxDepth: maxDepth ?? AXorcist.defaultMaxDepthSearch,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
        }

        if let elementToQuery = foundElement {
            // Pass logging parameters to getElementAttributes
            var attributes = getElementAttributes(
                elementToQuery,
                requestedAttributes: requestedAttributes ?? [],
                forMultiDefault: false,
                targetRole: locator.criteria[kAXRoleAttribute],
                outputFormat: outputFormat ?? .smart,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            if outputFormat == .json_string {
                attributes = encodeAttributesToJSONStringRepresentation(attributes)
            }
            
            let axElement = AXElement(attributes: attributes)
            return HandlerResponse(
                data: axElement,
                error: nil,
                debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
            )
        } else {
            return HandlerResponse(
                data: nil,
                error: "No element matches single query criteria with locator or app-only locator failed to resolve.",
                debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
            )
        }
    }

    // MARK: - handleGetAttributes
    
    @MainActor
    internal func handleGetAttributes(
        for appIdentifierOrNil: String?,
        locator: Locator,
        requestedAttributes: [String]?,
        pathHint: [String]?,
        maxDepth: Int?,
        outputFormat: OutputFormat?,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) async -> HandlerResponse {
        
        func dLog(_ message: String) { if isDebugLoggingEnabled { currentDebugLogs.append(message) } }
        
        let appIdentifier = appIdentifierOrNil ?? self.focusedAppKeyValue
        dLog("Handling get_attributes command for app: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "Application not found: \(appIdentifier)"
            dLog("handleGetAttributes: \(errorMessage)")
            return HandlerResponse(
                data: nil,
                error: errorMessage,
                debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
            )
        }

        // Find element to get attributes from
        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            dLog("handleGetAttributes: Navigating with path_hint: \(pathHint.joined(separator: " -> "))")
            if let navigatedElement = self.navigateToElement(
                from: effectiveElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                effectiveElement = navigatedElement
            } else {
                let errorMessage = "Element not found via path hint: \(pathHint.joined(separator: " -> "))"
                dLog("handleGetAttributes: \(errorMessage)")
                return HandlerResponse(
                    data: nil,
                    error: errorMessage,
                    debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
                )
            }
        }

        dLog(
            "handleGetAttributes: Searching for element with locator: \(locator.criteria) from root: \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
        )
        let foundElement = search(
            element: effectiveElement,
            locator: locator,
            requireAction: locator.requireAction,
            maxDepth: maxDepth ?? AXorcist.defaultMaxDepthSearch,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )

        if let elementToQuery = foundElement {
            dLog(
                "handleGetAttributes: Element found: \(elementToQuery.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)). Fetching attributes: \(requestedAttributes ?? ["all"])..."
            )
            var attributes = getElementAttributes(
                elementToQuery,
                requestedAttributes: requestedAttributes ?? [],
                forMultiDefault: false,
                targetRole: locator.criteria[kAXRoleAttribute],
                outputFormat: outputFormat ?? .smart,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            if outputFormat == .json_string {
                attributes = encodeAttributesToJSONStringRepresentation(attributes)
            }
            dLog(
                "Successfully fetched attributes for element \(elementToQuery.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))."
            )
            
            let axElement = AXElement(attributes: attributes)
            return HandlerResponse(
                data: axElement,
                error: nil,
                debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
            )
        } else {
            let errorMessage = "No element found for get_attributes with locator: \(String(describing: locator))"
            dLog("handleGetAttributes: \(errorMessage)")
            return HandlerResponse(
                data: nil,
                error: errorMessage,
                debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
            )
        }
    }
}