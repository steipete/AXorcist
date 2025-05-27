// ResponseModels.swift - Contains response model structs for AXorcist commands

import Foundation

// MARK: - AXErrorCode

// Error codes for AXorcist operations
public enum AXErrorCode: String, Codable, Sendable {
    case elementNotFound = "element_not_found"
    case actionFailed = "action_failed"
    case attributeNotFound = "attribute_not_found"
    case invalidCommand = "invalid_command"
    case unknownCommand = "unknown_command"
    case internalError = "internal_error"
    case permissionDenied = "permission_denied"
    case invalidParameter = "invalid_parameter"
    case timeout = "timeout"
    case observationFailed = "observation_failed"
    case applicationNotFound = "application_not_found"
    case batchOperationFailed = "batch_operation_failed"
    case actionNotSupported = "action_not_supported"
}

// MARK: - AXResponse

// Main response enum for AXorcist operations
public enum AXResponse: Sendable {
    case success(payload: AnyCodable?, logs: [String]?)
    case error(message: String, code: AXErrorCode, logs: [String]?)

    // Computed property for status
    public var status: String {
        switch self {
        case .success: return "success"
        case .error: return "error"
        }
    }

    // Computed property for payload
    public var payload: AnyCodable? {
        switch self {
        case .success(let payload, _): return payload
        case .error: return nil
        }
    }

    // Computed property for error
    public var error: (message: String, code: AXErrorCode)? {
        switch self {
        case .success: return nil
        case .error(let message, let code, _): return (message, code)
        }
    }

    // Computed property for logs
    public var logs: [String]? {
        switch self {
        case .success(_, let logs): return logs
        case .error(_, _, let logs): return logs
        }
    }

    // Static factory methods
    public static func successResponse(payload: AnyCodable?, logs: [String]? = nil) -> AXResponse {
        return .success(payload: payload, logs: logs)
    }

    public static func errorResponse(message: String, code: AXErrorCode, logs: [String]? = nil) -> AXResponse {
        return .error(message: message, code: code, logs: logs)
    }
}

// New protocol for generic data in HandlerResponse
public protocol HandlerDataRepresentable: Codable {}

// Definition for AXElementData based on usage in AXorcist+QueryHandlers.swift
public struct AXElementData: Codable, HandlerDataRepresentable {
    public var briefDescription: String?
    public var role: String?
    public var attributes: [String: AXValueWrapper]? // Assuming AXValueWrapper is Codable
    public var allPossibleAttributes: [String]?
    public var textualContent: String?
    public var childrenBriefDescriptions: [String]?
    public var fullAXDescription: String?
    // Add path here as it's often part of element data
    public var path: [String]?

    public init(
        briefDescription: String? = nil,
        role: String? = nil,
        attributes: [String: AXValueWrapper]? = nil,
        allPossibleAttributes: [String]? = nil,
        textualContent: String? = nil,
        childrenBriefDescriptions: [String]? = nil,
        fullAXDescription: String? = nil,
        path: [String]? = nil
    ) {
        self.briefDescription = briefDescription
        self.role = role
        self.attributes = attributes
        self.allPossibleAttributes = allPossibleAttributes
        self.textualContent = textualContent
        self.childrenBriefDescriptions = childrenBriefDescriptions
        self.fullAXDescription = fullAXDescription
        self.path = path
    }
}

// Make existing relevant models conform
// AXElement is defined in DataModels.swift, so we'll make it conform there later.
// For now, assume it will.

// Response for query command (single element)
public struct QueryResponse: Codable {
    public var commandId: String
    public var success: Bool
    public var command: String
    public var data: AXElement?
    public var attributes: ElementAttributes?
    public var error: String?
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId
        case success
        case command
        case data
        case attributes
        case error
        case debugLogs
    }

    public init(
        commandId: String,
        success: Bool = true,
        command: String = "getFocusedElement",
        data: AXElement? = nil,
        attributes: ElementAttributes? = nil,
        error: String? = nil,
        debugLogs: [String]? = nil
    ) {
        self.commandId = commandId
        self.success = success
        self.command = command
        self.data = data
        self.attributes = attributes
        self.error = error
        self.debugLogs = debugLogs
    }

    // Custom init for HandlerResponse integration
    public init(
        commandId: String,
        success: Bool,
        command: String,
        handlerResponse: HandlerResponse,
        debugLogs: [String]?
    ) {
        self.commandId = commandId
        self.success = success
        self.command = command
        // Extract AXElement from AnyCodable if present
        if let anyCodableData = handlerResponse.data,
           let axElement = anyCodableData.value as? AXElement {
            self.data = axElement
            self.attributes = axElement.attributes
        } else {
            self.data = nil
            self.attributes = nil
        }
        self.error = handlerResponse.error
        self.debugLogs = debugLogs
    }
}

// Extension to add JSON encoding functionality to QueryResponse
extension QueryResponse {
    public func jsonString() throws -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let data = try encoder.encode(self)
        return String(data: data, encoding: .utf8) ?? ""
    }
}

// Response for collect_all command (multiple elements)
public struct MultiQueryResponse: Codable {
    public var commandId: String
    public var elements: [ElementAttributes]?
    public var count: Int?
    public var error: String?
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId
        case elements
        case count
        case error
        case debugLogs
    }

    public init(
        commandId: String,
        elements: [ElementAttributes]? = nil,
        count: Int? = nil,
        error: String? = nil,
        debugLogs: [String]? = nil
    ) {
        self.commandId = commandId
        self.elements = elements
        self.count = count ?? elements?.count
        self.error = error
        self.debugLogs = debugLogs
    }
}

// Response for perform_action command
public struct PerformResponse: Codable, HandlerDataRepresentable {
    public var commandId: String
    public var success: Bool
    public var error: String?
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId
        case success
        case error
        case debugLogs
    }

    public init(commandId: String, success: Bool, error: String? = nil, debugLogs: [String]? = nil) {
        self.commandId = commandId
        self.success = success
        self.error = error
        self.debugLogs = debugLogs
    }
}

// New response for extract_text command
public struct TextExtractionResponse: Codable, HandlerDataRepresentable {
    public var textContent: String?
    // commandId, error, debugLogs can be part of the HandlerResponse envelope

    enum CodingKeys: String, CodingKey {
        case textContent
    }

    public init(textContent: String?) {
        self.textContent = textContent
    }
}

// Response for extract_text command - THIS OLD ONE CAN BE REMOVED or kept if used elsewhere
// For now, commenting out, replaced by TextExtractionResponse for HandlerResponse.data
/*
 public struct TextContentResponse: Codable {
 public var command_id: String
 public var text_content: String?
 public var error: String?
 public var debug_logs: [String]?

 public init(command_id: String, text_content: String? = nil, error: String? = nil, debug_logs: [String]? = nil) {
 self.command_id = command_id
 self.text_content = text_content
 self.error = error
 self.debug_logs = debug_logs
 }
 }
 */

// Generic error response
public struct ErrorResponse: Codable {
    public var commandId: String
    public var success: Bool
    public var error: ErrorDetail
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId
        case success
        case error
        case debugLogs
    }

    public init(commandId: String, error: String, debugLogs: [String]? = nil) {
        self.commandId = commandId
        self.success = false
        self.error = ErrorDetail(message: error)
        self.debugLogs = debugLogs
    }
}

public struct ErrorDetail: Codable {
    public var message: String

    public init(message: String) {
        self.message = message
    }
}

// Simple success response, e.g. for ping
public struct SimpleSuccessResponse: Codable, Equatable {
    public var commandId: String
    public var success: Bool
    public var status: String
    public var message: String
    public var details: String?
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId
        case success
        case status
        case message
        case details
        case debugLogs
    }

    public init(commandId: String,
                status: String,
                message: String,
                details: String? = nil,
                debugLogs: [String]? = nil) {
        self.commandId = commandId
        self.success = true
        self.status = status
        self.message = message
        self.details = details
        self.debugLogs = debugLogs
    }
}

// HandlerResponse is now defined in Models/HandlerResponse.swift

public struct BatchResponse: Codable {
    public var commandId: String
    public var success: Bool
    public var results: [HandlerResponse] // Array of HandlerResponses for each sub-command
    public var error: String? // For an overall batch error, if any
    public var debugLogs: [String]?

    enum CodingKeys: String, CodingKey {
        case commandId
        case success
        case results
        case error
        case debugLogs
    }

    public init(
        commandId: String,
        success: Bool,
        results: [HandlerResponse],
        error: String? = nil,
        debugLogs: [String]? = nil
    ) {
        self.commandId = commandId
        self.success = success
        self.results = results
        self.error = error
        self.debugLogs = debugLogs
    }
}

// MARK: - Additional Payload Structs

// NoFocusPayload for when no focused element is found
public struct NoFocusPayload: Codable, HandlerDataRepresentable {
    public let message: String

    public init(message: String) {
        self.message = message
    }
}

// TextPayload for text extraction
public struct TextPayload: Codable, HandlerDataRepresentable {
    public let text: String

    public init(text: String) {
        self.text = text
    }
}

// BatchResponsePayload for batch operations
public struct BatchResponsePayload: Codable, HandlerDataRepresentable {
    public let results: [AnyCodable?]?
    public let errors: [String]?

    public init(results: [AnyCodable?]?, errors: [String]?) {
        self.results = results
        self.errors = errors
    }
}

// MARK: - AXElementDescription

// Structure for element tree descriptions
public struct AXElementDescription: Codable, Sendable {
    public let briefDescription: String?
    public let role: String?
    public let attributes: [String: AXValueWrapper]?
    public let children: [AXElementDescription]?

    public init(
        briefDescription: String?,
        role: String?,
        attributes: [String: AXValueWrapper]?,
        children: [AXElementDescription]? = nil
    ) {
        self.briefDescription = briefDescription
        self.role = role
        self.attributes = attributes
        self.children = children
    }
}

// Structure for custom JSON output of handleCollectAll
public struct CollectAllOutput: Codable {
    public let commandId: String
    public let success: Bool
    public let command: String // e.g., "collectAll"
    public let collectedElements: [AXElementData]? // MODIFIED: Made optional
    public let appIdentifier: String? // MODIFIED: Renamed from appBundleId
    public var debugLogs: [String]?
    public let message: String? // MODIFIED: Renamed from errorMessage

    enum CodingKeys: String, CodingKey {
        case commandId = "command_id"
        case success
        case command
        case collectedElements = "collected_elements"
        case appIdentifier = "app_identifier" // MODIFIED: CodingKey updated
        case debugLogs = "debug_logs"
        case message = "message" // MODIFIED: CodingKey updated
    }

    // Add a new initializer or ensure the existing one matches these fields.
    // Assuming the default memberwise initializer will now work with these changes,
    // or one will be synthesized. If a custom one exists, it will need updating.
    // For safety, let's add one that matches the typical usage pattern.
    public init(commandId: String,
                success: Bool,
                command: String,
                collectedElements: [AXElementData]?,
                appIdentifier: String?,
                debugLogs: [String]?,
                message: String?) {
        self.commandId = commandId
        self.success = success
        self.command = command
        self.collectedElements = collectedElements
        self.appIdentifier = appIdentifier
        self.debugLogs = debugLogs
        self.message = message
    }
}
