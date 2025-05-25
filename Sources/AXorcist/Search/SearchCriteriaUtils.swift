// SearchCriteriaUtils.swift - Utility functions for handling search criteria

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// MARK: - PathHintComponent Definition
@MainActor
public struct PathHintComponent {
    public let criteria: [String: String]
    public let originalSegment: String // Added to store the original segment

    /// Aliases mapping human-readable keys (as produced by Accessibility Inspector) to actual AX attribute names.
    private static let attributeAliases: [String: String] = [
        // Common role/title identifiers that use ':' delimiter in Inspector output
        "Role": AXAttributeNames.kAXRoleAttribute,
        "Title": AXAttributeNames.kAXTitleAttribute,
        "Subrole": AXAttributeNames.kAXSubroleAttribute,
        "Identifier": AXAttributeNames.kAXIdentifierAttribute,
        "DOMId": AXAttributeNames.kAXDOMIdentifierAttribute,
        // PID is handled specially elsewhere, keep as-is
        "PID": "PID"
    ]

    public init?(pathSegment: String) {
        self.originalSegment = pathSegment

        // First, try to parse with PathUtils.parseRichPathComponent which supports ':' delimiters
        var parsedCriteria = PathUtils.parseRichPathComponent(pathSegment)

        // Fallback – older format that uses '=' as delimiter
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

        // Apply alias mapping so that keys line up with real AX attribute names expected by the matcher.
        var mappedCriteria: [String: String] = [:]
        for (rawKey, value) in parsedCriteria {
            if let mappedKey = Self.attributeAliases[rawKey] {
                mappedCriteria[mappedKey] = value
            } else {
                mappedCriteria[rawKey] = value
            }
        }

        // If still empty after parsing/mapping, return nil so that the component is ignored by caller.
        if mappedCriteria.isEmpty {
            axWarningLog("PathHintComponent: Path segment '\(pathSegment)' produced no usable criteria after parsing.")
            return nil
        }

        self.criteria = mappedCriteria

        let critDesc = mappedCriteria
        axDebugLog("PathHintComponent initialized. Segment: '\(pathSegment)' => criteria: \(critDesc)")
    }

    // Convenience initializer if criteria is already a dictionary
    init(criteria: [String: String], originalSegment: String = "") { // Added originalSegment, default empty
        self.criteria = criteria
        self.originalSegment = originalSegment.isEmpty && !criteria.isEmpty ? "criteria_only_init" : originalSegment
    }

    // Refactored matches method
    func matches(element: Element) -> Bool {
        return criteriaMatch(element: element, criteria: self.criteria)
    }
}

// MARK: - Criteria Matching Helper
@MainActor
public func criteriaMatch(
    element: Element, 
    criteria: [String: String]?, 
    matchAll: Bool? = true,
    appProcessId: pid_t? = nil
) -> Bool {
    guard let criteria = criteria, !criteria.isEmpty else {
        return true // No criteria means an automatic match
    }

    let elementDescriptionForLog = element.briefDescription(option: .short)
    axDebugLog("criteriaMatch: Checking element [\(elementDescriptionForLog)] against criteria. Criteria count: \(criteria.count). Criteria: \(criteria)")

    for (key, expectedValue) in criteria {
        if key == AXAttributeNames.kAXRoleAttribute && expectedValue == "*" {
            axDebugLog("criteriaMatch: Wildcard for role attribute matched.")
            continue // Wildcard for role
        }

        // Special handling for PID, similar to elementMatchesAllCriteria
        if key == "PID" {
            if element.role() == AXRoleNames.kAXApplicationRole {
                axDebugLog("Element [\(elementDescriptionForLog)] is AXApplication. PID criterion '\(expectedValue)' considered met by context.")
                continue
            }
            guard let actualPid_t = element.pid() else {
                axDebugLog("Element [\(elementDescriptionForLog)] failed to provide PID. No match for key 'PID'.")
                return false
            }
            let actualPid = Int(actualPid_t)
            guard let expectedPid = Int(expectedValue) else {
                axDebugLog("Element [\(elementDescriptionForLog)] PID criteria '\(expectedValue)' is not a valid Int. No match for key 'PID'.")
                return false
            }
            if actualPid != expectedPid {
                axDebugLog("Element [\(elementDescriptionForLog)] PID [\(actualPid)] != expected [\(expectedPid)]. No match for key 'PID'.")
                return false
            }
            axDebugLog("Element [\(elementDescriptionForLog)] PID [\(actualPid)] == expected [\(expectedPid)]. Criterion met for key 'PID'.")
            continue // PID matched, move to next criterion
        }

        // Handle "IsClickable" as a computed property
        if key == "IsClickable" {
            let supportsPress = element.isActionSupported(AXActionNames.kAXPressAction)
            let expectedBoolValue = (expectedValue.lowercased() == "true")
            if supportsPress == expectedBoolValue {
                axDebugLog("Computed criteria 'IsClickable' (via AXPress support) matched: Expected '\(expectedValue)', Got '\(supportsPress)'.")
                continue
            } else {
                axDebugLog("Computed criteria 'IsClickable' (via AXPress support) mismatch: Expected '\(expectedValue)', Got '\(supportsPress)'. Element: \(elementDescriptionForLog). No match.")
                return false
            }
        }

        // For other attributes, fetch as String and perform exact match
        let fetchedAttributeValue: String? = element.attribute(Attribute(key))
        axDebugLog("criteriaMatch: For element [\(elementDescriptionForLog)], attr [\(key)], fetched value is: [\(String(describing: fetchedAttributeValue))]. Expected: [\(expectedValue)]")

        guard let actualValue = fetchedAttributeValue else {
            // If attribute is not present, it's a mismatch unless expectedValue indicates absence (e.g., "~nil" or "~empty")
            // or if a regex is used that could potentially match an empty string (though attribute must exist).
            if expectedValue.lowercased() == "~nil" {
                 axDebugLog("Element [\(elementDescriptionForLog)] lacks attribute [\(key)]. Expected '~nil'. Criterion met.")
                 continue
            }
            // If expecting a regex match, the attribute must exist.
            if expectedValue.starts(with: "~regex:") {
                 axDebugLog("Element [\(elementDescriptionForLog)] lacks attribute [\(key)] (value was nil after fetch). Expected regex match for '\(expectedValue)'. No match.")
                 return false
            }
            axDebugLog("Element [\(elementDescriptionForLog)] lacks attribute [\(key)] (value was nil after fetch). Expected '\(expectedValue)'. No match.")
            return false
        }

        // Handle ~empty explicitly, before regex, as regex could also match empty.
        if expectedValue.lowercased() == "~empty" {
            if actualValue.isEmpty {
                axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] is empty. Expected '~empty'. Criterion met.")
                continue
            } else {
                axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] is not empty. Expected '~empty'. No match.")
                return false
            }
        }

        // Regular Expression Matching
        if expectedValue.starts(with: "~regex:") {
            let pattern = String(expectedValue.dropFirst("~regex:".count))
            do {
                // Default to case-insensitive matching for UI elements, which is generally more useful.
                let regex = try NSRegularExpression(pattern: pattern, options: .caseInsensitive)
                let range = NSRange(actualValue.startIndex..<actualValue.endIndex, in: actualValue)
                if regex.firstMatch(in: actualValue, options: [], range: range) != nil {
                    axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] MATCHED regex [\(pattern)]. Criterion met.")
                    continue // Matched
                } else {
                    axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] did NOT match regex [\(pattern)]. No match.")
                    return false // Did not match
                }
            } catch {
                axErrorLog("Invalid regex pattern [\(pattern)] for key [\(key)]: \(error.localizedDescription). Treating as no match.")
                return false // Invalid regex pattern
            }
        }
        // Exact, case-sensitive match (fallback if not a special prefix)
        else if actualValue != expectedValue {
            axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] != expected [\(expectedValue)] (exact match). No match.")
            return false
        }
        axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] == expected [\(expectedValue)] (or matched regex). Criterion met.")
    }

    axDebugLog("Element [\(elementDescriptionForLog)] matches ALL criteria. Match!")
    return true
}
