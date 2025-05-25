// ModelEnums.swift - Contains enum definitions for the AXorcist models

import Foundation

// Enum for output formatting options
public enum OutputFormat: String, Codable {
    case smart // Default, tries to be concise and informative
    case verbose // More detailed output, includes more attributes/info
    case textContent // Primarily extracts textual content
    case jsonString // Returns the attributes as a JSON string (new)
}

// Define CommandType enum
public enum CommandType: String, Codable {
    case query
    case performAction
    case getAttributes
    case batch
    case describeElement
    case getFocusedElement
    case collectAll
    case extractText
    case ping
    case getElementAtPoint
    case observe
    case setFocusedValue // New: sets a value on the currently focused element
    // Add future commands here, ensuring case matches JSON or provide explicit raw value
}
