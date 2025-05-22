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
    public static let defaultMaxDepthSearch = 10 // Example, adjust as needed
    public static let defaultMaxDepthCollectAll = 5
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

    @MainActor
    internal func navigateToElement(
        from startElement: Element,
        pathHint: [String],
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> Element? {
        // let navigationDebugEnabled = isDebugLoggingEnabled // Create local constant // REMOVE THIS

        // VERY EARLY DEBUG LOG
        let pathHintString = pathHint.joined(separator: ", ") // Pre-calculate
        let earlyLogMsg = AXorcist.formatDebugLogMessage(
            "navigateToElement: Entered. isDebugLoggingEnabled: \\(isDebugLoggingEnabled). pathHint: [\\(pathHintString)]", // Use pre-calculated string
            applicationName: nil, commandID: nil, file: #file, function: #function, line: #line
        )
        currentDebugLogs.append(earlyLogMsg)

        func dLog(_ message: String) { // Removed isLoggingActive parameter
            let logMessage = AXorcist.formatDebugLogMessage(
                message,
                applicationName: nil, 
                commandID: nil, 
                file: #file,
                function: #function,
                line: #line
            )
            currentDebugLogs.append(logMessage) 
        }

        var currentElement = startElement
        var currentPathSegmentForLog = ""

        for (index, pathComponentString) in pathHint.enumerated() {
            currentPathSegmentForLog += (index > 0 ? " -> " : "") + pathComponentString
            let briefDesc = currentElement.briefDescription(
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            dLog("Navigating: Processing path component '\(pathComponentString)' from current element: \(briefDesc)")

            let trimmedPathComponentString = pathComponentString.trimmingCharacters(in: .whitespacesAndNewlines)
            dLog("Trimmed path component string: '\(trimmedPathComponentString)' (Count: \(trimmedPathComponentString.count))")
            let parts = trimmedPathComponentString.split(separator: ":", maxSplits: 1)
            dLog("Split parts: \(parts) (Count: \(parts.count))")

            guard parts.count == 2 else {
                currentDebugLogs.append("CRITICAL_NAV_PARSE_FAILURE_MARKER")
                return nil
            }

            let attributeName = String(parts[0])
            let expectedValue = String(parts[1])

            var foundMatchForPathComponent = false

            // Check current element first
            if let actualValueOnCurrent = currentElement.attribute(
                Attribute<String>(attributeName),
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            ) {
                if actualValueOnCurrent == expectedValue {
                    let briefDesc = currentElement.briefDescription(
                        option: .default,
                        isDebugLoggingEnabled: isDebugLoggingEnabled,
                        currentDebugLogs: &currentDebugLogs
                    )
                    dLog("Current element \(briefDesc) matches path component '\(attributeName):\(expectedValue)'.")
                    foundMatchForPathComponent = true
                    // No change to currentElement, this component is satisfied.
                }
            }

            // If current element didn't match, search children
            if !foundMatchForPathComponent {
                // Attempt to get children. If this element has no children, it can't match a path component.
                // Note: children() can be expensive.
                let children = currentElement.children(
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
                
                dLog("Child count: \(children?.count ?? 0)")

                // Search children for the matching attribute and value
                for child in children ?? [] {
                    if let actualValue = child.attribute(
                        Attribute<String>(attributeName),
                        isDebugLoggingEnabled: isDebugLoggingEnabled,
                        currentDebugLogs: &currentDebugLogs
                    ) {
                        if actualValue == expectedValue {
                            let childDesc = child.briefDescription(
                                option: .default,
                                isDebugLoggingEnabled: isDebugLoggingEnabled,
                                currentDebugLogs: &currentDebugLogs
                            )
                            let matchMsg = "Matched child: \(childDesc) for '\(attributeName):\(expectedValue)'"
                            dLog(matchMsg)
                            currentElement = child
                            foundMatchForPathComponent = true
                            break // Found match for this path component, move to next in pathHint
                        }
                    }
                }
            }

            if !foundMatchForPathComponent {
                // All descriptive logging happens FIRST
                let briefDesc = currentElement.briefDescription(
                    option: .default,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
                let noMatchMsg = "Neither current element \(briefDesc) nor its children matched '\(attributeName):\(expectedValue)'. Path: \(currentPathSegmentForLog)"
                dLog(noMatchMsg)
                // THEN, the marker is the LAST log entry
                currentDebugLogs.append("CHILD_MATCH_FAILURE_MARKER")
                return nil // No match found for this path component, navigation fails
            }
        }
        // If the loop completes, all path components were matched
        let finalDesc = currentElement.briefDescription(
            option: .default,
            isDebugLoggingEnabled: isDebugLoggingEnabled,
            currentDebugLogs: &currentDebugLogs
        )
        dLog("Navigation successful. Final element: \(finalDesc)")
        return currentElement
    }
}
