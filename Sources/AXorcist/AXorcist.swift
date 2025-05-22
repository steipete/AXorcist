import AppKit
import ApplicationServices
import Foundation

// Global constant for backwards compatibility
public let DEFAULT_MAX_DEPTH_SEARCH = 10

// Placeholder for the actual accessibility logic.
// For now, this module is very thin and AXorcist.swift is the main public API.
// Other files like Element.swift, Models.swift, Search.swift, etc. are in Core/ Utils/ etc.

public class AXorcist {

    let focusedAppKeyValue = "focused"
    internal var recursiveCallDebugLogs: [String] = [] // Added for recursive logging

    // Default values for collection and search if not provided by the command
    public static let defaultMaxDepthSearch = 10 // Default for general locator-based searches
    public static let defaultMaxDepthCollectAll = 7 // Default for collectAll recursive operations
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
        // Future initialization logic can go here.
        // For now, ensure debug logs can be collected if needed.
        // Note: The actual logging enable/disable should be managed per-call.
        // This init doesn't take global logging flags anymore.
    }

    @MainActor
    public static func formatDebugLogMessage(
        _ message: String,
        applicationName: String?,
        commandID: String?,
        file: String,
        function: String,
        line: Int
    ) -> String {
        let fileName = (file as NSString).lastPathComponent
        let appContext = applicationName != nil ? "[\(applicationName!)]" : ""
        let cmdContext = commandID != nil ? "[SubCmd: \(commandID!)]" : ""
        return "\(appContext)\(cmdContext)[\(fileName):\(line) \(function)] \(message)"
    }

    // Handler methods are implemented in extension files:
    // - handlePerformAction: AXorcist+ActionHandlers.swift
    // - handleExtractText: AXorcist+ActionHandlers.swift
    // - handleCollectAll: AXorcist+ActionHandlers.swift
    // - handleBatchCommands: AXorcist+BatchHandler.swift

    // handleExtractText method is implemented in AXorcist+ActionHandlers.swift

    // handleBatchCommands method is implemented in AXorcist+BatchHandler.swift

    // handleCollectAll method is implemented in AXorcist+ActionHandlers.swift

    // MARK: - Path Navigation

    // Helper to check if the current element matches a specific attribute-value pair
    @MainActor
    private static func currentElementMatchesPathComponent(
        _ element: Element,
        attributeName: String,
        expectedValue: String,
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String] // For logging
    ) -> Bool {
        // Helper to log directly to currentDebugLogs for this function
        func logLocal(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
            if isDebugLoggingEnabled { // Check if logging is enabled for this specific call context
                let logMessage = AXorcist.formatDebugLogMessage(
                    message,
                    applicationName: nil, // Or pass from navigateToElement if needed
                    commandID: nil,       // Or pass from navigateToElement if needed
                    file: file,
                    function: function,
                    line: line
                )
                currentDebugLogs.append(logMessage)
            }
        }

        if attributeName.isEmpty { // Should not happen if parsePathComponent is robust
            logLocal("currentElementMatchesPathComponent: attributeName is empty, cannot match.")
            return false
        }
        if let actualValue = element.attribute(Attribute<String>(attributeName), isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) {
            // logLocal("currentElementMatchesPathComponent: Element \(element.briefDescription(option: .minimal, isDebugLoggingEnabled: false, currentDebugLogs: &currentDebugLogs)) has '\(attributeName)': [\(actualValue)] (Expected: [\(expectedValue)])")
            if actualValue == expectedValue {
                return true
            }
        }
        return false
    }

    // Updated navigateToElement to prioritize children
    @MainActor
    internal func navigateToElement(
        from startElement: Element,
        pathHint: [String],
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> Element? {
        let pathHintString = pathHint.joined(separator: ", ")
        // Log with the actual isDebugLoggingEnabled value
        currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Entered. isDebugLoggingEnabled: \(isDebugLoggingEnabled). pathHint: [\(pathHintString)]", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))

        func dLog(_ message: String, file: String = #file, function: String = #function, line: Int = #line) {
            // Use the passed-in isDebugLoggingEnabled
            if isDebugLoggingEnabled {
                currentDebugLogs.append(AXorcist.formatDebugLogMessage(message, applicationName: nil, commandID: nil, file: file, function: function, line: line))
            }
        }

        var currentElement = startElement
        var currentPathSegmentForLog = ""

        for (index, pathComponentString) in pathHint.enumerated() {
            currentPathSegmentForLog += (index > 0 ? " -> " : "") + pathComponentString
            let briefDesc = currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
            dLog("Navigating: Processing path component '\(pathComponentString)' from current element: \(briefDesc)")

            let (attributeName, expectedValue) = PathUtils.parsePathComponent(pathComponentString)
            guard !attributeName.isEmpty else {
                dLog("CRITICAL_NAV_PARSE_FAILURE_MARKER: Empty attribute name from pathComponentString '\(pathComponentString)'")
                return nil
            }

            var foundMatchForThisComponent = false
            var newElementForNextStep: Element? = nil

            // Priority 1: Check children using Element.children()
            if let childrenFromElementDotChildren = currentElement.children(isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) {
                dLog("Child count from Element.children(): \(childrenFromElementDotChildren.count)")
                for child in childrenFromElementDotChildren {
                    let childBriefDescForLog = child.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
                    if let actualValue = child.attribute(Attribute<String>(attributeName), isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) {
                        dLog("  [Nav Child Check 1] Child: \(childBriefDescForLog), Attribute '\(attributeName)': [\(actualValue)] (Expected: [\(expectedValue)])")
                        if actualValue == expectedValue {
                            dLog("Matched child (from Element.children): \(childBriefDescForLog) for '\(attributeName):\(expectedValue)'")
                            newElementForNextStep = child
                            foundMatchForThisComponent = true
                            break
                        }
                    } else {
                        // dLog("Attribute '\(attributeName)' was nil for child (from Element.children): \(childBriefDescForLog)")
                    }
                }
            } else {
                dLog("Current element \(briefDesc) has no children from Element.children() or children array was nil.")
            }

            // FALLBACK: If no child matched via Element.children(), try direct kAXChildrenAttribute call (Heisenbug workaround)
            if !foundMatchForThisComponent {
                // Log entry for this fallback block, without using currentElement.briefDescription() before the critical call.
                currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: No match from Element.children(). Trying direct kAXChildrenAttribute fallback.", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                
                var directChildrenValue: CFTypeRef?
                let directChildrenError = AXUIElementCopyAttributeValue(currentElement.underlyingElement, kAXChildrenAttribute as CFString, &directChildrenValue)

                // Now, after the critical call, we can get the description for logging.
                let currentElementDescForFallbackLog = isDebugLoggingEnabled ? currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) : "Element(debug_off)"
                currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Fallback is for element: \(currentElementDescForFallbackLog)", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))

                if directChildrenError == .success, let cfArray = directChildrenValue, CFGetTypeID(cfArray) == CFArrayGetTypeID() {
                    if let directAxElements = cfArray as? [AXUIElement] {
                        currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Direct kAXChildrenAttribute fallback found \(directAxElements.count) raw children for \(currentElementDescForFallbackLog).", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                        for axChild in directAxElements {
                            let childElement = Element(axChild)
                            let childBriefDescForLogFallback = childElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs)
                            if let actualValue = childElement.attribute(Attribute<String>(attributeName), isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs) {
                                dLog("  [Nav Child Check 2-Fallback] Child: \(childBriefDescForLogFallback), Attribute '\(attributeName)': [\(actualValue)] (Expected: [\(expectedValue)])")
                                if actualValue == expectedValue {
                                    currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Matched child (from direct fallback) for '\(attributeName):\(expectedValue)' on \(currentElementDescForFallbackLog). Child: \(childElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                                    newElementForNextStep = childElement
                                    foundMatchForThisComponent = true
                                    break
                                }
                            }
                        }
                    } else {
                        currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Direct kAXChildrenAttribute fallback: CFArray failed to cast to [AXUIElement] for \(currentElementDescForFallbackLog).", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                    }
                } else if directChildrenError != .success {
                     currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Direct kAXChildrenAttribute fallback: Error fetching for \(currentElementDescForFallbackLog): \(directChildrenError.rawValue)", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                } else {
                    currentDebugLogs.append(AXorcist.formatDebugLogMessage("navigateToElement: Direct kAXChildrenAttribute fallback: No children or not an array for \(currentElementDescForFallbackLog).", applicationName: nil, commandID: nil, file: #file, function: #function, line: #line))
                }
            }

            // Priority 2: If no child matched (even after fallback), check current element itself
            if !foundMatchForThisComponent {
                var tempLogsForMatchCheck = currentDebugLogs
                let matchResult = AXorcist.currentElementMatchesPathComponent(
                    currentElement,
                    attributeName: attributeName,
                    expectedValue: expectedValue,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &tempLogsForMatchCheck
                )
                currentDebugLogs = tempLogsForMatchCheck

                if matchResult {
                    dLog("Current element \(briefDesc) itself matches '\(attributeName):\(expectedValue)'. Retaining current element for this step.")
                    newElementForNextStep = currentElement
                    foundMatchForThisComponent = true
                }
            }
            
            if foundMatchForThisComponent, let nextElement = newElementForNextStep {
                currentElement = nextElement
            } else {
                dLog("Neither current element \(briefDesc) nor its children (after all checks) matched '\(attributeName):\(expectedValue)'. Path: \(currentPathSegmentForLog) // CHILD_MATCH_FAILURE_MARKER")
                return nil
            }
        }

        dLog("Navigation successful. Final element: \(currentElement.briefDescription(option: .default, isDebugLoggingEnabled: isDebugLoggingEnabled, currentDebugLogs: &currentDebugLogs))")
        return currentElement
    }
}
