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
    private func navigateToElement(
        from startElement: Element,
        pathHint: [String],
        isDebugLoggingEnabled: Bool,
        currentDebugLogs: inout [String]
    ) -> Element? {
        func dLog(_ message: String) {
            if isDebugLoggingEnabled {
                let logMessage = AXorcist.formatDebugLogMessage(
                    message,
                    applicationName: nil, // App name not available for low-level navigation
                    commandID: nil, // No specific command ID for this utility
                    file: #file,
                    function: #function,
                    line: #line
                )
                currentDebugLogs.append(logMessage)
            }
        }

        var currentElement = startElement
        var currentPathSegmentForLog = ""

        for (index, pathComponentString) in pathHint.enumerated() {
            currentPathSegmentForLog += (index > 0 ? " -> " : "") + pathComponentString
            let currentDesc = currentElement.briefDescription(
                option: .default,
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            dLog("Navigating: Processing path component '\(pathComponentString)' from current element: \(currentDesc)")

            let trimmedPathComponentString = pathComponentString.trimmingCharacters(in: .whitespacesAndNewlines)
            let parts = trimmedPathComponentString.split(separator: ":", maxSplits: 1)
            guard parts.count == 2 else {
                let parseFailMsg = "Failed to parse path component: '\(pathComponentString)' " +
                    "(trimmed: '\(trimmedPathComponentString)'). " +
                    "Expected 'Attribute:Value'. Path traversed so far: \(currentPathSegmentForLog)"
                dLog(parseFailMsg)
                return nil
            }

            let attributeName = String(parts[0])
            let expectedValue = String(parts[1])

            // Attempt to get children. If this element has no children, it can't match a path component.
            // Note: children() can be expensive.
            let children = currentElement.children(
                isDebugLoggingEnabled: isDebugLoggingEnabled,
                currentDebugLogs: &currentDebugLogs
            )
            if (children?.isEmpty ?? true) && !pathHint.isEmpty {
                let currentDesc = currentElement.briefDescription(
                    option: .default,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
                let errorMsg = "Element \(currentDesc) has no children, " +
                    "cannot match path component '\(attributeName):\(expectedValue)'. " +
                    "Path traversed so far: \(currentPathSegmentForLog)"
                dLog(errorMsg)
                return nil
            }

            var foundMatchForPathComponent = false
            // First, check if the currentElement itself matches the component if this is the first component and we haven't advanced.
            // This handles cases where the pathHint starts with an attribute of the startElement itself.
            // More robust logic might be needed if path hints can be self-referential at any point.
            // For now, this check is primarily for the very first part of a path hint.
            // It's disabled for now as the primary logic is to search children.
            // A more refined approach would be to check currentElement *if* it's the first path component
            // *or* if the component explicitly targets the current level (e.g. special syntax).

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

            if !foundMatchForPathComponent {
                let currentDesc = currentElement.briefDescription(
                    option: .default,
                    isDebugLoggingEnabled: isDebugLoggingEnabled,
                    currentDebugLogs: &currentDebugLogs
                )
                let noMatchMsg = "No child matched '\(attributeName):\(expectedValue)' under element \(currentDesc). " +
                    "Path traversed so far: \(currentPathSegmentForLog)"
                dLog(noMatchMsg)
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
