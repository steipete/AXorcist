// CommandModels.swift - Contains command-related model structs

import CoreGraphics // For CGPoint
import Foundation

// Main command envelope - REPLACED with definition from axorc.swift for consistency
public struct CommandEnvelope: Codable {
    public let commandId: String
    public let command: CommandType // Uses CommandType from this file
    public let application: String?
    public let attributes: [String]?
    public let payload: [String: String]? // For ping compatibility
    public let debugLogging: Bool?
    public let locator: Locator? // Locator from this file
    public let pathHint: [String]?
    public let maxElements: Int?
    public let maxDepth: Int?
    public let outputFormat: OutputFormat? // OutputFormat from this file
    public let actionName: String? // For performAction
    public let actionValue: AnyCodable? // For performAction (AnyCodable from this file)
    public let subCommands: [CommandEnvelope]? // For batch command
    public let point: CGPoint? // Added for getElementAtPoint
    public let pid: Int? // Added for getElementAtPoint (optional specific PID)

    // Parameters for 'observe' command
    public let notifications: [String]?
    public let includeElementDetails: [String]?
    public let watchChildren: Bool?

    enum CodingKeys: String, CodingKey {
        case commandId
        case command
        case application
        case attributes
        case payload
        case debugLogging
        case locator
        case pathHint
        case maxElements
        case maxDepth
        case outputFormat
        case actionName
        case actionValue
        case subCommands
        case point
        case pid
        // CodingKeys for observe parameters
        case notifications
        case includeElementDetails
        case watchChildren
    }

    // Added a public initializer for convenience, matching fields.
    public init(commandId: String,
                command: CommandType,
                application: String? = nil,
                attributes: [String]? = nil,
                payload: [String: String]? = nil,
                debugLogging: Bool? = nil,
                locator: Locator? = nil,
                pathHint: [String]? = nil,
                maxElements: Int? = nil,
                maxDepth: Int? = nil,
                outputFormat: OutputFormat? = nil,
                actionName: String? = nil,
                actionValue: AnyCodable? = nil,
                subCommands: [CommandEnvelope]? = nil,
                point: CGPoint? = nil,
                pid: Int? = nil,
                // Init parameters for observe
                notifications: [String]? = nil,
                includeElementDetails: [String]? = nil,
                watchChildren: Bool? = nil
    ) {
        self.commandId = commandId
        self.command = command
        self.application = application
        self.attributes = attributes
        self.payload = payload
        self.debugLogging = debugLogging
        self.locator = locator
        self.pathHint = pathHint
        self.maxElements = maxElements
        self.maxDepth = maxDepth
        self.outputFormat = outputFormat
        self.actionName = actionName
        self.actionValue = actionValue
        self.subCommands = subCommands
        self.point = point
        self.pid = pid
        // Assignments for observe parameters
        self.notifications = notifications
        self.includeElementDetails = includeElementDetails
        self.watchChildren = watchChildren
    }
}

// Locator for finding elements
public struct Locator: Codable {
    public var matchAll: Bool?
    public var criteria: [String: String]
    public var rootElementPathHint: [String]?
    public var requireAction: String?
    public var computedNameContains: String?

    enum CodingKeys: String, CodingKey {
        case matchAll
        case criteria
        case rootElementPathHint
        case requireAction
        case computedNameContains
    }

    public init(
        matchAll: Bool? = nil,
        criteria: [String: String] = [:],
        rootElementPathHint: [String]? = nil,
        requireAction: String? = nil,
        computedNameContains: String? = nil
    ) {
        self.matchAll = matchAll
        self.criteria = criteria
        self.rootElementPathHint = rootElementPathHint
        self.requireAction = requireAction
        self.computedNameContains = computedNameContains
    }
}
