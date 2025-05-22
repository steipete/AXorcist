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
                // Check if the last log entry contains the critical navigation parse failure marker BEFORE adding debug logs
                let lastLogBeforeDebug = currentDebugLogs.last
                let error: String
                if let lastLog = lastLogBeforeDebug, lastLog == "CRITICAL_NAV_PARSE_FAILURE_MARKER" {
                    error = "Navigation parsing failed: Critical marker found."
                } else if let lastLog = lastLogBeforeDebug, lastLog == "CHILD_MATCH_FAILURE_MARKER" {
                    error = "Navigation child match failed: Child match marker found."
                } else {
                    error = "[AXorcist.handlePerformAction] Failed to navigate using path hint: \(pathHint.joined(separator: " -> "))"
                }
                
                // ADD DEBUG LOGGING BLOCK FOR MARKER CHECK
                if isDebugLoggingEnabled {
                    if let actualLastLog = lastLogBeforeDebug {
                        dLog("[MARKER_CHECK] Checked lastLog: '\(actualLastLog)' -> Error: '\(error)'")
                    } else {
                        dLog("[MARKER_CHECK] currentDebugLogs was empty or lastLog was nil -> Error: '\(error)'")
                    }
                }
                // END OF ADDED LOGGING BLOCK
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
                // Check if the last log entry contains the critical navigation parse failure marker BEFORE adding debug logs
                let lastLogBeforeDebug = currentDebugLogs.last
                let errorMessage: String
                if let lastLog = lastLogBeforeDebug, lastLog == "CRITICAL_NAV_PARSE_FAILURE_MARKER" {
                    errorMessage = "Navigation parsing failed: Critical marker found."
                } else if let lastLog = lastLogBeforeDebug, lastLog == "CHILD_MATCH_FAILURE_MARKER" {
                    errorMessage = "Navigation child match failed: Child match marker found."
                } else {
                    errorMessage = "Failed to navigate to element using path hint: \(pathHint.joined(separator: " -> "))"
                }
                
                // ADD DEBUG LOGGING BLOCK FOR MARKER CHECK
                if isDebugLoggingEnabled {
                    if let actualLastLog = lastLogBeforeDebug {
                        dLog("[MARKER_CHECK] Checked lastLog: '\(actualLastLog)' -> Error: '\(errorMessage)'")
                    } else {
                        dLog("[MARKER_CHECK] currentDebugLogs was empty or lastLog was nil -> Error: '\(errorMessage)'")
                    }
                }
                // END OF ADDED LOGGING BLOCK
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
        commandId: String?,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: [String] // No longer inout, logs from caller
    ) -> String {
        self.recursiveCallDebugLogs.removeAll()
        self.recursiveCallDebugLogs.append(contentsOf: currentDebugLogs) // Incorporate initial logs

        let effectiveCommandId = commandId ?? "collectAll_internal_id_error"

        // Centralized JSON encoding helper for CollectAllOutput
        func encode(_ output: CollectAllOutput) -> String {
            let encoder = JSONEncoder()
            encoder.outputFormatting = .prettyPrinted
            do {
                let jsonData = try encoder.encode(output)
                return String(data: jsonData, encoding: .utf8) ?? "{\"error\":\"Failed to encode CollectAllOutput to string (fallback)\"}" // Minimal fallback
            } catch {
                let errorMsgForLog = "Exception encoding CollectAllOutput: \\(error.localizedDescription)"
                self.recursiveCallDebugLogs.append(errorMsgForLog) // Log it
                // Extremely simplified fallback JSON for catastrophic failure of encoder.encode(output)
                return "{\"command_id\":\"Unknown\", \"success\":false, \"command\":\"Unknown\", \"error_message\":\"Catastrophic JSON encoding failure for CollectAllOutput. Original error logged.\", \"collected_elements\":[], \"debug_logs\":[\"Catastrophic JSON encoding failure as well.\"]}"
            }
        }

        func dLog(
            _ message: String,
            _ file: String = #file,
            _ function: String = #function,
            _ line: Int = #line
        ) {
            let logMessage = AXorcist.formatDebugLogMessage(
                message,
                applicationName: appIdentifierOrNil,
                commandID: effectiveCommandId,
                file: file,
                function: function,
                line: line
            )
            self.recursiveCallDebugLogs.append(logMessage)
        }

        let appNameForLog = appIdentifierOrNil ?? "N/A"
        let locatorDesc = String(describing: locator)
        let pathHintDesc = String(describing: pathHint)
        let maxDepthDesc = String(describing: maxDepth)
        dLog(
            "[AXorcist.handleCollectAll] Starting. App: \\(appNameForLog), Locator: \\(locatorDesc), PathHint: \\(pathHintDesc), MaxDepth: \\(maxDepthDesc)"
        )

        let recursionDepthLimit = (maxDepth != nil && maxDepth! >= 0) ? maxDepth! : AXorcist.defaultMaxDepthCollectAll
        let attributesToFetch = requestedAttributes ?? AXorcist.defaultAttributesToFetch
        let effectiveOutputFormat = outputFormat ?? .smart

        dLog(
            "Effective recursionDepthLimit: \\(recursionDepthLimit), attributesToFetch: \\(attributesToFetch.count) items, effectiveOutputFormat: \\(effectiveOutputFormat.rawValue)"
        )

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("Using app identifier: \\(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &self.recursiveCallDebugLogs
        ) else {
            let errorMsg = "Failed to get app element for identifier: \\(appIdentifier)"
            dLog(errorMsg) // errorMsg is already added to recursiveCallDebugLogs by dLog
            return encode(CollectAllOutput(
                command_id: effectiveCommandId,
                success: false,
                command: "collectAll",
                collected_elements: [],
                app_bundle_id: appIdentifier,
                debug_logs: self.recursiveCallDebugLogs
            ))
        }

        var startElement: Element
        if let hint = pathHint, !hint.isEmpty {
            let pathHintString = hint.joined(separator: " -> ")
            dLog("Navigating to path hint: \\(pathHintString)")
            guard let navigatedElement = navigateToElement(
                from: appElement,
                pathHint: hint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &self.recursiveCallDebugLogs
            ) else {
                let lastLogBeforeError = self.recursiveCallDebugLogs.last
                var errorMsg = "Failed to navigate to path: \\(pathHintString)" // Use pre-calculated pathHintString
                if let lastLog = lastLogBeforeError, lastLog == "CRITICAL_NAV_PARSE_FAILURE_MARKER" {
                    errorMsg = "Navigation parsing failed: Critical marker found."
                } else if let lastLog = lastLogBeforeError, lastLog == "CHILD_MATCH_FAILURE_MARKER" {
                    errorMsg = "Navigation child match failed: Child match marker found."
                }
                dLog(errorMsg) // Log the specific navigation error reason
                return encode(CollectAllOutput(
                    command_id: effectiveCommandId,
                    success: false,
                    command: "collectAll",
                    collected_elements: [],
                    app_bundle_id: appIdentifier,
                    debug_logs: self.recursiveCallDebugLogs
                ))
            }
            startElement = navigatedElement
        } else {
            dLog("Using app element as start element")
            startElement = appElement
        }

        if let loc = locator {
            dLog("Locator provided. Searching for element from current startElement: \\(startElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) with locator: \\(loc.description)")
            if let locatedStartElement = search(element: startElement, locator: loc, requireAction: loc.requireAction, depth: 0, maxDepth: Self.defaultMaxDepthSearch, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs) {
                dLog("Locator found element: \\(locatedStartElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)). This will be the root for collectAll recursion.")
                startElement = locatedStartElement
            } else {
                let errorMsg = "Failed to find element with provided locator: \\(loc.description). Cannot start collectAll."
                dLog(errorMsg)
                return encode(CollectAllOutput(
                    command_id: effectiveCommandId,
                    success: false,
                    command: "collectAll",
                    collected_elements: [],
                    app_bundle_id: appIdentifier,
                    debug_logs: self.recursiveCallDebugLogs
                ))
            }
        }

        var collectedAXElements: [AXElement] = []
        var collectRecursively: ((AXUIElement, Int) -> Void)!
        collectRecursively = { axUIElement, currentDepth in
            if currentDepth > recursionDepthLimit {
                dLog(
                    "Reached recursionDepthLimit (\\(recursionDepthLimit)) at element \\(Element(axUIElement).briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)), stopping recursion for this branch."
                )
                return
            }

            let currentElement = Element(axUIElement)
            dLog("Collecting element \\(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) at depth \\(currentDepth)")

            let fetchedAttrs = getElementAttributes(
                currentElement,
                requestedAttributes: attributesToFetch,
                forMultiDefault: true,
                targetRole: nil,
                outputFormat: effectiveOutputFormat,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &self.recursiveCallDebugLogs
            )

            let elementPath = currentElement.generatePathArray(
                upTo: appElement,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &self.recursiveCallDebugLogs
            )
            let axElement = AXElement(attributes: fetchedAttrs, path: elementPath)
            collectedAXElements.append(axElement)

            var childrenRef: CFTypeRef?
            let childrenResult = AXUIElementCopyAttributeValue(
                axUIElement,
                kAXChildrenAttribute as CFString,
                &childrenRef
            )

            if childrenResult == .success, let children = childrenRef as? [AXUIElement] {
                dLog(
                    "Element \\(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) has \\(children.count) children at depth \\(currentDepth). Recursing."
                )
                for childElement in children {
                    collectRecursively(childElement, currentDepth + 1)
                }
            } else if childrenResult != .success {
                dLog(
                    "Failed to get children for element \\(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)): \\(axErrorToString(childrenResult))"
                )
            } else {
                dLog(
                    "No children found for element \\(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs)) at depth \\(currentDepth)"
                )
            }
        }

        dLog(
            "Starting recursive collection from start element: \\(startElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &self.recursiveCallDebugLogs))"
        )
        collectRecursively(startElement.underlyingElement, 0)

        dLog("Collection complete. Found \\(collectedAXElements.count) elements.")

        return encode(CollectAllOutput(
            command_id: effectiveCommandId,
            success: true,
            command: "collectAll",
            collected_elements: collectedAXElements,
            app_bundle_id: appIdentifier,
            debug_logs: self.recursiveCallDebugLogs
        ))
    }

    // Helper to encode CollectAllOutput, ensure it exists in AXorcist or is added.
    // If it doesn't exist, this edit will require it.
    // For now, assuming it's available.
    // private func encodeOutputToJSON(output: CollectAllOutput) -> String {
    //     let encoder = JSONEncoder()
    //     encoder.outputFormatting = .prettyPrinted
    //     do {
    //         let data = try encoder.encode(output)
    //         return String(data: data, encoding: .utf8) ?? "{\\"error\\":\\"Failed to encode CollectAllOutput to JSON string\\"}"
    //     } catch {
    //         return "{\\"error\\":\\"Exception encoding CollectAllOutput: \\(error.localizedDescription)\\"}"
    //     }
    // }
}

