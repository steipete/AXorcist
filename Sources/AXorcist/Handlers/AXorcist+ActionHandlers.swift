// AXorcist+ActionHandlers.swift - Action and data operation handlers

import AppKit
import ApplicationServices
import Darwin
import Foundation

// MARK: - Action & Data Handlers Extension
extension AXorcist {

    @MainActor
    public func handlePerformAction(
        for appIdentifierOrNil: String? = nil,
        locator: Locator?,
        pathHint: [String]? = nil,
        actionName: String,
        actionValue: AnyCodable?,
        maxDepth: Int? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {

        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append(AXorcist.formatDebugLogMessage(message, applicationName: appIdentifierOrNil, commandID: nil, file: #file, function: #function, line: #line))
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("[AXorcist.handlePerformAction] Handling for app: \(appIdentifier), action: \(actionName)")

        guard let appElement = applicationElement(for: appIdentifier, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) else {
            let error = "[AXorcist.handlePerformAction] Failed to get application element for identifier: \(appIdentifier)"
            currentDebugLogs.append(error)
            return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
        }

        var effectiveElement = appElement

        if let pathHint = pathHint, !pathHint.isEmpty {
            dLog("[AXorcist.handlePerformAction] Navigating with path_hint: \(pathHint.joined(separator: " -> ")) from root \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
            guard let navigatedElement = navigateToElement(from: effectiveElement, pathHint: pathHint, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) else {
                let lastLogBeforeDebug = currentDebugLogs.last
                let error: String
                if let lastLog = lastLogBeforeDebug, lastLog.contains("CRITICAL_NAV_PARSE_FAILURE_MARKER") {
                    error = "Navigation parsing failed (critical marker found) for path hint: \(pathHint.joined(separator: " -> "))"
                } else if let lastLog = lastLogBeforeDebug, lastLog.contains("CHILD_MATCH_FAILURE_MARKER") {
                    error = "Navigation child match failed (child match marker found) for path hint: \(pathHint.joined(separator: " -> "))"
                } else {
                    error = "[AXorcist.handlePerformAction] Failed to navigate using path hint: \(pathHint.joined(separator: " -> "))"
                }
                
                if isDebugLoggingEnabled {
                    if let actualLastLog = lastLogBeforeDebug {
                        dLog("[MARKER_CHECK] Checked lastLog for markers -> Error: '\(error)'. LastLog: '\(actualLastLog)'")
                    } else {
                        dLog("[MARKER_CHECK] currentDebugLogs was empty or lastLog was nil -> Error: '\(error)'")
                    }
                }
                currentDebugLogs.append(error)
                return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
            }
            effectiveElement = navigatedElement
            dLog("[AXorcist.handlePerformAction] Successfully navigated path_hint. New effectiveElement: \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        }

        let targetElementForAction: Element
        if let actualLocator = locator {
            dLog("[AXorcist.handlePerformAction] Locator provided. Searching from current effectiveElement: \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)) using locator criteria: \(actualLocator.criteria)")
            
            let searchResult = search(
                element: effectiveElement,
                locator: actualLocator,
                requireAction: actualLocator.requireAction,
                depth: 0,
                maxDepth: maxDepth ?? DEFAULT_MAX_DEPTH_SEARCH,
                isDebugLoggingEnabled: isDebugLoggingEnabled
            )
            fputs("HANDLER_RAW_STDERR_BEFORE_LOG_APPEND handlePerformAction: searchResult.logs.count = \(searchResult.logs.count), currentDebugLogs count = \(currentDebugLogs.count)\n", stderr)
            currentDebugLogs.append("HANDLER_DEBUG: searchResult.logs.count = \(searchResult.logs.count) before append for performAction")
            currentDebugLogs.append(contentsOf: searchResult.logs)
            fputs("HANDLER_RAW_STDERR_AFTER_LOG_APPEND handlePerformAction: currentDebugLogs count = \(currentDebugLogs.count)\n", stderr)
            currentDebugLogs.append("POST_SEARCH_LOG_APPEND_MARKER_IN_HANDLER")

            guard let foundElement = searchResult.foundElement else {
                let error = "[AXorcist.handlePerformAction] Search failed. Could not find element matching locator criteria \(actualLocator.criteria) starting from element \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))."
                if !currentDebugLogs.contains(error) {
                    currentDebugLogs.append(error)
                }
                return HandlerResponse(data: nil, error: error, debug_logs: currentDebugLogs)
            }
            targetElementForAction = foundElement
            dLog("[AXorcist.handlePerformAction] Found element via locator: \(targetElementForAction.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        } else {
            targetElementForAction = effectiveElement
            dLog("[AXorcist.handlePerformAction] No locator provided. Using current effectiveElement as target: \(targetElementForAction.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        }
        
        dLog("[AXorcist.handlePerformAction] Element for action: \(targetElementForAction.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        if let actionValue = actionValue {
            let valueDescription = String(describing: actionValue.value)
            dLog("[AXorcist.handlePerformAction] Performing action '\(actionName)' with value: \(valueDescription)")
        } else {
            dLog("[AXorcist.handlePerformAction] Performing action '\(actionName)'")
        }

        var errorMessage: String?
        var axStatus: AXError = .success

        switch actionName.lowercased() {
        case "press":
            axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, kAXPressAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform press action: \(axErrorToString(axStatus))"
            }
        case "increment":
            axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, kAXIncrementAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform increment action: \(axErrorToString(axStatus))"
            }
        case "decrement":
            axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, kAXDecrementAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform decrement action: \(axErrorToString(axStatus))"
            }
        case "showmenu":
            axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, kAXShowMenuAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform showmenu action: \(axErrorToString(axStatus))"
            }
        case "pick":
            axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, kAXPickAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform pick action: \(axErrorToString(axStatus))"
            }
        case "cancel":
            axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, kAXCancelAction as CFString)
            if axStatus != .success {
                errorMessage = "[AXorcist.handlePerformAction] Failed to perform cancel action: \(axErrorToString(axStatus))"
            }
        default:
            if actionName.hasPrefix("AX") {
                axStatus = AXUIElementPerformAction(targetElementForAction.underlyingElement, actionName as CFString)
                if axStatus != .success {
                    errorMessage = "[AXorcist.handlePerformAction] Failed to perform action '\(actionName)': \(axErrorToString(axStatus))"
                }
            } else {
                if let actionValue = actionValue {
                    var cfValue: CFTypeRef?
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
                    default:
                        if CFGetTypeID(actionValue.value as AnyObject) != 0 {
                            cfValue = actionValue.value as AnyObject
                            dLog("[AXorcist.handlePerformAction] Warning: Attempting to use actionValue of type '\(type(of: actionValue.value))' directly as CFTypeRef for attribute '\(actionName)'. This might not work as expected.")
                        } else {
                            errorMessage = "[AXorcist.handlePerformAction] Unsupported value type '\(type(of: actionValue.value))' for attribute '\(actionName)'. Cannot convert to CFTypeRef."
                            dLog(errorMessage!)
                        }
                    }

                    if errorMessage == nil, let finalCFValue = cfValue {
                        axStatus = AXUIElementSetAttributeValue(targetElementForAction.underlyingElement, actionName as CFString, finalCFValue)
                        if axStatus != .success {
                            errorMessage = "[AXorcist.handlePerformAction] Failed to set attribute '\(actionName)' to value '\(String(describing: actionValue.value))': \(axErrorToString(axStatus))"
                        }
                    } else if errorMessage == nil {
                        errorMessage = "[AXorcist.handlePerformAction] Failed to convert value for attribute '\(actionName)' to a CoreFoundation type."
                    }
                } else {
                    errorMessage = "[AXorcist.handlePerformAction] Attribute action '\(actionName)' requires an action_value, but none was provided."
                }
            }
        }

        if let currentErrorMessage = errorMessage {
            currentDebugLogs.append(currentErrorMessage)
            return HandlerResponse(data: nil, error: currentErrorMessage, debug_logs: currentDebugLogs)
        }

        dLog("[AXorcist.handlePerformAction] Action '\(actionName)' performed successfully.")
        return HandlerResponse(data: nil, error: nil, debug_logs: currentDebugLogs)
    }

    @MainActor
    public func handleExtractText(
        for appIdentifierOrNil: String? = nil,
        locator: Locator?,
        pathHint: [String]? = nil,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> HandlerResponse {
        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                currentDebugLogs.append(AXorcist.formatDebugLogMessage(message, applicationName: appIdentifierOrNil, commandID: nil, file: #file, function: #function, line: #line))
            }
        }

        let appIdentifier = appIdentifierOrNil ?? focusedAppKeyValue
        dLog("[handleExtractText] Starting text extraction for app: \(appIdentifier)")

        guard let appElement = applicationElement(
            for: appIdentifier,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        ) else {
            let errorMessage = "[handleExtractText] Failed to get application element for \(appIdentifier)"
            currentDebugLogs.append(errorMessage)
            return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
        }

        var effectiveElement = appElement
        if let pathHint = pathHint, !pathHint.isEmpty {
            dLog("[handleExtractText] Navigating to element using path hint: \(pathHint.joined(separator: " -> "))")
            guard let navigatedElement = navigateToElement(
                from: appElement,
                pathHint: pathHint,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) else {
                let lastLogBeforeDebug = currentDebugLogs.last
                let errorMessage: String
                if let lastLog = lastLogBeforeDebug, lastLog.contains("CRITICAL_NAV_PARSE_FAILURE_MARKER") {
                    errorMessage = "[handleExtractText] Navigation parsing failed (critical marker found) for path hint: \(pathHint.joined(separator: " -> "))"
                } else if let lastLog = lastLogBeforeDebug, lastLog.contains("CHILD_MATCH_FAILURE_MARKER") {
                    errorMessage = "[handleExtractText] Navigation child match failed (child match marker found) for path hint: \(pathHint.joined(separator: " -> "))"
                } else {
                    errorMessage = "[handleExtractText] Failed to navigate to element using path hint: \(pathHint.joined(separator: " -> "))"
                }
                
                if isDebugLoggingEnabled {
                    if let actualLastLog = lastLogBeforeDebug {
                        dLog("[MARKER_CHECK] Checked lastLog for markers -> Error: '\(errorMessage)'. LastLog: '\(actualLastLog)'")
                    } else {
                        dLog("[MARKER_CHECK] currentDebugLogs was empty or lastLog was nil -> Error: '\(errorMessage)'")
                    }
                }
                currentDebugLogs.append(errorMessage)
                return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
            }
            effectiveElement = navigatedElement
            dLog("[handleExtractText] Successfully navigated path_hint. New effectiveElement for text extraction: \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        }

        let targetElementForExtract: Element
        if let actualLocator = locator {
            dLog("[handleExtractText] Locator provided. Searching from current effectiveElement: \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)) using locator criteria: \(actualLocator.criteria)")
            
            let searchResult = search(
                element: effectiveElement,
                locator: actualLocator,
                requireAction: nil,
                depth: 0,
                maxDepth: DEFAULT_MAX_DEPTH_SEARCH,
                isDebugLoggingEnabled: isDebugLoggingEnabled
            )
            fputs("HANDLER_RAW_STDERR_BEFORE_LOG_APPEND handleExtractText: searchResult.logs.count = \(searchResult.logs.count), currentDebugLogs count = \(currentDebugLogs.count)\n", stderr)
            currentDebugLogs.append("HANDLER_DEBUG: searchResult.logs.count = \(searchResult.logs.count) before append for extractText")
            currentDebugLogs.append(contentsOf: searchResult.logs)
            fputs("HANDLER_RAW_STDERR_AFTER_LOG_APPEND handleExtractText: currentDebugLogs count = \(currentDebugLogs.count)\n", stderr)
            currentDebugLogs.append("POST_SEARCH_LOG_APPEND_MARKER_IN_EXTRACT_TEXT")

            guard let foundElement = searchResult.foundElement else {
                let errorMessage = "[handleExtractText] Target element not found for locator: \(actualLocator) starting from \(effectiveElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))"
                if !currentDebugLogs.contains(errorMessage) {
                    currentDebugLogs.append(errorMessage)
                }
                return HandlerResponse(data: nil, error: errorMessage, debug_logs: currentDebugLogs)
            }
            targetElementForExtract = foundElement
            dLog("[handleExtractText] Found element via locator for text extraction: \(targetElementForExtract.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        } else {
            targetElementForExtract = effectiveElement
            dLog("[handleExtractText] No locator. Using effectiveElement from path_hint/app_root as target for text extraction: \(targetElementForExtract.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        }
        
        dLog("[handleExtractText] Target element found: \(targetElementForExtract.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)), attempting to extract text")
        var attributes: [String: AnyCodable] = [:]
        var extractedAnyText = false

        if let valueCF = targetElementForExtract.rawAttributeValue(named: kAXValueAttribute as String, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) {
            if CFGetTypeID(valueCF) == CFStringGetTypeID() {
                let extractedValueText = valueCF as! String
                if !extractedValueText.isEmpty {
                    attributes["extractedValue"] = AnyCodable(extractedValueText)
                    extractedAnyText = true
                    dLog("[handleExtractText] Extracted text from kAXValueAttribute (length: \(extractedValueText.count)): \(extractedValueText.prefix(80))...")
                } else {
                    dLog("[handleExtractText] kAXValueAttribute was empty or not a string.")
                }
            } else {
                dLog("[handleExtractText] kAXValueAttribute was present but not a CFString. TypeID: \(CFGetTypeID(valueCF))")
            }
        } else {
            dLog("[handleExtractText] kAXValueAttribute not found or nil.")
        }

        if let selectedValueCF = targetElementForExtract.rawAttributeValue(named: kAXSelectedTextAttribute as String, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) {
            if CFGetTypeID(selectedValueCF) == CFStringGetTypeID() {
                let extractedSelectedText = selectedValueCF as! String
                if !extractedSelectedText.isEmpty {
                    attributes["extractedSelectedText"] = AnyCodable(extractedSelectedText)
                    extractedAnyText = true
                    dLog("[handleExtractText] Extracted selected text from kAXSelectedTextAttribute (length: \(extractedSelectedText.count)): \(extractedSelectedText.prefix(80))...")
                } else {
                    dLog("[handleExtractText] kAXSelectedTextAttribute was empty or not a string.")
                }
            } else {
                dLog("[handleExtractText] kAXSelectedTextAttribute was present but not a CFString. TypeID: \(CFGetTypeID(selectedValueCF))")
            }
        } else {
            dLog("[handleExtractText] kAXSelectedTextAttribute not found or nil.")
        }
        
        if !extractedAnyText {
            dLog("[handleExtractText] No text could be extracted from kAXValue or kAXSelectedText for element.")
        }

        let pathArray = targetElementForExtract.generatePathArray(upTo: appElement, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
        let axElementToReturn = AXElement(attributes: attributes, path: pathArray) 
        return HandlerResponse(data: axElementToReturn, error: nil, debug_logs: currentDebugLogs)
    }
}

