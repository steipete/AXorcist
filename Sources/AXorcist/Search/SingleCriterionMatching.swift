// SingleCriterionMatching.swift - Single criterion matching logic

import Foundation

// MARK: - Single Criterion Matching Logic

@MainActor
internal func matchSingleCriterion(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String
) -> Bool {
    GlobalAXLogger.shared.log(AXLogEntry(
        level: .debug,
        message: "SC/MSC: Matching key '\(key)' (expected: '\(expectedValue)', " +
            "type: \(matchType.rawValue)) on \(elementDescriptionForLog)"
    ))

    let comparisonResult = matchAttributeByKey(
        element: element,
        key: key,
        expectedValue: expectedValue,
        matchType: matchType,
        elementDescriptionForLog: elementDescriptionForLog
    )

    GlobalAXLogger.shared.log(AXLogEntry(
        level: .debug,
        message: "SC/MSC: Key '\(key)', Expected='\(expectedValue)', MatchType='\(matchType.rawValue)', " +
            "Result=\(comparisonResult) on \(elementDescriptionForLog)."
    ))
    return comparisonResult
}

@MainActor
private func matchAttributeByKey(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String
) -> Bool {
    switch key.lowercased() {
    case AXAttributeNames.kAXRoleAttribute.lowercased(), "role":
        return matchRoleAttribute(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXSubroleAttribute.lowercased(), "subrole":
        return matchSubroleAttribute(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXIdentifierAttribute.lowercased(), "identifier", "id":
        return matchIdentifierAttribute(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    case "pid":
        return matchPidCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog)
    case AXAttributeNames.kAXDOMClassListAttribute.lowercased(), "domclasslist", "classlist", "dom":
        return matchDomClassListAttribute(element: element, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    case AXMiscConstants.isIgnoredAttributeKey.lowercased(), "isignored", "ignored":
        return matchIsIgnoredCriterion(element: element, expectedValue: expectedValue, elementDescriptionForLog: elementDescriptionForLog)
    case AXMiscConstants.computedNameAttributeKey.lowercased(), "computedname", "name":
        return matchComputedNameAttributes(
            element: element,
            expectedValue: expectedValue,
            matchType: matchType,
            attributeName: AXMiscConstants.computedNameAttributeKey,
            elementDescriptionForLog: elementDescriptionForLog
        )
    case "computednamewithvalue", "namewithvalue":
        return matchComputedNameAttributes(
            element: element,
            expectedValue: expectedValue,
            matchType: matchType,
            attributeName: "computedNameWithValue",
            elementDescriptionForLog: elementDescriptionForLog,
            includeValueInComputedName: true
        )
    default:
        return matchGenericAttribute(element: element, key: key, expectedValue: expectedValue, matchType: matchType, elementDescriptionForLog: elementDescriptionForLog)
    }
}

@MainActor
private func matchGenericAttribute(element: Element, key: String, expectedValue: String, matchType: JSONPathHintComponent.MatchType, elementDescriptionForLog: String) -> Bool {
    guard let actualValueAny: Any = element.attribute(Attribute(key)) else {
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "SC/MSC/Default: Attribute '\(key)' not found or nil on " +
                "\(elementDescriptionForLog). No match."
        ))
        return false
    }
    let actualValueString: String
    if let str = actualValueAny as? String {
        actualValueString = str
    } else {
        actualValueString = "\(actualValueAny)"
        GlobalAXLogger.shared.log(AXLogEntry(
            level: .debug,
            message: "SC/MSC/Default: Attribute '\(key)' on \(elementDescriptionForLog) " +
                "was not String (type: \(type(of: actualValueAny))), " +
                "using string description: '\(actualValueString)' for comparison."
        ))
    }
    GlobalAXLogger.shared.log(AXLogEntry(
        level: .debug,
        message: "SC/MSC/Default: Attribute '\(key)', Actual='\(actualValueString)'"
    ))
    return compareStrings(
        actualValueString, expectedValue, matchType,
        caseSensitive: true,
        attributeName: key,
        elementDescriptionForLog: elementDescriptionForLog
    )
}