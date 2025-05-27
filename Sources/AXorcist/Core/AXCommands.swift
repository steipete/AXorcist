// AXCommands.swift - AXCommand enum and individual command structs

import CoreGraphics
import Foundation

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
