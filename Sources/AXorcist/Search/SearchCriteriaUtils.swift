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
        let critDesc = mappedCriteria
        axDebugLog("PathHintComponent initialized. Segment: '\\(pathSegment)' => criteria: \\(critDesc)")
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
    criteria: [String: String],
    matchType: JSONPathHintComponent.MatchType = .exact
) async -> Bool { // Made async
    if criteria.isEmpty {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesCriteria: Criteria dictionary is empty. Element '\\(element.briefDescription(option: .raw))' is considered a match by default."))
        return true
    }

    for (key, expectedValue) in criteria {
        // matchSingleCriterion needs to be awaited if it becomes async
        if !(await matchSingleCriterion(element: element, key: key, expectedValue: expectedValue, matchType: matchType)) {
            return false
        }
    }
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesCriteria: Element '\\(element.briefDescription(option: .raw))' MATCHED ALL \\(criteria.count) criteria: \\(criteria)."))
    return true
}

// MARK: - Single Criterion Matching Logic

@MainActor
private func matchSingleCriterion( // Should this be async if its callees are? Yes.
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType
) async -> Bool { // Made async, and added await to callers
    let elementDescriptionForLog = element.briefDescription(option: .raw)
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC: Matching key '\\(key)' (expected: '\\(expectedValue)', type: \\(matchType.rawValue)) on \\(elementDescriptionForLog)"))

    switch key.lowercased() {
    case "pid":
        return await matchPidCriterion(element: element, expectedPid: expectedValue, elementDescriptionForLog: elementDescriptionForLog) // Added await
    case AXMiscConstants.isIgnoredAttributeKey.lowercased():
        return await matchIsIgnoredCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog) // Added await
    case AXAttributeNames.kAXDOMClassListAttribute:
        return await matchDomClassListCriterion(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog) // Added await
    default:
        guard let actualValue: String = element.attribute(Attribute(key)) else {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC: Attribute '\\(key)' not found or nil on \\(elementDescriptionForLog). No match."))
            return false
        }
        return await compareValues(actual: actualValue, expected: expectedValue, matchType: matchType, attributeName: key, elementDescriptionForLog: elementDescriptionForLog) // Added await
    }
}

// MARK: - Specific Criterion Matchers

@MainActor
private func matchPidCriterion(element: Element, expectedPid: String, elementDescriptionForLog: String) async -> Bool { // Made async
    if element.role() == AXRoleNames.kAXApplicationRole {
        guard let actualPid_t = element.pid() else {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) (app role) failed to provide PID. No match."))
            return false
        }
        if String(actualPid_t) == expectedPid {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) (app role) PID \\(actualPid_t) MATCHES expected \\(expectedPid)."))
            return true
        } else {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) (app role) PID \\(actualPid_t) MISMATCHES expected \\(expectedPid)."))
            return false
        }
    }
    guard let actualPid_t = element.pid() else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) failed to provide PID. No match."))
        return false
    }
    let actualPidString = String(actualPid_t)
    if actualPidString == expectedPid {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) PID \\(actualPidString) MATCHES expected \\(expectedPid)."))
        return true
    } else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \\(elementDescriptionForLog) PID \\(actualPidString) MISMATCHES expected \\(expectedPid)."))
        return false
    }
}

@MainActor
private func matchIsIgnoredCriterion(element: Element, expectedValue: String, elementDescriptionForLog: String) async -> Bool { // Made async
    let actualIsIgnored = element.isIgnored()
    let expectedBool = (expectedValue.lowercased() == "true")
    if actualIsIgnored == expectedBool {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/IsIgnored: \\(elementDescriptionForLog) actual (\'(actualIsIgnored)\') MATCHES expected (\'(expectedBool)\')."))
        return true
    } else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/IsIgnored: \\(elementDescriptionForLog) actual (\'(actualIsIgnored)\') MISMATCHES expected (\'(expectedBool)\')."))
        return false
    }
}

@MainActor
private func matchDomClassListCriterion(element: Element, expectedValue: String, matchType: JSONPathHintComponent.MatchType, elementDescriptionForLog: String) async -> Bool { // Made async
    guard let domClassListValue: Any = element.attribute(Attribute(AXAttributeNames.kAXDOMClassListAttribute)) else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) attribute was nil. No match."))
        return false
    }

    let matchFound: Bool
    if let classListArray = domClassListValue as? [String] {
        switch matchType {
        case .exact:
            matchFound = classListArray.contains(expectedValue)
        case .contains:
            matchFound = classListArray.contains { $0.localizedCaseInsensitiveContains(expectedValue) }
        case .regex: // Added regex case
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "SearchCrit/DOMClass: Regex match type not yet implemented for array. Defaulting to false."))
            matchFound = false
        }
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) (Array: \\(classListArray)) match type \'\\(matchType.rawValue)\' with \'\\(expectedValue)\': \\(matchFound)."))
    } else if let classListString = domClassListValue as? String {
        switch matchType {
        case .exact:
            matchFound = classListString.split(separator: " ").map(String.init).contains(expectedValue)
        case .contains:
            matchFound = classListString.localizedCaseInsensitiveContains(expectedValue)
        case .regex: // Added regex case
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "SearchCrit/DOMClass: Regex match type not yet implemented for string. Defaulting to false."))
            matchFound = false
        }
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) (String: \'\\(classListString)\') match type \'\\(matchType.rawValue)\' with \'\\(expectedValue)\': \\(matchFound)."))
    } else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \\(elementDescriptionForLog) attribute was not [String] or String. Type: \\(type(of: domClassListValue)). No match."))
        return false
    }
    return matchFound
}

// MARK: - Value Comparison Helper

@MainActor
private func compareValues(actual: String, expected: String, matchType: JSONPathHintComponent.MatchType, attributeName: String, elementDescriptionForLog: String) async -> Bool { // Made async
    let comparisonResult: Bool
    switch matchType {
    case .exact:
        comparisonResult = (actual == expected)
    case .contains:
        comparisonResult = actual.localizedCaseInsensitiveContains(expected)
    case .regex: // Added regex case
        await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "SearchCrit/Compare: Regex match type not yet implemented for attribute \'\\(attributeName)\'. Defaulting to false."))
        comparisonResult = false
    }

    if comparisonResult {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: \'\\(attributeName)\' on \\(elementDescriptionForLog): Actual (\'\\(actual)\') MATCHED Expected (\'\\(expected)\') with type \'\\(matchType.rawValue)\'."))
    } else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: \'\\(attributeName)\' on \\(elementDescriptionForLog): Actual (\'\\(actual)\') MISMATCHED Expected (\'\\(expected)\') with type \'\\(matchType.rawValue)\'."))
    }
    return comparisonResult
}


