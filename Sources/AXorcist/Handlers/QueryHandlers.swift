import AppKit
import ApplicationServices
import Foundation

// MARK: - Query Handler Methods Extension
extension AXorcist {

    // Handle getting attributes for a specific element using locator
    @MainActor
    public func handleGetAttributes(
        for appIdentifierOrNil: String? = nil,
        locator: Locator,
        requestedAttributes: [String]? = nil,
        pathHint: [String]? = nil,
        maxDepth: Int? = nil,
        outputFormat: OutputFormat? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {
        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append(message)
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("[AXorcist.handleGetAttributes] Handling for app: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "Application not found: \(appIdentifier)"
            dLog("[AXorcist.handleGetAttributes] \(errorMessage)")
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }

        // Find element to get attributes from
        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            let pathHintString = pathHint.joined(separator: " -> ")
            _ = pathHintString // Silences compiler warning
            let logMessage = "[AXorcist.handleGetAttributes] Navigating with path_hint: \(pathHintString)"
            dLog(logMessage)
            if let navigatedElement = navigateToElement(
                from: effectiveElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                effectiveElement = navigatedElement
            } else {
                let pathHintStringForError = pathHint.joined(separator: " -> ")
                _ = pathHintStringForError // Silences compiler warning
                let errorMessageText = "Element not found via path hint: \(pathHintStringForError)"
                dLog("[AXorcist.handleGetAttributes] \(errorMessageText)")
                return HandlerResponse(data: nil, error: errorMessageText, debug_logs: currentDebugLogs)
            }
        }

        var elementToQuery: Element?
        let axApplicationKey = "AXApplication" // String literal for the attribute key

        if locator.criteria.count == 1, let appCritervalue = locator.criteria[axApplicationKey],
           (appCritervalue.uppercased() == "YES" || appCritervalue.uppercased() == "TRUE") {
            let briefDesc = effectiveElement.briefDescription(
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            dLog(
                "[AXorcist.handleGetAttributes] Locator criteria is {'\(axApplicationKey)': '\(appCritervalue)'}. Using effectiveElement (\(briefDesc)) as target."
            )
            elementToQuery = effectiveElement
        } else {
            let rootElementDescription = effectiveElement.briefDescription(
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            dLog(
                "[AXorcist.handleGetAttributes] Not an AXApplication-only locator or value mismatch. Searching for element with locator: \(locator.criteria) from root: \(rootElementDescription)"
            )
            let searchResultGetAttributes = search(
                element: effectiveElement,
                locator: locator,
                requireAction: locator.requireAction,
                maxDepth: maxDepth ?? DEFAULT_MAX_DEPTH_SEARCH,
                isDebugLoggingEnabled: isDebugLoggingEnabled
            )
            currentDebugLogs.append(contentsOf: searchResultGetAttributes.logs)
            elementToQuery = searchResultGetAttributes.foundElement
        }

        if let actualElementToQuery = elementToQuery {
            let elementDescription = actualElementToQuery.briefDescription(
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            let attributesDescription = (requestedAttributes ?? ["all"]).description
            dLog(
                "[AXorcist.handleGetAttributes] Element identified/found: \(elementDescription). Fetching attributes: \(attributesDescription)..."
            )

            var attributes = getElementAttributes(
                actualElementToQuery,
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

            let elementPathArray = actualElementToQuery.generatePathArray(
                upTo: appElement,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            let axElement = AXElement(attributes: attributes, path: elementPathArray)

            dLog(
                "[AXorcist.handleGetAttributes] Successfully fetched attributes for element \(actualElementToQuery.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))."
            )
            return HandlerResponse(data: axElement, error: nil, debug_logs: currentDebugLogs)
        } else {
            let errorMessage = "No element found for get_attributes with locator: \(String(describing: locator))"
            dLog("[AXorcist.handleGetAttributes] \(errorMessage)")
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }
    }

    // Handle query command - find an element matching criteria
    @MainActor
    public func handleQuery(
        for appIdentifierOrNil: String? = nil,
        locator: Locator,
        pathHint: [String]? = nil,
        maxDepth: Int? = nil,
        requestedAttributes: [String]? = nil,
        outputFormat: OutputFormat? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {
        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append(message)
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("[AXorcist.handleQuery] Handling query for app: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "Application not found: \(appIdentifier)"
            dLog("[AXorcist.handleQuery] \(errorMessage)")
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }

        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            let pathHintString = pathHint.joined(separator: " -> ")
            _ = pathHintString // Silences compiler warning
            dLog("[AXorcist.handleQuery] Navigating with path_hint: \(pathHintString)")
            if let navigatedElement = navigateToElement(
                from: effectiveElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                effectiveElement = navigatedElement
            } else {
                let errorMessage = "Element not found via path hint: \(pathHintString)"
                dLog("[AXorcist.handleQuery] \(errorMessage)")
                return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
            }
        }

        // Check if this is an app-only locator (only application/bundle_id/pid/path criteria)
        let appSpecifiers = ["application", "bundle_id", "pid", "path"]
        let criteriaKeys = locator.criteria.keys
        let isAppOnlyLocator = criteriaKeys.allSatisfy { appSpecifiers.contains($0) } && criteriaKeys.count == 1

        var foundElement: Element?

        if isAppOnlyLocator {
            dLog(
                "[AXorcist.handleQuery] Locator is app-only (criteria: \(locator.criteria)). Using appElement directly."
            )
            foundElement = effectiveElement
        } else {
            dLog("[AXorcist.handleQuery] Locator contains element-specific criteria. Proceeding with search.")
            var searchStartElementForLocator = appElement

            if let rootPathHint = locator.root_element_path_hint, !rootPathHint.isEmpty {
                let rootPathHintString = rootPathHint.joined(separator: " -> ")
                _ = rootPathHintString // Silences compiler warning
                dLog(
                    "[AXorcist.handleQuery] Locator has root_element_path_hint: \(rootPathHintString). Navigating from app element first."
                )
                guard let containerElement = navigateToElement(
                    from: appElement,
                    pathHint: rootPathHint,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                ) else {
                    let errorMessage =
                        "Container for locator not found via root_element_path_hint: \(rootPathHintString)"
                    dLog("[AXorcist.handleQuery] \(errorMessage)")
                    return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
                }
                searchStartElementForLocator = containerElement
                let containerDescription = searchStartElementForLocator.briefDescription(
                    option: .default,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
                _ = containerDescription // Silences compiler warning
                dLog(
                    "[AXorcist.handleQuery] Searching with locator within container found by root_element_path_hint: \(containerDescription)"
                )
            } else {
                searchStartElementForLocator = effectiveElement
                let searchDescription = searchStartElementForLocator.briefDescription(
                    option: .default,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
                _ = searchDescription // Silences compiler warning
                dLog(
                    "[AXorcist.handleQuery] Searching with locator from element (determined by main path_hint or app root): \(searchDescription)"
                )
            }

            let finalSearchTarget = (pathHint != nil && !pathHint!.isEmpty) ? effectiveElement :
                searchStartElementForLocator

            let searchResultQuery = search(
                element: finalSearchTarget,
                locator: locator,
                requireAction: locator.requireAction,
                maxDepth: maxDepth ?? DEFAULT_MAX_DEPTH_SEARCH,
                isDebugLoggingEnabled: isDebugLoggingEnabled
            )
            currentDebugLogs.append(contentsOf: searchResultQuery.logs)
            foundElement = searchResultQuery.foundElement
        }

        if let elementToQuery = foundElement {
            let elementDescription = elementToQuery.briefDescription(
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            _ = elementDescription // Silences compiler warning
            dLog("[AXorcist.handleQuery] Element found: \(elementDescription). Fetching attributes...")

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

            let elementPathArray = elementToQuery.generatePathArray(
                upTo: appElement,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            let axElement = AXElement(attributes: attributes, path: elementPathArray)

            dLog("[AXorcist.handleQuery] Successfully found and processed element with query.")
            return HandlerResponse(data: axElement, error: nil, debug_logs: currentDebugLogs)
        } else {
            let errorMessage = "No element matches query criteria with locator: \(String(describing: locator))"
            dLog("[AXorcist.handleQuery] \(errorMessage)")
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }
    }

    // Handle describe element command - provides comprehensive details about a specific element
    @MainActor
    public func handleDescribeElement(
        for appIdentifierOrNil: String? = nil,
        locator: Locator,
        pathHint: [String]? = nil,
        maxDepth: Int? = nil,
        outputFormat: OutputFormat? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {
        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append(message)
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("[AXorcist.handleDescribeElement] Handling for app: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "Application not found: \(appIdentifier)"
            dLog("[AXorcist.handleDescribeElement] \(errorMessage)")
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }

        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            let pathHintString = pathHint.joined(separator: " -> ")
            _ = pathHintString // Silences compiler warning
            dLog("[AXorcist.handleDescribeElement] Navigating with path_hint: \(pathHintString)")
            if let navigatedElement = navigateToElement(
                from: effectiveElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                effectiveElement = navigatedElement
            } else {
                let errorMessage = "Element not found via path hint for describe_element: \(pathHintString)"
                dLog("[AXorcist.handleDescribeElement] \(errorMessage)")
                return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
            }
        }

        let rootElementDescription = effectiveElement.briefDescription(
            option: .default,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
        _ = rootElementDescription // Silences compiler warning
        dLog(
            "[AXorcist.handleDescribeElement] Searching for element with locator: \(locator.criteria) from root: \(rootElementDescription)"
        )
        let searchResultDescribe = search(
            element: effectiveElement,
            locator: locator,
            requireAction: locator.requireAction,
            maxDepth: maxDepth ?? DEFAULT_MAX_DEPTH_SEARCH,
            isDebugLoggingEnabled: isDebugLoggingEnabled
        )
        currentDebugLogs.append(contentsOf: searchResultDescribe.logs)
        let foundElementForDescribe = searchResultDescribe.foundElement

        if let elementToDescribe = foundElementForDescribe {
            let elementDescription = elementToDescribe.briefDescription(
                option: ValueFormatOption.default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            _ = elementDescription // Silences compiler warning
            dLog(
                "[AXorcist.handleDescribeElement] Element found: \(elementDescription). Describing with verbose output..."
            )

            // For describe_element, we typically want ALL attributes with verbose output
            var attributes = getElementAttributes(
                elementToDescribe,
                requestedAttributes: [], // Empty means 'all standard' or 'all known'
                forMultiDefault: true,
                targetRole: locator.criteria[kAXRoleAttribute],
                outputFormat: outputFormat ?? .smart,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )

            if outputFormat == .json_string {
                attributes = encodeAttributesToJSONStringRepresentation(attributes)
            }

            let elementPathArray = elementToDescribe.generatePathArray(
                upTo: appElement,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            let axElement = AXElement(attributes: attributes, path: elementPathArray)

            dLog(
                "[AXorcist.handleDescribeElement] Successfully described element \(elementToDescribe.briefDescription(option: ValueFormatOption.default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))."
            )
            return HandlerResponse(data: axElement, error: nil, debug_logs: currentDebugLogs)
        } else {
            let errorMessage = "No element found for describe_element with locator: \(String(describing: locator))"
            dLog("[AXorcist.handleDescribeElement] \(errorMessage)")
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }
    }
}
