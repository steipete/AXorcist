// MatchingTypes.swift - Types for element matching and locating

import Foundation

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