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
            axWarningLog("PathHintComponent: Path segment '\(pathSegment)' produced no usable criteria after parsing.")
            return nil
        }
        self.criteria = mappedCriteria
        axDebugLog("PathHintComponent initialized. Segment: '\(pathSegment)' => criteria: \(mappedCriteria)")
    }

    init(criteria: [String: String], originalSegment: String = "") {
        self.criteria = criteria
        self.originalSegment = originalSegment.isEmpty && !criteria.isEmpty ? "criteria_only_init" : originalSegment
    }

    // PathHintComponent uses exact matching by default when calling elementMatchesCriteria
    func matches(element: Element) -> Bool {
        return elementMatchesCriteria(element, criteria: self.criteria, matchType: JSONPathHintComponent.MatchType.exact)
    }
}

// MARK: - Criteria Matching Helper

@MainActor
public func elementMatchesAllCriteria(
    element: Element,
    criteria: [Criterion],
    matchType: JSONPathHintComponent.MatchType = .exact
) -> Bool {
    for criterion in criteria {
        let effectiveMatchType = criterion.match_type ?? matchType
        if !matchSingleCriterion(element: element, key: criterion.attribute, expectedValue: criterion.value, matchType: effectiveMatchType, elementDescriptionForLog: element.briefDescription(option: ValueFormatOption.raw)) {
            return false
        }
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesAllCriteria: Element '\(element.briefDescription(option: ValueFormatOption.raw))' MATCHED ALL \(criteria.count) criteria: \(criteria)."))
    return true
}

@MainActor
public func elementMatchesAnyCriterion(
    element: Element,
    criteria: [Criterion],
    matchType: JSONPathHintComponent.MatchType = .exact
) -> Bool {
    if criteria.isEmpty { // If there are no criteria, it's vacuously false that any criterion matches.
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesAnyCriterion: No criteria provided. Returning false."))
        return false
    }
    for criterion in criteria {
        let effectiveMatchType = criterion.match_type ?? matchType // Use criterion's own match_type if present, else the overall one.
        if matchSingleCriterion(element: element, key: criterion.attribute, expectedValue: criterion.value, matchType: effectiveMatchType, elementDescriptionForLog: element.briefDescription(option: ValueFormatOption.raw)) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesAnyCriterion: Element '\(element.briefDescription(option: ValueFormatOption.raw))' MATCHED criterion: \(criterion)."))
            return true // Found one criterion that matches
        }
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "elementMatchesAnyCriterion: Element '\(element.briefDescription(option: ValueFormatOption.raw))' DID NOT MATCH ANY of \(criteria.count) criteria: \(criteria)."))
    return false
}

// Overload for backward compatibility with dictionary
@MainActor
public func elementMatchesCriteria(
    _ element: Element,
    criteria: [String: String],
    matchType: JSONPathHintComponent.MatchType = .exact
) -> Bool {
    let criterionArray = criteria.map { key, value in
        Criterion(attribute: key, value: value, matchType: nil)
    }
    return elementMatchesAllCriteria(element: element, criteria: criterionArray, matchType: matchType)
}

// MARK: - Single Criterion Matching Logic

@MainActor
internal func matchSingleCriterion(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String
) -> Bool {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC: Matching key '\(key)' (expected: '\(expectedValue)', type: \(matchType.rawValue)) on \(elementDescriptionForLog)"))
    let comparisonResult: Bool

    switch key.lowercased() {
    case AXAttributeNames.kAXRoleAttribute.lowercased(), "role":
        let actual = element.role()
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/Role: Actual='\(actual ?? "nil")'"))
        if actual == AXRoleNames.kAXTextAreaRole {
            let domClassList = element.attribute(Attribute<Any>(AXAttributeNames.kAXDOMClassListAttribute))
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "SearchCrit/MSC/Role: ELEMENT IS AXTextArea. Its AXDOMClassList is: \(String(describing: domClassList))"))
        }
        comparisonResult = compareStrings(actual, expectedValue, matchType, caseSensitive: false, attributeName: AXAttributeNames.kAXRoleAttribute, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXSubroleAttribute.lowercased(), "subrole":
        let actual = element.subrole()
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/Subrole: Actual='\(actual ?? "nil")'"))
        comparisonResult = compareStrings(actual, expectedValue, matchType, caseSensitive: false, attributeName: AXAttributeNames.kAXSubroleAttribute, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXIdentifierAttribute.lowercased(), "identifier", "id":
        let actual = element.identifier()
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/ID: Actual='\(actual ?? "nil")'"))
        comparisonResult = compareStrings(actual, expectedValue, matchType, caseSensitive: true, attributeName: AXAttributeNames.kAXIdentifierAttribute, elementDescriptionForLog: elementDescriptionForLog)
    case "pid":
        comparisonResult = matchPidCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXDOMClassListAttribute.lowercased(), "domclasslist", "classlist":
        let actualRaw = element.attribute(Attribute<Any>(AXAttributeNames.kAXDOMClassListAttribute))
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/DOMClassList: ActualRaw='\(String(describing: actualRaw))'"))
        comparisonResult = matchDomClassListCriterion(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    case AXMiscConstants.isIgnoredAttributeKey.lowercased(), "isignored", "ignored":
        comparisonResult = matchIsIgnoredCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog)
    case AXMiscConstants.computedNameAttributeKey.lowercased(), "computedname", "name":
        comparisonResult = matchComputedNameAttributes(element: element, expectedValue: expectedValue, matchType: matchType, attributeName: AXMiscConstants.computedNameAttributeKey, elementDescriptionForLog: elementDescriptionForLog)
    case "computednamewithvalue", "namewithvalue":
        comparisonResult = matchComputedNameAttributes(element: element, expectedValue: expectedValue, matchType: matchType, attributeName: "computedNameWithValue", elementDescriptionForLog: elementDescriptionForLog, includeValueInComputedName: true)
    default:
        guard let actualValueAny: Any = element.attribute(Attribute(key)) else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/Default: Attribute '\(key)' not found or nil on \(elementDescriptionForLog). No match."))
            return false
        }
        let actualValueString: String
        if let str = actualValueAny as? String {
            actualValueString = str
        } else {
            actualValueString = "\(actualValueAny)"
             GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/Default: Attribute '\(key)' on \(elementDescriptionForLog) was not String (type: \(type(of: actualValueAny))), using string description: '\(actualValueString)' for comparison."))
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC/Default: Attribute '\(key)', Actual='\(actualValueString)'"))
        comparisonResult = compareStrings(actualValueString, expectedValue, matchType, caseSensitive: true, attributeName: key, elementDescriptionForLog: elementDescriptionForLog)
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/MSC: Key '\(key)', Expected='\(expectedValue)', MatchType='\(matchType.rawValue)', Result=\(comparisonResult) on \(elementDescriptionForLog)."))
    return comparisonResult
}

// MARK: - Specific Criterion Matchers

@MainActor
private func matchPidCriterion(element: Element, expectedValue: String, elementDescriptionForLog: String) -> Bool {
    let expectedPid = expectedValue
    if element.role() == AXRoleNames.kAXApplicationRole {
        guard let actualPid_t = element.pid() else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \(elementDescriptionForLog) (app role) failed to provide PID. No match."))
            return false
        }
        if String(actualPid_t) == expectedPid {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \(elementDescriptionForLog) (app role) PID \(actualPid_t) MATCHES expected \(expectedPid)."))
            return true
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \(elementDescriptionForLog) (app role) PID \(actualPid_t) MISMATCHES expected \(expectedPid)."))
            return false
        }
    }
    guard let actualPid_t = element.pid() else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \(elementDescriptionForLog) failed to provide PID. No match."))
        return false
    }
    let actualPidString = String(actualPid_t)
    if actualPidString == expectedPid {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \(elementDescriptionForLog) PID \(actualPidString) MATCHES expected \(expectedPid)."))
        return true
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/PID: \(elementDescriptionForLog) PID \(actualPidString) MISMATCHES expected \(expectedPid)."))
        return false
    }
}

@MainActor
private func matchIsIgnoredCriterion(element: Element, expectedValue: String, elementDescriptionForLog: String) -> Bool {
    let actualIsIgnored: Bool = element.isIgnored()
    let expectedBool = (expectedValue.lowercased() == "true")
    if actualIsIgnored == expectedBool {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/IsIgnored: \(elementDescriptionForLog) actual ('\(actualIsIgnored)') MATCHES expected ('\(expectedBool)')."))
        return true
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/IsIgnored: \(elementDescriptionForLog) actual ('\(actualIsIgnored)') MISMATCHES expected ('\(expectedBool)')."))
        return false
    }
}

@MainActor
private func matchDomClassListCriterion(element: Element, expectedValue: String, matchType: JSONPathHintComponent.MatchType, elementDescriptionForLog: String) -> Bool {
    guard let domClassListValue: Any = element.attribute(Attribute(AXAttributeNames.kAXDOMClassListAttribute)) else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \(elementDescriptionForLog) attribute was nil. No match."))
        return false
    }

    var matchFound = false
    if let classListArray = domClassListValue as? [String] {
        switch matchType {
        case .exact:
            matchFound = classListArray.contains(expectedValue)
        case .contains:
            matchFound = classListArray.contains { $0.localizedCaseInsensitiveContains(expectedValue) }
        case .containsAny:
            let expectedParts = expectedValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            matchFound = classListArray.contains { actualPart in
                expectedParts.contains { expectedPart in actualPart.localizedCaseInsensitiveContains(expectedPart) }
            }
        case .prefix:
            matchFound = classListArray.contains { $0.hasPrefix(expectedValue) }
        case .suffix:
            matchFound = classListArray.contains { $0.hasSuffix(expectedValue) }
        case .regex:
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: Regex matching for array of classes. Element: \(elementDescriptionForLog) Expected: \(expectedValue)."))
            matchFound = classListArray.contains { item in
                 if let _ = item.range(of: expectedValue, options: .regularExpression) { return true }
                 return false
            }
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \(elementDescriptionForLog) (Array: \(classListArray)) match type '\(matchType.rawValue)' with '\(expectedValue)' resolved to \(matchFound)."))
    } else if let classListString = domClassListValue as? String {
        let classes = classListString.split(separator: " ").map(String.init)
        switch matchType {
        case .exact:
            matchFound = classes.contains(expectedValue)
        case .contains:
            matchFound = classListString.localizedCaseInsensitiveContains(expectedValue)
        case .containsAny:
            let expectedParts = expectedValue.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            matchFound = expectedParts.contains { classListString.localizedCaseInsensitiveContains($0) }
        case .prefix:
            matchFound = classes.contains { $0.hasPrefix(expectedValue) }
        case .suffix:
            matchFound = classes.contains { $0.hasSuffix(expectedValue) }
        case .regex:
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: Regex matching for space-separated class string. Element: \(elementDescriptionForLog) Expected: \(expectedValue)."))
            matchFound = classes.contains { item in
                 if let _ = item.range(of: expectedValue, options: .regularExpression) { return true }
                 return false
            }
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \(elementDescriptionForLog) (String: '\(classListString)') match type '\(matchType.rawValue)' with '\(expectedValue)' resolved to \(matchFound)."))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \(elementDescriptionForLog) attribute was not [String] or String (type: \(type(of: domClassListValue))). No match."))
        return false
    }

    if matchFound {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \(elementDescriptionForLog) MATCHED expected '\(expectedValue)' with type '\(matchType.rawValue)'. Classes: '\(domClassListValue)'"))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/DOMClass: \(elementDescriptionForLog) MISMATCHED expected '\(expectedValue)' with type '\(matchType.rawValue)'. Classes: '\(domClassListValue)'"))
    }
    return matchFound
}


@MainActor
private func matchComputedNameAttributes(element: Element, expectedValue: String, matchType: JSONPathHintComponent.MatchType, attributeName: String, elementDescriptionForLog: String, includeValueInComputedName: Bool = false) -> Bool {
    let computedName = element.computedName()

    if includeValueInComputedName {
        if let value = element.value() as? String {
            let combinedName = (computedName ?? "") + " " + value
            return compareStrings(combinedName, expectedValue, matchType, attributeName: attributeName, elementDescriptionForLog: elementDescriptionForLog)
        }
    }
    
    return compareStrings(computedName, expectedValue, matchType, attributeName: attributeName, elementDescriptionForLog: elementDescriptionForLog)
}

// MARK: - String Comparison Logic

@MainActor
public func compareStrings(
    _ actualValueOptional: String?,
    _ expectedValue: String,
    _ matchType: JSONPathHintComponent.MatchType,
    caseSensitive: Bool = true,
    attributeName: String,
    elementDescriptionForLog: String
) -> Bool {
    guard let actualValue = actualValueOptional, !actualValue.isEmpty else {
        let isEmptyMatch = expectedValue.isEmpty && matchType == .exact
        
        if isEmptyMatch {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: '\(attributeName)' on \(elementDescriptionForLog): Actual is nil/empty, Expected is empty. MATCHED with type '\(matchType.rawValue)'."))
            return true
        } else {
             GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: Attribute '\(attributeName)' on \(elementDescriptionForLog) (actual: nil/empty, expected: '\(expectedValue)', type: \(matchType.rawValue)) -> MISMATCH"))
            return false
        }
    }

    let finalActual = caseSensitive ? actualValue : actualValue.lowercased()
    let finalExpected = caseSensitive ? expectedValue : expectedValue.lowercased()
    var result = false

    switch matchType {
    case .exact:
        result = (finalActual.localizedCompare(finalExpected) == .orderedSame)
    case .contains:
        result = finalActual.contains(finalExpected)
    case .regex:
        result = (finalActual.range(of: finalExpected, options: .regularExpression) != nil)
    case .prefix:
        result = finalActual.hasPrefix(finalExpected)
    case .suffix:
        result = finalActual.hasSuffix(finalExpected)
    case .containsAny:
        let expectedSubstrings = finalExpected.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespacesAndNewlines)) }
        if expectedSubstrings.isEmpty && finalActual.isEmpty {
            result = true
        } else {
            result = expectedSubstrings.contains { substring in
                finalActual.contains(substring)
            }
        }
    }

    let matchStatus = result ? "MATCH" : "MISMATCH"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "SearchCrit/Compare: Attribute '\(attributeName)' on \(elementDescriptionForLog) (actual: '\(actualValue)', expected: '\(expectedValue)', type: \(matchType.rawValue), caseSensitive: \(caseSensitive)) -> \(matchStatus)"))
    return result
}

// MARK: - Functions using undefined types (SearchCriteria, ProcessMatcherProtocol)
// These functions are commented out until the required types are defined

/*
@MainActor
public func evaluateElementAgainstCriteria(
    _ element: Element,
    criteria: SearchCriteria,
    appIdentifier: String?,
    processMatcher: ProcessMatcherProtocol
) -> (isMatch: Bool, logs: [AXLogEntry]) {
    var logs: [AXLogEntry] = [] // Changed from axDebugLog to aggregated logs

    // Check if the app identifier matches, if provided and different from current app
    if let criteriaAppIdentifier = criteria.appIdentifier,
       let currentAppIdentifier = appIdentifier,
       criteriaAppIdentifier != currentAppIdentifier
    {
        logs.append(AXLogEntry(level: .debug, message: "SearchCriteriaUtils: Element \(element.briefDescription(option: ValueFormatOption.smart)) app mismatch. Criteria wants '\(criteriaAppIdentifier)', current is '\(currentAppIdentifier)'. No match."))
        return (false, logs) // Early exit if app ID doesn't match
    }

    // Check basic properties first (role, subrole, identifier, title, value using direct attribute calls)
    if let criteriaRole = criteria.role, element.role() != criteriaRole { // role() is sync
        logs.append(AXLogEntry(level: .debug, message: "SearchCriteriaUtils: Element \(element.briefDescription(option: ValueFormatOption.smart)) role mismatch. Expected '\(criteriaRole)', got '\(element.role() ?? "nil")'."))
        return (false, logs)
    }

    // If all checks passed
    logs.append(AXLogEntry(level: .debug, message: "SearchCriteriaUtils: Element \(element.briefDescription(option: ValueFormatOption.smart)) matches all criteria for app '\(appIdentifier ?? "any")'."))
    return (true, logs)
}

@MainActor
public func elementMatchesAnyCriteria(
    _ element: Element,
    criteriaList: [SearchCriteria],
    appIdentifier: String?,
    processMatcher: ProcessMatcherProtocol
) -> (isMatch: Bool, logs: [AXLogEntry]) {
    var overallLogs: [AXLogEntry] = []
    for criteria in criteriaList {
        let result = evaluateElementAgainstCriteria(element, criteria: criteria, appIdentifier: appIdentifier, processMatcher: processMatcher)
        overallLogs.append(contentsOf: result.logs)
        if result.isMatch {
            overallLogs.append(AXLogEntry(level: .debug, message: "SearchCriteriaUtils: Element \(element.briefDescription(option: ValueFormatOption.smart)) matched one of the criteria for app '\(appIdentifier ?? "any")'."))
            return (true, overallLogs)
        }
    }
    overallLogs.append(AXLogEntry(level: .debug, message: "SearchCriteriaUtils: Element \(element.briefDescription(option: ValueFormatOption.smart)) did not match any of the criteria for app '\(appIdentifier ?? "any")'."))
    return (false, overallLogs)
}
*/
