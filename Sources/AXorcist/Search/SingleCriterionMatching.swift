// SingleCriterionMatching.swift - Single criterion matching logic

import Foundation

// MARK: - Single Criterion Matching Logic

@MainActor
func matchSingleCriterion(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String) -> Bool
{
    GlobalAXLogger.shared.log(
        AXLogEntry(
            level: .debug,
            message: logSegments(
                "SC/MSC: Matching key '\(key)' (expected: '\(expectedValue)', ",
                "type: \(matchType.rawValue)) on ",
                elementDescriptionForLog)))

    let comparisonResult = matchAttributeByKey(
        element: element,
        key: key,
        expectedValue: expectedValue,
        matchType: matchType,
        elementDescriptionForLog: elementDescriptionForLog)

    GlobalAXLogger.shared.log(
        AXLogEntry(
            level: .debug,
            message: logSegments(
                [
                    "SC/MSC: Key '\(key)'",
                    "Expected='\(expectedValue)'",
                    "MatchType='\(matchType.rawValue)'",
                    "Result=\(comparisonResult) on \(elementDescriptionForLog).",
                ])))
    return comparisonResult
}

@MainActor
private func matchAttributeByKey(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String) -> Bool
{
    let context = CriterionContext(
        element: element,
        expectedValue: expectedValue,
        matchType: matchType,
        elementDescriptionForLog: elementDescriptionForLog)
    switch criterionKey(for: key) {
    case .role:
        return context.matchRole()
    case .subrole:
        return context.matchSubrole()
    case .identifier:
        return context.matchIdentifier()
    case .pid:
        return context.matchPid()
    case .domClassList:
        return context.matchDomClassList()
    case .isIgnored:
        return context.matchIsIgnored()
    case .computedName:
        return context.matchComputedName()
    case .computedNameWithValue:
        return context.matchComputedNameWithValue()
    case let .generic(originalKey):
        return context.matchGenericAttributeValue(key: originalKey)
    }
}

private enum CriterionKey {
    case role, subrole, identifier, pid, domClassList, isIgnored, computedName, computedNameWithValue
    case generic(String)
}

private func criterionKey(for rawKey: String) -> CriterionKey {
    let normalized = rawKey.lowercased()
    switch normalized {
    case AXAttributeNames.kAXRoleAttribute.lowercased(), "role":
        return .role
    case AXAttributeNames.kAXSubroleAttribute.lowercased(), "subrole":
        return .subrole
    case AXAttributeNames.kAXIdentifierAttribute.lowercased(), "identifier", "id":
        return .identifier
    case "pid":
        return .pid
    case AXAttributeNames.kAXDOMClassListAttribute.lowercased(),
         "domclasslist", "classlist", "dom":
        return .domClassList
    case AXMiscConstants.isIgnoredAttributeKey.lowercased(), "isignored", "ignored":
        return .isIgnored
    case AXMiscConstants.computedNameAttributeKey.lowercased(), "computedname", "name":
        return .computedName
    case "computednamewithvalue", "namewithvalue":
        return .computedNameWithValue
    default:
        return .generic(rawKey)
    }
}

private struct CriterionContext {
    let element: Element
    let expectedValue: String
    let matchType: JSONPathHintComponent.MatchType
    let elementDescriptionForLog: String
}

extension CriterionContext {
    fileprivate func matchRole() -> Bool {
        matchRoleAttribute(
            element: self.element,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchSubrole() -> Bool {
        matchSubroleAttribute(
            element: self.element,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchIdentifier() -> Bool {
        matchIdentifierAttribute(
            element: self.element,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchPid() -> Bool {
        matchPidCriterion(
            element: self.element,
            expectedValue: self.expectedValue,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchDomClassList() -> Bool {
        matchDomClassListAttribute(
            element: self.element,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchIsIgnored() -> Bool {
        matchIsIgnoredCriterion(
            element: self.element,
            expectedValue: self.expectedValue,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchComputedName() -> Bool {
        matchComputedNameAttributes(
            element: self.element,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            attributeName: AXMiscConstants.computedNameAttributeKey,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }

    fileprivate func matchComputedNameWithValue() -> Bool {
        matchComputedNameAttributes(
            element: self.element,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            attributeName: "computedNameWithValue",
            elementDescriptionForLog: self.elementDescriptionForLog,
            includeValueInComputedName: true)
    }

    fileprivate func matchGenericAttributeValue(key: String) -> Bool {
        performGenericAttributeMatch(
            element: self.element,
            key: key,
            expectedValue: self.expectedValue,
            matchType: self.matchType,
            elementDescriptionForLog: self.elementDescriptionForLog)
    }
}

@MainActor
private func performGenericAttributeMatch(
    element: Element,
    key: String,
    expectedValue: String,
    matchType: JSONPathHintComponent.MatchType,
    elementDescriptionForLog: String) -> Bool
{
    guard let actualValueAny: Any = element.attribute(Attribute(key)) else {
        GlobalAXLogger.shared.log(
            AXLogEntry(
                level: .debug,
                message: logSegments(
                    "SC/MSC/Default: Attribute '\(key)' not found or nil on ",
                    elementDescriptionForLog,
                    ". No match.")))
        return false
    }
    let actualValueString: String
    if let str = actualValueAny as? String {
        actualValueString = str
    } else {
        actualValueString = "\(actualValueAny)"
        GlobalAXLogger.shared.log(
            AXLogEntry(
                level: .debug,
                message: logSegments(
                    [
                        "SC/MSC/Default: Attribute '\(key)' on \(elementDescriptionForLog)",
                        "was not String (type: \(type(of: actualValueAny)))",
                        "using string description: '\(actualValueString)' for comparison.",
                    ])))
    }
    GlobalAXLogger.shared.log(
        AXLogEntry(
            level: .debug,
            message: "SC/MSC/Default: Attribute '\(key)', Actual='\(actualValueString)'"))
    return compareStrings(
        actualValueString,
        expectedValue,
        matchType,
        caseSensitive: true,
        context: StringComparisonContext(
            attributeName: key,
            elementDescription: elementDescriptionForLog))
}
