// AXorcist+ActionHandlers.swift - Action and data operation handlers

import AppKit
import ApplicationServices
import Foundation

// MARK: - Action & Data Handlers Extension
extension AXorcist {

    @MainActor
    public func handlePerformAction(
        for appIdentifierOrNil: String? = nil,
        locator: Locator,
        pathHint: [String]? = nil,
        actionName: String,
        actionValue: AnyCodable?,
        maxDepth: Int? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {

        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append(message)
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("[AXorcist.handlePerformAction] Handling for app: \(appIdentifier), action: \(actionName)")

        guard let appElement = applicationElement(for: appIdentifier, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) else {
            let error = "[AXorcist.handlePerformAction] Failed to get application element for identifier: \(appIdentifier)"
            dLog(error)
            return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
        }

        var effectiveElement = appElement

        if let pathHint = pathHint, !pathHint.isEmpty {
            dLog("[AXorcist.handlePerformAction] Navigating with path_hint: \(pathHint.joined(separator: " -> "))")
            guard let navigatedElement = navigateToElement(from: effectiveElement, pathHint: pathHint, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) else {
                let error = "[AXorcist.handlePerformAction] Failed to navigate using path hint: \(pathHint.joined(separator: " -> "))"
                dLog(error)
                return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
            }
            effectiveElement = navigatedElement
        }

        dLog("[AXorcist.handlePerformAction] Searching for element with locator: \(locator.criteria) from root: \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        guard let foundElement = search(element: effectiveElement, locator: locator, requireAction: locator.requireAction, depth: 0, maxDepth: maxDepth ?? DEFAULT_MAX_DEPTH_SEARCH, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) else {
            let error = "[AXorcist.handlePerformAction] Failed to find element with locator: \(locator)"
            dLog(error)
            return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
        }

        dLog("[AXorcist.handlePerformAction] Found element: \(foundElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        if let actionValue = actionValue {
            // Attempt to get a string representation of actionValue.value for logging
            // This is a basic attempt; complex types might not log well.
            let valueDescription = String(describing: actionValue.value)
            dLog("[AXorcist.handlePerformAction] Performing action '\(actionName)' with value: \(valueDescription)")
        } else {
            dLog("[AXorcist.handlePerformAction] Performing action '\(actionName)'")
        }

        var errorMessage: String?
        var axStatus: AXError = .success // Initialize to success

        switch actionName.lowercased() {
        case "press":
            axStatus = AXUIElementPerformAction(foundElement.underlyingElement, kAXPressAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform press action: \(axErrorToString(axStatus))"
            }
        case "increment":
            axStatus = AXUIElementPerformAction(foundElement.underlyingElement, kAXIncrementAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform increment action: \(axErrorToString(axStatus))"
            }
        case "decrement":
            axStatus = AXUIElementPerformAction(foundElement.underlyingElement, kAXDecrementAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform decrement action: \(axErrorToString(axStatus))"
            }
        case "showmenu":
            axStatus = AXUIElementPerformAction(foundElement.underlyingElement, kAXShowMenuAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform showmenu action: \(axErrorToString(axStatus))"
            }
        case "pick":
            axStatus = AXUIElementPerformAction(foundElement.underlyingElement, kAXPickAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform pick action: \(axErrorToString(axStatus))"
            }
        case "cancel":
            axStatus = AXUIElementPerformAction(foundElement.underlyingElement, kAXCancelAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform cancel action: \(axErrorToString(axStatus))"
            }
        default:
            if actionName.hasPrefix("AX") {
                axStatus = AXUIElementPerformAction(foundElement.underlyingElement, actionName as CFString)
                if axStatus != .success {
                    errorMessage = "[AXorcist.handlePerformAction] Failed to perform action '\(actionName)': \(axErrorToString(axStatus))"
                }
            } else {
                if let actionValue = actionValue {
                    var cfValue: CFTypeRef?
                    // Convert basic Swift types to CFTypeRef for setting attributes
                    switch actionValue.value {
                    case let stringValue as String:
                        cfValue = stringValue as CFString
                    case let boolValue as Bool:
                        cfValue = boolValue as CFBoolean
                    case let intValue as Int:
                        var number = intValue
                        cfValue = CFNumberCreate(kCFAllocatorDefault, .intType, &number)
                    case let doubleValue as Double:
                        var number = doubleValue
                        cfValue = CFNumberCreate(kCFAllocatorDefault, .doubleType, &number)
                    // TODO: Consider other CFNumber types if necessary (CGFloat, etc.)
                    // TODO: Consider CFArray, CFDictionary if complex values are needed.
                    default:
                        // For other types, attempt a direct cast if possible, or log/error.
                        // This is a simplification; robust conversion is more involved.
                        if CFGetTypeID(actionValue.value as AnyObject) != 0 { // Basic check if it *might* be a CFType
                            cfValue = actionValue.value as AnyObject // bridge from Any to AnyObject then to CFTypeRef
                            dLog("[AXorcist.handlePerformAction] Warning: Attempting to use actionValue of type '\(type(of: actionValue.value))' directly as CFTypeRef for attribute '\(actionName)'. This might not work as expected.")
                        } else {
                            errorMessage = "[AXorcist.handlePerformAction] Unsupported value type '\(type(of: actionValue.value))' for attribute '\(actionName)'. Cannot convert to CFTypeRef."
                            dLog(errorMessage!)
                        }
                    }

                    if errorMessage == nil, let finalCFValue = cfValue {
                        axStatus = AXUIElementSetAttributeValue(foundElement.underlyingElement, actionName as CFString, finalCFValue)
                        if axStatus != .success {
                            errorMessage = "[AXorcist.handlePerformAction] Failed to set attribute '\(actionName)' to value '\(String(describing: actionValue.value))': \(axErrorToString(axStatus))"
                        }
                    } else if errorMessage == nil { // cfValue was nil, means conversion failed earlier but wasn't caught by the default error
                        errorMessage = "[AXorcist.handlePerformAction] Failed to convert value for attribute '\(actionName)' to a CoreFoundation type."
                    }
                } else {
                    errorMessage = "[AXorcist.handlePerformAction] Unknown action '\(actionName)' and no action_value provided to interpret as an attribute."
                }
            }
        }

        if let currentErrorMessage = errorMessage {
            dLog(currentErrorMessage)
            return HandlerResponse(data: nil, error: currentErrorMessage, debug_logs: currentDebugLogs)
        }

        dLog("[AXorcist.handlePerformAction] Action '\(actionName)' performed successfully.")
        return HandlerResponse(data: nil, error: nil, debug_logs: currentDebugLogs)
    }

    @MainActor
    public func handleExtractText(
        for appIdentifierOrNil: String? = nil,
        locator: Locator,
        pathHint: [String]? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {
        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append("[handleExtractText] \(message)")
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("Starting text extraction for app: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "Failed to get application element for \(appIdentifier)"
            dLog(errorMessage)
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }

        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            dLog("Navigating to element using path hint: \(pathHint.joined(separator: " -> "))")
            guard let navigatedElement = navigateToElement(
                from: appElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) else {
                let errorMessage =
                    "Failed to navigate to element using path hint: \(pathHint.joined(separator: " -> "))"
                dLog(errorMessage)
                return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
            }
            effectiveElement = navigatedElement
        }

        dLog("Searching for target element with locator: \(locator)")
        // Assuming DEFAULT_MAX_DEPTH_SEARCH is defined elsewhere, e.g., in AXConstants.swift or similar.
        // If not, replace with a sensible default like 10.
        guard let foundElement = search(
            element: effectiveElement,
            locator: locator,
            requireAction: locator.requireAction,
            maxDepth: DEFAULT_MAX_DEPTH_SEARCH,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "Target element not found for locator: \(locator)"
            dLog(errorMessage)
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }

        dLog(
            "Target element found: \(foundElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)), attempting to extract text"
        )
        var attributes: [String: AnyCodable] = [:]
        var extractedValueText: String?
        var extractedSelectedText: String?

        var cfValue: CFTypeRef?
        if AXUIElementCopyAttributeValue(foundElement.underlyingElement, kAXValueAttribute as CFString, &cfValue) ==
            .success, let value = cfValue {
            if CFGetTypeID(value) == CFStringGetTypeID() {
                extractedValueText = (value as! CFString) as String
                if let extractedValueText = extractedValueText, !extractedValueText.isEmpty {
                    attributes["extractedValue"] = AnyCodable(extractedValueText)
                    dLog(
                        "Extracted text from kAXValueAttribute (length: \(extractedValueText.count)): \(extractedValueText.prefix(80))..."
                    )
                } else {
                    dLog("kAXValueAttribute was empty or not a string.")
                }
            } else {
                dLog("kAXValueAttribute was present but not a CFString. TypeID: \(CFGetTypeID(value))")
            }
        } else {
            dLog("Failed to get kAXValueAttribute or it was nil.")
        }

        cfValue = nil // Reset for next attribute
        if AXUIElementCopyAttributeValue(
            foundElement.underlyingElement,
            kAXSelectedTextAttribute as CFString,
            &cfValue
        ) == .success, let selectedValue = cfValue {
            if CFGetTypeID(selectedValue) == CFStringGetTypeID() {
                extractedSelectedText = (selectedValue as! CFString) as String
                if let extractedSelectedText = extractedSelectedText, !extractedSelectedText.isEmpty {
                    attributes["extractedSelectedText"] = AnyCodable(extractedSelectedText)
                    dLog(
                        "Extracted selected text from kAXSelectedTextAttribute (length: \(extractedSelectedText.count)): \(extractedSelectedText.prefix(80))..."
                    )
                } else {
                    dLog("kAXSelectedTextAttribute was empty or not a string.")
                }
            } else {
                dLog("kAXSelectedTextAttribute was present but not a CFString. TypeID: \(CFGetTypeID(selectedValue))")
            }
        } else {
            dLog("Failed to get kAXSelectedTextAttribute or it was nil.")
        }


        if attributes.isEmpty {
            dLog(
                "Warning: No text could be extracted from the element via kAXValueAttribute or kAXSelectedTextAttribute."
            )
            // It's not an error, just means no text content via these primary attributes.
            // Other attributes might still be relevant, so we return the element.
        }

        let elementPathArray = foundElement.generatePathArray(
            upTo: appElement,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
        // Include any other relevant attributes if needed, for now just the extracted text
        let axElement = AXElement(attributes: attributes, path: elementPathArray)

        dLog("Text extraction process completed.")
        return HandlerResponse(data: axElement, error: nil, debug_logs: currentDebugLogs)
    }

    @MainActor
    public func handleCollectAll(
        for appIdentifierOrNil: String?,
        locator: Locator?,
        pathHint: [String]?,
        maxDepth: Int?, // This is the input from the command
        requestedAttributes: [String]?,
        outputFormat: OutputFormat?,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: [String] // No longer inout, logs from caller
    ) -> String {
        self.recursiveCallDebugLogs.removeAll()
        self.recursiveCallDebugLogs.append(contentsOf: currentDebugLogs) // Incorporate initial logs

        // Local dLog now appends to self.recursiveCallDebugLogs
        func dLog(
            _ message: String,
            subCommandID: String? = nil,
            _ file: String = #file,
            _ function: String = #function,
            _ line: Int = #line
        ) {
            let logMessage = AXorcist.formatDebugLogMessage(
                message,
                applicationName: appIdentifierOrNil,
                commandID: subCommandID,
                file: file,
                function: function,
                line: line
            )
            self.recursiveCallDebugLogs.append(logMessage)
        }

        dLog(
            "[AXorcist.handleCollectAll] Starting. App: \(appIdentifierOrNil ?? "N/A"), Locator: \(String(describing: locator)), PathHint: \(String(describing: pathHint)), MaxDepth: \(String(describing: maxDepth))"
        )

        // Determine effectiveMaxDepth based on input or default
        // Ensure maxDepth is at least 0 if provided, otherwise use default.
        // A negative input maxDepth doesn't make sense for collection, treat as default.
        let recursionDepthLimit = (maxDepth != nil && maxDepth! >= 0) ? maxDepth! : AXorcist.defaultMaxDepthCollectAll

        dLog(
            "Initial input maxDepth: \(String(describing: maxDepth)), AXorcist.defaultMaxDepthCollectAll: \(AXorcist.defaultMaxDepthCollectAll). Calculated recursionDepthLimit: \(recursionDepthLimit)"
        )

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("Using app identifier: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &self.recursiveCallDebugLogs
        ) else {
            let errorMsg = "Failed to get app element for identifier: \(appIdentifier)"
            dLog(errorMsg)
            // Return error as JSON string
            let errorResponse = QueryResponse(
                command_id: "collectAll",
                success: false,
                command: "collectAll",
                data: nil,
                attributes: nil,
                error: errorMsg,
                debug_logs: self.recursiveCallDebugLogs
            )
            return (try? errorResponse.jsonString()) ?? "{\"error\":\"Failed to get app element\"}"
        }

        var startElement: Element
        if let hint = pathHint, !hint.isEmpty {
            dLog("Navigating to path hint: \(hint.joined(separator: " -> "))")
            guard let navigatedElement = navigateToElement(
                from: appElement,
                pathHint: hint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &self.recursiveCallDebugLogs
            ) else {
                let errorMsg = "Failed to navigate to path: \(hint.joined(separator: " -> "))"
                dLog(errorMsg)
                let errorResponse = QueryResponse(
                    command_id: "collectAll",
                    success: false,
                    command: "collectAll",
                    data: nil,
                    attributes: nil,
                    error: errorMsg,
                    debug_logs: self.recursiveCallDebugLogs
                )
                return (try? errorResponse.jsonString()) ?? "{\"error\":\"Failed to navigate to path\"}"
            }
            startElement = navigatedElement
        } else {
            dLog("Using app element as start element")
            startElement = appElement
        }

        var collectedAXElements: [AXElement] = []
        let effectiveMaxDepth = maxDepth ?? 8
        dLog("Max collection depth: \(effectiveMaxDepth)")

        var collectRecursively: ((AXUIElement, Int) -> Void)!
        collectRecursively = { axUIElement, currentDepth in
            // Use the correctly scoped recursionDepthLimit here
            if currentDepth > recursionDepthLimit {
                dLog(
                    "Reached recursionDepthLimit (\(recursionDepthLimit)) at element \(Element(axUIElement).briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)), stopping recursion for this branch."
                )
                return
            }

            let currentElement = Element(axUIElement)

            var shouldIncludeElement = true
            // If we are at depth 0 (the start element itself) AND a locator was provided,
            // then this start element must match the locator.
            // For all children (depth > 0), or if no locator was provided at all,
            // elements are included by default.
            if currentDepth == 0 && locator != nil {
                if let loc = locator {
                    // Re-check locator, though it should be non-nil if currentDepth == 0 && locator != nil condition was met
                    let matchStatus = evaluateElementAgainstCriteria(
                        element: currentElement,
                        locator: loc,
                        actionToVerify: loc.requireAction,
                        depth: currentDepth, // currentDepth is 0 here
                        isDebugLoggingEnabled: isDebugLoggingEnabled,
                        currentDebugLogs: &self.recursiveCallDebugLogs
                    )
                    if matchStatus != .fullMatch {
                        shouldIncludeElement = false
                        dLog(
                            "Start element (depth 0) \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) did not fully match locator (status: \(matchStatus)), not collecting it. This might indicate an issue if a start element was expected."
                        )
                    } else {
                        dLog(
                            "Start element (depth 0) \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) matched locator. Collecting it."
                        )
                    }
                }
            } else if locator != nil && currentDepth > 0 {
                // For children of the start element (depth > 0), when a locator was initially provided,
                // we still log that we *would have* checked, but we will include them anyway.
                dLog(
                    "Element \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) at depth \(currentDepth) is a child of a located start element. Including it regardless of initial locator criteria."
                )
            }
            // If locator was nil initially, shouldIncludeElement remains true.
            if shouldIncludeElement {
                dLog(
                    "Collecting element \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) at depth \(currentDepth)"
                )

                let fetchedAttrs = getElementAttributes(
                    currentElement,
                    requestedAttributes: requestedAttributes ?? [],
                    forMultiDefault: true,
                    targetRole: nil as String?,
                    outputFormat: outputFormat ?? .smart,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &self.recursiveCallDebugLogs // Pass self.recursiveCallDebugLogs
                )

                let elementPath = currentElement.generatePathArray(
                    upTo: appElement,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &self.recursiveCallDebugLogs // Pass self.recursiveCallDebugLogs
                )

                let axElement = AXElement(attributes: fetchedAttrs, path: elementPath)
                collectedAXElements.append(axElement)
            } else if locator != nil {
                dLog(
                    "Element \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) did not match locator. Still checking children."
                )
            }

            var childrenRef: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(
                axUIElement,
                kAXChildrenAttribute as CFString,
                &childrenRef
            )

            if childrenResult == .success, let children = childrenRef as? [AXUIElement] {
                dLog(
                    "Element \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) has \(children.count) children at depth \(currentDepth). Recursing."
                )
                for childElement in children {
                    collectRecursively(childElement, currentDepth + 1)
                }
            } else if childrenResult != .success {
                dLog(
                    "Failed to get children for element \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)): \(axErrorToString(childrenResult))"
                )
            } else {
                dLog(
                    "No children found for element \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) at depth \(currentDepth)"
                )
            }
        }

        dLog(
            "Starting recursive collection from start element: \(startElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs))"
        )
        collectRecursively(startElement.underlyingElement, 0)

        dLog(
            "Collection complete. Found \(collectedAXElements.count) elements matching criteria (if any). Naming them 'collected_elements' in response."
        )

        // Create and encode CollectAllOutput directly
        let output = CollectAllOutput(
            command_id: "collectAll", // Consider making this dynamic if original command_id is available
            success: true,
            command: "collectAll", // Consider making this dynamic
            collected_elements: collectedAXElements,
            app_bundle_id: appIdentifier,
            debug_logs: isDebugLoggingEnabled ? self.recursiveCallDebugLogs : nil
        )

        do {
            let encoder = JSONEncoder()
            if #available(macOS 10.13, *) {
                encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
            } else {
                encoder.outputFormatting = .prettyPrinted
            }
            let jsonData = try encoder.encode(output)
            return String(data: jsonData, encoding: .utf8) ?? #"{"error":"Serialization_failed_to_string"}"#
        } catch {
            let errorMsg = "handleCollectAll: Failed to encode CollectAllOutput to JSON: \(error.localizedDescription) - \(error)"
            dLog(errorMsg) // Log the detailed error

            // Build error response as dictionary and try to serialize it
            var errorDict: [String: Any] = [
                "command_id": "collectAll",
                "success": false,
                "command": "collectAll",
                "error": errorMsg
            ]

            if isDebugLoggingEnabled {
                errorDict["debug_logs"] = self.recursiveCallDebugLogs
            }

            do {
                let errorJsonData = try JSONSerialization.data(withJSONObject: errorDict, options: [])
                return String(data: errorJsonData, encoding: .utf8) ?? #"{"error":"handleCollectAll: Catastrophic failure to encode error response"}"#
            } catch {
                return #"{"error":"handleCollectAll: Catastrophic failure to encode error response"}"#
            }
        }
    }
}
