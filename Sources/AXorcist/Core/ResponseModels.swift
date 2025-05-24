// ResponseModels.swift - Contains response model structs for AXorcist commands

import Foundation

// New protocol for generic data in HandlerResponse
public protocol HandlerDataRepresentable: Codable {}

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

// Structure for custom JSON output of handleCollectAll
public struct CollectAllOutput: Codable {
    public let commandId: String
    public let success: Bool
    public let command: String
    public let collectedElements: [AXElement]
    public let appBundleId: String?
    public let debugLogs: [String]?
    public let errorMessage: String?

    enum CodingKeys: String, CodingKey {
        case commandId
        case success
        case command
        case collectedElements
        case appBundleId
        case debugLogs
        case errorMessage
    }
}
