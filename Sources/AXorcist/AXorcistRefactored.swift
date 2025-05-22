// AXorcist.swift - Core AXorcist class definition

import AppKit
import ApplicationServices
import Foundation

public class AXorcist {
    
    let focusedAppKeyValue = "focused"
    private var recursiveCallDebugLogs: [String] = [] // Added for recursive logging

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
}

// All handler methods are now implemented in separate extension files:
// - AXorcist+QueryHandlers.swift (handleQuery, handleGetAttributes, handleDescribeElement, handleGetFocusedElement)
// - AXorcist+ActionHandlers.swift (handlePerformAction, handleExtractText, handleCollectAll)
// - AXorcist+BatchHandler.swift (handleBatchCommands)