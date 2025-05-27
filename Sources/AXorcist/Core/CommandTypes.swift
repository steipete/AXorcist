// CommandTypes.swift - Command type definitions

import Foundation

public enum CommandType: String, Codable, Sendable {
    case ping
    case query
    case getAttributes
    case describeElement
    case getElementAtPoint
    case getFocusedElement
    case performAction
    case batch
    case observe
    case collectAll
    case stopObservation
    case isProcessTrusted
    case isAXFeatureEnabled
    case setFocusedValue // Added from error
    case extractText // Added from error
    case setNotificationHandler // For AXObserver
    case removeNotificationHandler // For AXObserver
    case getElementDescription // Utility command for full description
}

public enum OutputFormat: String, Codable, Sendable {
    case json
    case verbose
    case smart // Default, tries to be concise and informative
    case jsonString // JSON output as a string, often for AXpector.
    case textContent // Specifically for text content output, might ignore non-textual parts.
}
