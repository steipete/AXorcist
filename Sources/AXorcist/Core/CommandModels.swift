// CommandModels.swift - Contains command-related model structs

import CoreGraphics // For CGPoint
import Foundation

// Enum for specifying how values, especially for descriptions, should be formatted.
public enum ValueFormatOption: String, Codable, Sendable {
    case smart      // Tries to provide the most useful, possibly summarized, representation.
    case raw        // Provides the raw or complete value, potentially verbose.
    case textContent // Specifically for text content extraction, might ignore non-textual parts.
    case stringified // For detailed string representation, often for logging or debugging.
}

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

// Represents a single criterion for element matching
public struct Criterion: Codable, Sendable {
    public let attribute: String
    public let value: String
    public let match_type: JSONPathHintComponent.MatchType? // Retained for flexibility if needed directly in Criterion
    public let matchType: JSONPathHintComponent.MatchType? // Preferred name, aliased in custom init/codingkeys if needed

    // To handle decoding from either "match_type" or "matchType"
    enum CodingKeys: String, CodingKey {
        case attribute, value
        case match_type // for decoding json
        case matchType // for swift code
    }
    
    public init(attribute: String, value: String, matchType: JSONPathHintComponent.MatchType? = nil) {
        self.attribute = attribute
        self.value = value
        self.match_type = matchType // Set both to ensure consistency during encoding if old key is used
        self.matchType = matchType
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        attribute = try container.decode(String.self, forKey: .attribute)
        value = try container.decode(String.self, forKey: .value)
        // Try decoding 'matchType' first, then fall back to 'match_type'
        if let mt = try container.decodeIfPresent(JSONPathHintComponent.MatchType.self, forKey: .matchType) {
            matchType = mt
            match_type = mt
        } else if let mtOld = try container.decodeIfPresent(JSONPathHintComponent.MatchType.self, forKey: .match_type) {
            matchType = mtOld
            match_type = mtOld
        } else {
            matchType = nil
            match_type = nil
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(attribute, forKey: .attribute)
        try container.encode(value, forKey: .value)
        // Encode using the preferred 'matchType' key
        try container.encodeIfPresent(matchType, forKey: .matchType)
    }
}

/// Represents a step in a hierarchical path, defined by a set of criteria.
public struct PathStep: Codable, Sendable {
    public let criteria: [Criterion]
    public let matchType: JSONPathHintComponent.MatchType? // How to evaluate criteria (e.g., exact, contains)
    public let matchAllCriteria: Bool? // Whether all criteria must match (AND) or any (OR)
    public let maxDepthForStep: Int? // Maximum depth to search for this specific step

    // CodingKeys to map JSON keys to Swift properties
    enum CodingKeys: String, CodingKey {
        case criteria
        case matchType
        case matchAllCriteria
        case maxDepthForStep = "max_depth_for_step" // Map JSON's snake_case to Swift's camelCase
    }

    // Default initializer
    public init(criteria: [Criterion], 
                matchType: JSONPathHintComponent.MatchType? = .exact, 
                matchAllCriteria: Bool? = true,
                maxDepthForStep: Int? = nil) { // Added maxDepthForStep
        self.criteria = criteria
        self.matchType = matchType
        self.matchAllCriteria = matchAllCriteria
        self.maxDepthForStep = maxDepthForStep // Initialize
    }
    
    /// Returns a string representation suitable for logging
    public func descriptionForLog() -> String {
        let critDesc = criteria.map { criterion -> String in
            "\(criterion.attribute):\(criterion.value)(\((criterion.matchType ?? .exact).rawValue))"
        }.joined(separator: ", ")
        
        let depthStringPart: String
        if let depth = maxDepthForStep {
            depthStringPart = ", Depth: \(depth)"
        } else {
            depthStringPart = ""
        }
        
        let matchTypeStringPart = (matchType ?? .exact).rawValue
        let matchAllStringPart = "\(matchAllCriteria ?? true)"

        return "[Criteria: (\(critDesc)), MatchType: \(matchTypeStringPart), MatchAll: \(matchAllStringPart)\(depthStringPart)]"
    }
}

// Locator for finding elements
public struct Locator: Codable, Sendable { 
    public var matchAll: Bool? // For the top-level criteria, if path_from_root is not used or fails early.
    public var criteria: [Criterion]
    public var rootElementPathHint: [JSONPathHintComponent]? // Changed from [PathStep]?
    public var descendantCriteria: [String: String]? // This seems to be an older/alternative way? Consider phasing out or clarifying.
    public var requireAction: String?
    public var computedNameContains: String?
    public var debugPathSearch: Bool?

    enum CodingKeys: String, CodingKey {
        case matchAll
        case criteria
        case rootElementPathHint = "path_from_root" // Map to JSON key "path_from_root"
        case descendantCriteria
        case requireAction
        case computedNameContains
        case debugPathSearch
    }

    public init(
        matchAll: Bool? = true, // Default to true for criteria
        criteria: [Criterion] = [],
        rootElementPathHint: [JSONPathHintComponent]? = nil, // Changed from [PathStep]?
        descendantCriteria: [String: String]? = nil,
        requireAction: String? = nil,
        computedNameContains: String? = nil,
        debugPathSearch: Bool? = false
    ) {
        self.matchAll = matchAll
        self.criteria = criteria
        self.rootElementPathHint = rootElementPathHint
        self.descendantCriteria = descendantCriteria
        self.requireAction = requireAction
        self.computedNameContains = computedNameContains
        self.debugPathSearch = debugPathSearch
    }
}

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
    case extractText     // Added from error
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

// MARK: - AnyCodable for mixed-type payloads or attributes

// Reverted to simpler AnyCodable with public 'value' to match widespread usage
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is () { // Our nil marker for explicit nil
            try container.encodeNil()
            return
        }
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            if let codableValue = value as? Encodable {
                // If the value conforms to Encodable, let it encode itself using the provided encoder.
                // This is the most flexible approach as the Encodable type can use any container type it needs.
                try codableValue.encode(to: encoder)
            } else if CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID() {
                 try container.encodeNil()
            } else {
                 throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "AnyCodable value (\(type(of: value))) cannot be encoded and does not conform to Encodable."))
            }
        }
    }
}

// Helper struct for AnyCodable to properly encode intermediate Encodable values
// This might not be necessary if the direct (value as! Encodable).encode(to: encoder) works.
struct AnyCodablePośrednik<T: Encodable>: Encodable {
    let value: T
    init(_ value: T) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

// Helper protocol to check if a type is Optional
fileprivate protocol OptionalProtocol {
    static func isOptional() -> Bool
}

extension Optional: OptionalProtocol {
    static func isOptional() -> Bool {
        return true
    }
}

// MARK: - AXNotificationName enum
// Define AXNotificationName as a String-based enum for notification names
public enum AXNotificationName: String, Codable, Sendable {
    case focusedUIElementChanged = "AXFocusedUIElementChanged"
    case valueChanged = "AXValueChanged"
    case uiElementDestroyed = "AXUIElementDestroyed"
    case mainWindowChanged = "AXMainWindowChanged"
    case focusedWindowChanged = "AXFocusedWindowChanged"
    case applicationActivated = "AXApplicationActivated"
    case applicationDeactivated = "AXApplicationDeactivated"
    case applicationHidden = "AXApplicationHidden"
    case applicationShown = "AXApplicationShown"
    case windowCreated = "AXWindowCreated"
    case windowResized = "AXWindowResized"
    case windowMoved = "AXWindowMoved"
    case announcementRequested = "AXAnnouncementRequested"
    case focusedApplicationChanged = "AXFocusedApplicationChanged"
    case focusedTabChanged = "AXFocusedTabChanged"
    case windowMinimized = "AXWindowMiniaturized"
    case windowDeminiaturized = "AXWindowDeminiaturized"
    case sheetCreated = "AXSheetCreated"
    case drawerCreated = "AXDrawerCreated"
    case titleChanged = "AXTitleChanged"
    case resized = "AXResized"
    case moved = "AXMoved"
    case created = "AXCreated"
    case layoutChanged = "AXLayoutChanged"
    case selectedTextChanged = "AXSelectedTextChanged"
    case rowCountChanged = "AXRowCountChanged"
    case selectedChildrenChanged = "AXSelectedChildrenChanged"
    case selectedRowsChanged = "AXSelectedRowsChanged"
    case selectedColumnsChanged = "AXSelectedColumnsChanged"
    case rowExpanded = "AXRowExpanded"
    case rowCollapsed = "AXRowCollapsed"
    case selectedCellsChanged = "AXSelectedCellsChanged"
    case helpTagCreated = "AXHelpTagCreated"
    case loadComplete = "AXLoadComplete"
}

// MARK: - AXCommand and Command Structs

// Enum representing all possible AX commands
public enum AXCommand: Sendable {
    case query(QueryCommand)
    case performAction(PerformActionCommand)
    case getAttributes(GetAttributesCommand)
    case describeElement(DescribeElementCommand)
    case extractText(ExtractTextCommand)
    case batch(AXBatchCommand)
    case setFocusedValue(SetFocusedValueCommand)
    case getElementAtPoint(GetElementAtPointCommand)
    case getFocusedElement(GetFocusedElementCommand)
    case observe(ObserveCommand)
    case collectAll(CollectAllCommand)
    
    // Computed property to get command type
    public var type: String {
        switch self {
        case .query: return "query"
        case .performAction: return "performAction"
        case .getAttributes: return "getAttributes"
        case .describeElement: return "describeElement"
        case .extractText: return "extractText"
        case .batch: return "batch"
        case .setFocusedValue: return "setFocusedValue"
        case .getElementAtPoint: return "getElementAtPoint"
        case .getFocusedElement: return "getFocusedElement"
        case .observe: return "observe"
        case .collectAll: return "collectAll"
        }
    }
}

// Command envelope for AXorcist
public struct AXCommandEnvelope: Sendable {
    public let commandID: String
    public let command: AXCommand
    
    public init(commandID: String, command: AXCommand) {
        self.commandID = commandID
        self.command = command
    }
}

// Individual command structs
public struct QueryCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator
    public let attributesToReturn: [String]?
    public let maxDepthForSearch: Int
    public let includeChildrenBrief: Bool?
    
    public init(appIdentifier: String?, locator: Locator, attributesToReturn: [String]? = nil, maxDepthForSearch: Int = 10, includeChildrenBrief: Bool? = nil) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.attributesToReturn = attributesToReturn
        self.maxDepthForSearch = maxDepthForSearch
        self.includeChildrenBrief = includeChildrenBrief
    }
}

public struct PerformActionCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator
    public let action: String
    public let value: AnyCodable?
    public let maxDepthForSearch: Int
    
    public init(appIdentifier: String?, locator: Locator, action: String, value: AnyCodable? = nil, maxDepthForSearch: Int = 10) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.action = action
        self.value = value
        self.maxDepthForSearch = maxDepthForSearch
    }
}

public struct GetAttributesCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator
    public let attributes: [String]
    public let maxDepthForSearch: Int
    
    public init(appIdentifier: String?, locator: Locator, attributes: [String], maxDepthForSearch: Int = 10) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.attributes = attributes
        self.maxDepthForSearch = maxDepthForSearch
    }
}

public struct DescribeElementCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator
    public let formatOption: ValueFormatOption
    public let maxDepthForSearch: Int
    public let depth: Int
    public let includeIgnored: Bool
    public let maxSearchDepth: Int
    
    public init(appIdentifier: String?, locator: Locator, formatOption: ValueFormatOption = .smart, maxDepthForSearch: Int = 10, depth: Int = 3, includeIgnored: Bool = false, maxSearchDepth: Int = 10) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.formatOption = formatOption
        self.maxDepthForSearch = maxDepthForSearch
        self.depth = depth
        self.includeIgnored = includeIgnored
        self.maxSearchDepth = maxSearchDepth
    }
}

public struct ExtractTextCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator
    public let maxDepthForSearch: Int
    public let includeChildren: Bool?
    public let maxDepth: Int?
    
    public init(appIdentifier: String?, locator: Locator, maxDepthForSearch: Int = 10, includeChildren: Bool? = nil, maxDepth: Int? = nil) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.maxDepthForSearch = maxDepthForSearch
        self.includeChildren = includeChildren
        self.maxDepth = maxDepth
    }
}

public struct SetFocusedValueCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator
    public let value: String
    public let maxDepthForSearch: Int
    
    public init(appIdentifier: String?, locator: Locator, value: String, maxDepthForSearch: Int = 10) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.value = value
        self.maxDepthForSearch = maxDepthForSearch
    }
}

public struct GetElementAtPointCommand: Sendable {
    public let point: CGPoint
    public let appIdentifier: String?
    public let pid: Int?
    public let x: Float
    public let y: Float
    public let attributesToReturn: [String]?
    public let includeChildrenBrief: Bool?
    
    public init(point: CGPoint, appIdentifier: String? = nil, pid: Int? = nil, attributesToReturn: [String]? = nil, includeChildrenBrief: Bool? = nil) {
        self.point = point
        self.appIdentifier = appIdentifier
        self.pid = pid
        self.x = Float(point.x)
        self.y = Float(point.y)
        self.attributesToReturn = attributesToReturn
        self.includeChildrenBrief = includeChildrenBrief
    }
    
    public init(appIdentifier: String?, x: Float, y: Float, attributesToReturn: [String]? = nil, includeChildrenBrief: Bool? = nil) {
        self.point = CGPoint(x: CGFloat(x), y: CGFloat(y))
        self.appIdentifier = appIdentifier
        self.pid = nil
        self.x = x
        self.y = y
        self.attributesToReturn = attributesToReturn
        self.includeChildrenBrief = includeChildrenBrief
    }
}

public struct GetFocusedElementCommand: Sendable {
    public let appIdentifier: String?
    public let attributesToReturn: [String]?
    public let includeChildrenBrief: Bool?
    
    public init(appIdentifier: String?, attributesToReturn: [String]? = nil, includeChildrenBrief: Bool? = nil) {
        self.appIdentifier = appIdentifier
        self.attributesToReturn = attributesToReturn
        self.includeChildrenBrief = includeChildrenBrief
    }
}

public struct ObserveCommand: Sendable {
    public let appIdentifier: String?
    public let locator: Locator?
    public let notifications: [String]
    public let includeDetails: Bool
    public let watchChildren: Bool
    public let notificationName: AXNotification
    public let includeElementDetails: [String]?
    public let maxDepthForSearch: Int
    
    public init(appIdentifier: String?, locator: Locator? = nil, notifications: [String], includeDetails: Bool = true, watchChildren: Bool = false, notificationName: AXNotification, includeElementDetails: [String]? = nil, maxDepthForSearch: Int = 10) {
        self.appIdentifier = appIdentifier
        self.locator = locator
        self.notifications = notifications
        self.includeDetails = includeDetails
        self.watchChildren = watchChildren
        self.notificationName = notificationName
        self.includeElementDetails = includeElementDetails
        self.maxDepthForSearch = maxDepthForSearch
    }
}

// Command struct for collectAll
public struct CollectAllCommand: Sendable {
    public let appIdentifier: String?
    public let attributesToReturn: [String]?
    public let maxDepth: Int
    public let filterCriteria: [String: String]? // JSON string for criteria, or can be decoded
    public let valueFormatOption: ValueFormatOption?

    public init(
        appIdentifier: String? = nil, // Provide default nil
        attributesToReturn: [String]? = nil,
        maxDepth: Int = 10,
        filterCriteria: [String: String]? = nil,
        valueFormatOption: ValueFormatOption? = .smart
    ) {
        self.appIdentifier = appIdentifier
        self.attributesToReturn = attributesToReturn
        self.maxDepth = maxDepth
        self.filterCriteria = filterCriteria
        self.valueFormatOption = valueFormatOption
    }
}

// Batch command structures
public struct AXBatchCommand: Sendable {
    public struct SubCommandEnvelope: Sendable {
        public let commandID: String
        public let command: AXCommand
        
        public init(commandID: String, command: AXCommand) {
            self.commandID = commandID
            self.command = command
        }
    }
    
    public let commands: [SubCommandEnvelope]
    
    public init(commands: [SubCommandEnvelope]) {
        self.commands = commands
    }
}

// Alias for backward compatibility if needed
public typealias AXSubCommand = AXCommand
public typealias BatchCommandEnvelope = AXBatchCommand
