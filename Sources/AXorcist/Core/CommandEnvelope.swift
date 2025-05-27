// CommandEnvelope.swift - Main command envelope structure

import CoreGraphics // For CGPoint
import Foundation

// Main command envelope - REPLACED with definition from axorc.swift for consistency
public struct CommandEnvelope: Codable {
    public let commandId: String
    public let command: CommandType // Uses CommandType from this file
    public let application: String?
    public let attributes: [String]?
    public let payload: [String: String]? // For ping compatibility
    public let debugLogging: Bool
    public let locator: Locator? // Locator from this file
    public let pathHint: [String]? // This is likely legacy, Locator.rootElementPathHint is preferred
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

    // New field for collectAll filtering
    public let filterCriteria: [String: String]?

    // Additional fields for various commands
    public let includeChildrenBrief: Bool?
    public let includeChildrenInText: Bool?
    public let includeIgnoredElements: Bool?

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
        // CodingKey for new field
        case filterCriteria
        // Additional CodingKeys
        case includeChildrenBrief
        case includeChildrenInText
        case includeIgnoredElements
    }

    public init(commandId: String,
                command: CommandType,
                application: String? = nil,
                attributes: [String]? = nil,
                payload: [String: String]? = nil,
                debugLogging: Bool = false,
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
                notifications: [String]? = nil,
                includeElementDetails: [String]? = nil,
                watchChildren: Bool? = nil,
                filterCriteria: [String: String]? = nil,
                includeChildrenBrief: Bool? = nil,
                includeChildrenInText: Bool? = nil,
                includeIgnoredElements: Bool? = nil
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
        self.notifications = notifications
        self.includeElementDetails = includeElementDetails
        self.watchChildren = watchChildren
        self.filterCriteria = filterCriteria
        self.includeChildrenBrief = includeChildrenBrief
        self.includeChildrenInText = includeChildrenInText
        self.includeIgnoredElements = includeIgnoredElements
    }
}
