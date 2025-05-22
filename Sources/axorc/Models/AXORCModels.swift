// AXORCModels.swift - Response models for AXORC CLI

import Foundation

// MARK: - Response Models
// These should align with structs in AXorcistIntegrationTests.swift

struct SimpleSuccessResponse: Codable {
    let success: Bool
    let message: String?
    let command_id: String?
    let debug_logs: [String]?
}

struct ErrorResponse: Codable {
    let success: Bool = false
    let error: ErrorDetail
    
    struct ErrorDetail: Codable {
        let message: String
        let command_id: String?
        let debug_logs: [String]?
    }
}

// This is a pass-through structure. AXorcist.AXElement should be Codable itself.
// If AXorcist.AXElement is not Codable, then this needs to be manually constructed.
// For now, treating AXElement as having attributes: [String: AnyCodable] which should be Codable if AnyCodable is Codable.

struct AXElementForEncoding: Codable {
    let attributes: [String: AnyCodable]
    let path: [String]?
    
    init(from axElement: AXElement) {
        self.attributes = axElement.attributes
        self.path = axElement.path
    }
}

struct QueryResponse: Codable {
    let success: Bool
    let command_id: String?
    let command: String?
    let data: AXElementForEncoding?
    let attributes: [String: AnyCodable]?
    let error: String?
    let debug_logs: [String]?
    
    // Initializer for success cases
    init(success: Bool = true, commandId: String? = nil, command: String? = nil, 
         axElement: AXElement? = nil, attributes: [String: AnyCodable]? = nil, 
         error: String? = nil, debugLogs: [String]? = nil) {
        self.success = success
        self.command_id = commandId
        self.command = command
        self.data = axElement != nil ? AXElementForEncoding(from: axElement!) : nil
        self.attributes = attributes
        self.error = error
        self.debug_logs = debugLogs
    }
}

struct BatchOperationResponse: Codable {
    let success: Bool
    let command_id: String?
    let command: String = "batch"
    let batch_results: [QueryResponse]?
    let error: String?
    let debug_logs: [String]?
    
    init(success: Bool = true, commandId: String? = nil, batchResults: [QueryResponse]? = nil, 
         error: String? = nil, debugLogs: [String]? = nil) {
        self.success = success
        self.command_id = commandId
        self.batch_results = batchResults
        self.error = error
        self.debug_logs = debugLogs
    }
}