// Models.swift - Contains core data models and type aliases

import Foundation

// Type alias for element attributes dictionary
public typealias ElementAttributes = [String: AnyCodable]

public struct AXElement: Codable, HandlerDataRepresentable {
    public var attributes: ElementAttributes?
    public var path: [String]?

    public init(attributes: ElementAttributes?, path: [String]? = nil) {
        self.attributes = attributes
        self.path = path
    }
}

// MARK: - Search Log Entry Model (for stderr JSON logging)
public struct SearchLogEntry: Codable {
    public let depth: Int
    public let elementRole: String?
    public let elementTitle: String?
    public let elementIdentifier: String?
    public let maxDepth: Int
    public let criteria: [String: String]?
    public let status: String // status (e.g., "vis", "found", "noMatch", "maxD")
    public let isMatch: Bool? // isMatch (true, false, or nil if not applicable for this status)

    enum CodingKeys: String, CodingKey {
        case depth = "d"
        case elementRole = "eR"
        case elementTitle = "eT"
        case elementIdentifier = "eI"
        case maxDepth = "mD"
        case criteria = "c"
        case status = "s"
        case isMatch = "iM"
    }

    // Public initializer
    public init(depth: Int, elementRole: String?, elementTitle: String?, elementIdentifier: String?, maxDepth: Int, criteria: [String: String]?, status: String, isMatch: Bool?) {
        self.depth = depth
        self.elementRole = elementRole
        self.elementTitle = elementTitle
        self.elementIdentifier = elementIdentifier
        self.maxDepth = maxDepth
        self.criteria = criteria
        self.status = status
        self.isMatch = isMatch
    }
}
