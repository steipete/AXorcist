// SearchCriteriaUtils.swift - Utility functions for handling search criteria

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// MARK: - PathHintComponent Definition
@MainActor
public struct PathHintComponent {
    public let criteria: [String: String]
    public let originalSegment: String // Added to store the original segment

    // Refactored initializer
    public init?(pathSegment: String) {
        self.originalSegment = pathSegment // Store original segment
        var parsedCriteria: [String: String] = [:]
        let pairs = pathSegment.split(separator: ",").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        for pair in pairs {
            let keyValue = pair.split(separator: "=", maxSplits: 1)
                .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            if keyValue.count == 2 {
                parsedCriteria[String(keyValue[0])] = String(keyValue[1])
            } else {
                axDebugLog("PathHintComponent: Invalid key-value pair: \(pair)")
            }
        }
        if parsedCriteria.isEmpty && !pathSegment.isEmpty {
            axDebugLog("PathHintComponent: Path segment \"\(pathSegment)\" parsed into empty criteria.")
        }
        self.criteria = parsedCriteria
        let criteriaForLog = self.criteria
        let segmentForLog = pathSegment
        axDebugLog("PathHintComponent initialized with criteria: \(criteriaForLog) from segment: \(segmentForLog)")
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
func criteriaMatch(element: Element, criteria: [String: String]?) -> Bool {
    guard let criteria = criteria, !criteria.isEmpty else {
        return true // No criteria means an automatic match
    }

    for (key, expectedValue) in criteria {
        if key == AXAttributeNames.kAXRoleAttribute && expectedValue == "*" { continue } // Wildcard for role

        if key == "IsClickable" { // Computed property
            let supportsPress = element.isActionSupported(AXActionNames.kAXPressAction)
            let expectedBoolValue = (expectedValue.lowercased() == "true")
            if supportsPress == expectedBoolValue {
                axDebugLog(
                    "Computed criteria 'IsClickable' (via AXPress support) matched: " +
                        "Expected '\(expectedValue)', Got '\(supportsPress)'."
                )
                continue
            } else {
                axDebugLog(
                    "Computed criteria 'IsClickable' (via AXPress support) mismatch: " +
                        "Expected '\(expectedValue)', Got '\(supportsPress)'. " +
                        "Element: \(element.briefDescription(option: .default)). No match."
                )
                return false
            }
        }

        // Removed unused variable: var attributeValueCFType: CFTypeRef?
        let rawValue = element.rawAttributeValue(named: key)

        guard let actualValueCF = rawValue else {
            axDebugLog(
                "Attribute \(key) not found or error on element " +
                    "\(element.briefDescription(option: .default)). No match."
            )
            return false
        }

        let actualValueSwift: Any? = ValueUnwrapper.unwrap(actualValueCF)
        let actualValueString = String(describing: actualValueSwift ?? "nil_after_unwrap")

        if !(actualValueString.localizedCaseInsensitiveContains(expectedValue) || actualValueString == expectedValue) {
            axDebugLog(
                "Attribute '\(key)' mismatch: Expected '\(expectedValue)', " +
                    "Got '\(actualValueString)'. " +
                    "Element: \(element.briefDescription(option: .default)). No match."
            )
            return false
        }
        axDebugLog("Attribute '\(key)' matched: Expected '\(expectedValue)', Got '\(actualValueString)'.")
    }
    axDebugLog("All criteria matched for element: \(element.briefDescription(option: .default)).")
    return true
}
