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
            var searchStartElementForLocator = effectiveElement
            if let rootPathHint = locator.root_element_path_hint, !rootPathHint.isEmpty {
                dLog(
                    "Locator has root_element_path_hint: \(rootPathHint.joined(separator: " -> ")). Navigating from app element first."
                )
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
                    "Searching with locator within container found by root_element_path_hint: \(searchStartElementForLocator.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
                )
            } else {
                dLog(
                    "Searching with locator from element (determined by main path_hint or app root): \(searchStartElementForLocator.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
                )
            }
            
            let searchResult = search(
                element: searchStartElementForLocator,
                locator: locator,
                requireAction: locator.requireAction,
                depth: 0,
                maxDepth: maxDepth ?? AXorcist.defaultMaxDepthSearch,
                isDebugLoggingEnabled: isDebugLoggingEnabled
            )
            currentDebugLogs.append("HANDLER_DEBUG: searchResult.logs.count = \(searchResult.logs.count) before append for query")
            currentDebugLogs.append(contentsOf: searchResult.logs)
            currentDebugLogs.append("POST_SEARCH_LOG_APPEND_MARKER_IN_QUERY")
            foundElement = searchResult.foundElement
        }

        if let elementToQuery = foundElement {
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
            "handleGetAttributes: Searching for element with locator: \(locator.criteria) from root: \(effectiveElement.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
        )
        let searchResult = search(
            element: effectiveElement,
            locator: locator,
            requireAction: locator.requireAction,
            depth: 0,
            maxDepth: maxDepth ?? AXorcist.defaultMaxDepthSearch,
            isDebugLoggingEnabled: isDebugLoggingEnabled
        )
        currentDebugLogs.append("HANDLER_DEBUG: searchResult.logs.count = \(searchResult.logs.count) before append for getAttributes")
        currentDebugLogs.append(contentsOf: searchResult.logs)
        currentDebugLogs.append("POST_SEARCH_LOG_APPEND_MARKER_IN_GET_ATTRIBUTES")
        let foundElement = searchResult.foundElement

        if let elementToQuery = foundElement {
            dLog(
                "handleGetAttributes: Element found: \(elementToQuery.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)). Fetching attributes: \(requestedAttributes ?? ["all"])..."
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
                "Successfully fetched attributes for element \(elementToQuery.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))."
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
    
    @MainActor
    public func handleDescribeElement(
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
        dLog("Handling describe_element for app: \(appIdentifier)")

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
            dLog("handleDescribeElement: Navigating with path_hint: \(pathHint.joined(separator: " -> "))")
            if let navigatedElement = self.navigateToElement(
                from: appElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                effectiveElement = navigatedElement
            } else {
                let errorMessage = "Element not found via path hint for describe: \(pathHint.joined(separator: " -> "))"
                dLog("handleDescribeElement: \(errorMessage)")
                return HandlerResponse(
                    data: nil,
                    error: errorMessage,
                    debug_logs: isDebugLoggingEnabled ? currentDebugLogs : nil
                )
            }
        }

        dLog(
            "[AXorcist.handleDescribeElement] Searching for element to describe using locator: \(locator.criteria) from effective element: \(effectiveElement.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
        )
        
        let searchMaxDepth = maxDepth ?? AXorcist.defaultMaxDepthSearch 

        let searchResult = search(
            element: effectiveElement,
            locator: locator,
            requireAction: locator.requireAction,
            depth: 0,
            maxDepth: searchMaxDepth, 
            isDebugLoggingEnabled: isDebugLoggingEnabled
        )
        currentDebugLogs.append("HANDLER_DEBUG: searchResult.logs.count = \(searchResult.logs.count) before append for describeElement")
        currentDebugLogs.append(contentsOf: searchResult.logs)
        currentDebugLogs.append("POST_SEARCH_LOG_APPEND_MARKER_IN_DESCRIBE")
        guard let elementToDescribe = searchResult.foundElement else {
            let error = "[AXorcist.handleDescribeElement] Element to describe not found for locator: \(locator.criteria)"
            currentDebugLogs.append(error)
            return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
        }
        
        dLog(
            "[AXorcist.handleDescribeElement] Element found: \(elementToDescribe.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)). Now describing."
        )
        
        var attributes = getElementAttributes(
            elementToDescribe,
            requestedAttributes: requestedAttributes ?? ["all"], 
            forMultiDefault: true, 
            targetRole: locator.criteria[kAXRoleAttribute],
            outputFormat: outputFormat ?? .verbose,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
        if outputFormat == .json_string {
            attributes = encodeAttributesToJSONStringRepresentation(attributes)
        }

        let axElement = AXElement(
            attributes: attributes,
            path: elementToDescribe.generatePathArray(upTo: appElement, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
        )
        
        return HandlerResponse(data: axElement, error: nil, debug_logs: currentDebugLogs)
    }
}