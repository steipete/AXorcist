// SearchCriteriaUtils.swift - Utility functions for handling search criteria

import ApplicationServices
import Foundation
import AppKit // For NSRunningApplication access
// GlobalAXLogger is assumed available

// MARK: - PathHintComponent Definition
// This PathHintComponent is simpler and used for basic string path hints if ever needed again.
// For new functionality, JSONPathHintComponent is preferred.
@MainActor
public struct PathHintComponent {
    public let criteria: [String: String]
    public let originalSegment: String

    // Corrected: PathUtils.attributeKeyMappings might be the intended property
    private static let attributeAliases: [String: String] = PathUtils.attributeKeyMappings // Ensure this is the correct static property in PathUtils

    public init?(pathSegment: String) {
        self.originalSegment = pathSegment
        var parsedCriteria = PathUtils.parseRichPathComponent(pathSegment)

        if parsedCriteria.isEmpty {
            let fallbackPairs = pathSegment
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            for pair in fallbackPairs {
                let keyValue = pair.split(separator: "=", maxSplits: 1)
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                if keyValue.count == 2 {
                    parsedCriteria[String(keyValue[0])] = String(keyValue[1])
                }
            }
        }

        var mappedCriteria: [String: String] = [:]
        for (rawKey, value) in parsedCriteria {
            if let mappedKey = Self.attributeAliases[rawKey] {
                mappedCriteria[mappedKey] = value
            } else {
                mappedCriteria[rawKey] = value // Keep unmapped keys as-is
            }
        }

        if mappedCriteria.isEmpty {
            axWarningLog("PathHintComponent: Path segment '\\(pathSegment)' produced no usable criteria after parsing.")
            return nil
        }
        self.criteria = mappedCriteria
        axDebugLog("PathHintComponent initialized. Segment: '\\(pathSegment)' => criteria: \\(mappedCriteria)")
    }

    init(criteria: [String: String], originalSegment: String = "") {
        self.criteria = criteria
        self.originalSegment = originalSegment.isEmpty && !criteria.isEmpty ? "criteria_only_init" : originalSegment
    }

    // PathHintComponent uses exact matching by default when calling elementMatchesCriteria
    func matches(element: Element) async -> Bool {
        return await elementMatchesCriteria(element, criteria: self.criteria, matchType: .exact)
    }
}

// MARK: - Criteria Matching Helper

@MainActor
public func elementMatchesCriteria(
    _ element: Element,
    criteria: [Criterion],
    matchType: JSONPathHintComponent.MatchType = .exact
) async -> Bool {
    if criteria.isEmpty {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesCriteria: Criteria dictionary is empty. Element '\\(element.briefDescription(option: .raw))' is considered a match by default."))
        return true
    }

    for criterion in criteria {
        let effectiveMatchType = criterion.match_type.flatMap { JSONPathHintComponent.MatchType(rawValue: $0) } ?? matchType
        if await !matchSingleCriterion(element: element, key: criterion.attribute, expectedValue: criterion.value, matchType: effectiveMatchType, elementDescriptionForLog: element.briefDescription(option: .raw)) {
            return false
        }
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesCriteria: Element '\\(element.briefDescription(option: .raw))' MATCHED ALL \\(criteria.count) criteria: \\(criteria)."))
    return true
}

// Overload for backward compatibility with dictionary
@MainActor
public func elementMatchesCriteria(
    _ element: Element,
    criteria: [String: String],
    matchType: JSONPathHintComponent.MatchType = .exact
) async -> Bool {
    let criterionArray = criteria.map { key, value in
        Criterion(attribute: key, value: value, match_type: nil)
    }
    return await elementMatchesCriteria(element, criteria: criterionArray, matchType: matchType)
}

// MARK: - Single Criterion Matching Logic

@MainActor
internal func matchSingleCriterion(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String
) async -> Bool {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC: Matching key '\\(key)' (expected: '\\(expectedValue)', type: \\(matchType.rawValue)) on \\(elementDescriptionForLog)"))

    switch key.lowercased() {
    case AXAttributeNames.kAXRoleAttribute.lowercased(), "role":
        return compareStrings(element.role(), expectedValue, matchType, attributeName: AXAttributeNames.kAXRoleAttribute, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXSubroleAttribute.lowercased(), "subrole":
        return compareStrings(element.subrole(), expectedValue, matchType, attributeName: AXAttributeNames.kAXSubroleAttribute, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXIdentifierAttribute.lowercased(), "identifier", "id":
        return compareStrings(element.identifier(), expectedValue, matchType, attributeName: AXAttributeNames.kAXIdentifierAttribute, elementDescriptionForLog: elementDescriptionForLog)
    case "pid":
        return matchPidCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXDOMClassListAttribute.lowercased(), "domclasslist", "classlist":
        return await matchDomClassListCriterion(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    case AXMiscConstants.isIgnoredAttributeKey.lowercased(), "isignored", "ignored":
        return matchIsIgnoredCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog)
    case AXMiscConstants.computedNameAttributeKey.lowercased(), "computedname", "name":
        return await matchComputedNameAttributes(element: element, expectedValue: expectedValue, matchType: matchType, attributeName: AXMiscConstants.computedNameAttributeKey, elementDescriptionForLog: elementDescriptionForLog)
    case "computednamewithvalue", "namewithvalue":
        return await matchComputedNameAttributes(element: element, expectedValue: expectedValue, matchType: matchType, attributeName: "computedNameWithValue", elementDescriptionForLog: elementDescriptionForLog, includeValueInComputedName: true)
    default:
        guard let actualValue: String = element.attribute(Attribute(key)) else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC: Attribute '\\(key)' not found or nil on \\(elementDescriptionForLog). No match."))
            return false
        }
        return compareStrings(actualValue, expectedValue, matchType, attributeName: key, elementDescriptionForLog: elementDescriptionForLog)
    }
}

// MARK: - Specific Criterion Matchers

@MainActor
private func matchPidCriterion(element: Element, expectedValue: String, elementDescriptionForLog: String) -> Bool {
    let expectedPid = expectedValue
    if element.role() == AXRoleNames.kAXApplicationRole {
        guard let actualPid_t = element.pid() else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) (app role) failed to provide PID. No match."))
            return false
        }
        if String(actualPid_t) == expectedPid {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) (app role) PID \\(actualPid_t) MATCHES expected \\(expectedPid)."))
            return true
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) (app role) PID \\(actualPid_t) MISMATCHES expected \\(expectedPid)."))
            return false
        }
    }
    guard let actualPid_t = element.pid() else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) failed to provide PID. No match."))
        return false
    }
    let actualPidString = String(actualPid_t)
    if actualPidString == expectedPid {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) PID \\(actualPidString) MATCHES expected \\(expectedPid)."))
        return true
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) PID \\(actualPidString) MISMATCHES expected \\(expectedPid)."))
        return false
    }
}

@MainActor
private func matchIsIgnoredCriterion(element: Element, expectedValue: String, elementDescriptionForLog: String) -> Bool {
    let actualIsIgnored: Bool = element.isIgnored()
    let expectedBool = (expectedValue.lowercased() == "true")
    if actualIsIgnored == expectedBool {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/IsIgnored: \\(elementDescriptionForLog) actual ('\\(actualIsIgnored)\') MATCHES expected ('\\(expectedBool)\')."))
        return true
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/IsIgnored: \\(elementDescriptionForLog) actual ('\\(actualIsIgnored)\') MISMATCHES expected ('\\(expectedBool)\')."))
        return false
    }
}

@MainActor
private func matchDomClassListCriterion(element: Element, expectedValue: String, matchType: JSONPathHintComponent.MatchType, elementDescriptionForLog: String) async -> Bool {
    guard let domClassListValue: Any = element.attribute(Attribute(AXAttributeNames.kAXDOMClassListAttribute)) else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) attribute was nil. No match."))
        return false
    }

    var matchFound = false
    if let classListArray = domClassListValue as? [String] {
        switch matchType {
        case .exact:
            matchFound = classListArray.contains(expectedValue)
        case .contains:
            matchFound = classListArray.contains { $0.localizedCaseInsensitiveContains(expectedValue) }
        case .regex:
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "SearchCrit/DOMClass: Regex match type not yet implemented for array. Defaulting to false."))
            matchFound = false
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) (Array: \\(classListArray)) match type '\\(matchType.rawValue)\' with '\\(expectedValue)\': \\(matchFound)."))
    } else if let classListString = domClassListValue as? String {
        switch matchType {
        case .exact:
            matchFound = classListString.split(separator: " ").map(String.init).contains(expectedValue)
        case .contains:
            matchFound = classListString.localizedCaseInsensitiveContains(expectedValue)
        case .regex:
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "SearchCrit/DOMClass: Regex match type not yet implemented for string. Defaulting to false."))
            matchFound = false
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) (String: '\\(classListString)\') match type '\\(matchType.rawValue)\' with '\\(expectedValue)\': \\(matchFound)."))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) attribute was not [String] or String. Type: \\(type(of: domClassListValue)). No match."))
        return false
    }
    return matchFound
}

// MARK: - Computed Name Matcher Helper

@MainActor
private func matchComputedNameAttributes(
    element: Element,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    attributeName: String,
    elementDescriptionForLog: String,
    includeValueInComputedName: Bool = false
) async -> Bool {
    let computedName = element.computedName()
    
    if includeValueInComputedName {
        // For computedNameWithValue, we might need to include the value attribute
        if let value = element.value() as? String {
            let combinedName = (computedName ?? "") + " " + value
            return compareStrings(combinedName, expectedValue, matchType, attributeName: attributeName, elementDescriptionForLog: elementDescriptionForLog)
        }
    }
    
    return compareStrings(computedName, expectedValue, matchType, attributeName: attributeName, elementDescriptionForLog: elementDescriptionForLog)
}

// MARK: - Value Comparison Helper

@MainActor
internal func compareStrings(_ actual: String?, _ expected: String, _ matchType: JSONPathHintComponent.MatchType, attributeName: String, elementDescriptionForLog: String) -> Bool {
    guard let actual = actual else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: '\\(attributeName)\' on \\(elementDescriptionForLog): Actual value is nil. Expected '\\(expected)'. No match."))
        return false
    }

    let comparisonResult: Bool
    switch matchType {
    case .exact:
        comparisonResult = (actual == expected)
    case .contains:
        comparisonResult = actual.localizedCaseInsensitiveContains(expected)
    case .regex:
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "SearchCrit/Compare: Regex match type not yet implemented for attribute '\\(attributeName)\'. Defaulting to false."))
        comparisonResult = false
    }

    if comparisonResult {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: '\\(attributeName)\' on \\(elementDescriptionForLog): Actual ('\\(actual)\') MATCHED Expected ('\\(expected)\') with type '\\(matchType.rawValue)\'."))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: '\\(attributeName)\' on \\(elementDescriptionForLog): Actual ('\\(actual)\') MISMATCHED Expected ('\\(expected)\') with type '\\(matchType.rawValue)\'."))
    }
    return comparisonResult
}


