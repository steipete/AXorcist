// PathNavigator.swift - Contains logic for navigating element hierarchies using path hints

import ApplicationServices
import Foundation

// Note: Assumes Element, PathUtils, Attribute are available.

// New helper to check if an element matches all given criteria
@MainActor
private func elementMatchesAllCriteria(
    _ element: Element,
    criteria: [String: String],
    forPathComponent pathComponentForLog: String // For logging
) async -> Bool {
    let elementDescriptionForLog = element.briefDescription(option: .short)
    axDebugLog("PathNav/EMAC: Checking element [\(elementDescriptionForLog)] against criteria for component [\(pathComponentForLog)]. Criteria count: \(criteria.count). Criteria: \(criteria)")

    guard !criteria.isEmpty else {
        axWarningLog("PathNav/EMAC: Criteria IS EMPTY for path component [\(pathComponentForLog)] on element [\(elementDescriptionForLog)]. Returning false as no criteria to match.")
        return false // If criteria is empty, technically nothing to match against.
    }

    for (key, expectedValue) in criteria {
        if key == "PID" { // Special handling for PID
            // If the element being checked IS the application (by its role),
            // and we're checking its PID criterion from a path hint component,
            // assume the PID matches because the app context is already established.
            if await element.role() == AXRoleNames.kAXApplicationRole {
                axDebugLog("Element [\(elementDescriptionForLog)] is AXApplication (role check). PID criterion '\(expectedValue)' from path component '\(pathComponentForLog)' considered met by context.")
                continue // Skip further PID checks for the application element itself
            }

            guard let actualPid_t = await element.pid() else {
                axDebugLog("Element [\(elementDescriptionForLog)] failed to provide PID (for path component [\(pathComponentForLog)]). No match.")
                return false
            }
            let actualPid = Int(actualPid_t)
            guard let expectedPid = Int(expectedValue) else {
                axDebugLog("Element [\(elementDescriptionForLog)] PID criteria '\(expectedValue)' is not a valid Int (for path component [\(pathComponentForLog)]). No match.")
                return false
            }
            if actualPid != expectedPid {
                axDebugLog("Element [\(elementDescriptionForLog)] PID [\(actualPid)] != expected [\(expectedPid)] (for path component [\(pathComponentForLog)]). No match.")
                return false
            }
            axDebugLog("Element [\(elementDescriptionForLog)] PID [\(actualPid)] == expected [\(expectedPid)] (for path component [\(pathComponentForLog)]). Criterion met.")
        } else { // Handle other attributes
            let fetchedAttributeValue: String? = await element.attribute(Attribute(key))
            axDebugLog("PathNav/EMAC: For element [\(elementDescriptionForLog)], component [\(pathComponentForLog)], attr [\(key)], fetched value is: [\(String(describing: fetchedAttributeValue))].")

            guard let actualValue = fetchedAttributeValue else {
                axDebugLog("Element [\(elementDescriptionForLog)] lacks attribute [\(key)] (value was nil after fetch) for path component [\(pathComponentForLog)]. No match.")
                return false
            }
            if actualValue != expectedValue {
                axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] != expected [\(expectedValue)] (for path component [\(pathComponentForLog)]). No match.")
                return false
            }
            axDebugLog("Element [\(elementDescriptionForLog)] attribute [\(key)] value [\(actualValue)] == expected [\(expectedValue)] (for path component [\(pathComponentForLog)]). Criterion met.")
        }
    }
    axDebugLog("Element [\(elementDescriptionForLog)] matches ALL criteria for path component [\(pathComponentForLog)]. Match!")
    return true
}

// Updated navigateToElement to prioritize children
@MainActor
internal func navigateToElement(
    from startElement: Element,
    pathHint: [String],
    maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch
) async -> Element? {
    var currentElement = startElement
    var currentPathSegmentForLog = ""

    for (index, pathComponentString) in pathHint.enumerated() {
        currentPathSegmentForLog += (index > 0 ? " -> " : "") + pathComponentString

        // Special handling for "application" as the first component
        // It implies the context is already the application element itself.
        if index == 0 && pathComponentString.lowercased() == "application" {
            axDebugLog("Path component 'application' encountered. Using current element (app root) as context for next component.", file: #file, function: #function, line: #line)
            // currentElement is already appElement, so just continue to the next component
            continue
        }

        if index >= maxDepth {
            axDebugLog(
                "Navigation aborted: Path hint index \(index) reached maxDepth \(maxDepth). " +
                    "Path so far: \(currentPathSegmentForLog)",
                file: #file,
                function: #function,
                line: #line
            )
            return nil
        }

        let criteriaToMatch = PathUtils.parseRichPathComponent(pathComponentString)
        guard !criteriaToMatch.isEmpty else {
            axErrorLog(
                "CRITICAL_NAV_PARSE_FAILURE_MARKER: Empty or unparsable criteria from " +
                    "pathComponentString '\(pathComponentString)'",
                file: #file,
                function: #function,
                line: #line
            )
            return nil
        }

        // Process this path component
        if let nextElement = await processPathComponent(
            currentElement: currentElement,
            pathComponentString: pathComponentString, // Still useful for logging
            criteriaToMatch: criteriaToMatch,
            currentPathSegmentForLog: currentPathSegmentForLog // Still useful for logging
        ) {
            currentElement = nextElement
        } else {
            // Log already done in processPathComponent or its callees
            return nil
        }
    }

    axDebugLog(
        "Navigation successful. Final element: \(currentElement.briefDescription(option: .default))",
        file: #file,
        function: #function,
        line: #line
    )
    return currentElement
}

// Helper function to process a single path component
@MainActor
private func processPathComponent(
    currentElement: Element,
    pathComponentString: String, // For logging
    criteriaToMatch: [String: String],
    currentPathSegmentForLog: String // For logging
) async -> Element? {
    // DIRECT LOGGING ATTEMPT
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC_DIRECT_LOG: Entered for \(pathComponentString)", file: #file, function: #function, line: Int(#line)))

    var stepCounter = 0
    axDebugLog("PathNav/PPC: Step \(stepCounter). Before briefDesc.")
    stepCounter += 1
    let briefDesc = currentElement.briefDescription(option: .default)
    axDebugLog("PathNav/PPC: Step \(stepCounter). Before logPathComponentProcessing. BriefDesc: \(briefDesc)")
    stepCounter += 1
    logPathComponentProcessing(pathComponentString: pathComponentString, briefDesc: briefDesc)
    axDebugLog("PathNav/PPC: Step \(stepCounter). After logPathComponentProcessing. Before PRE-CALL FMIC.")
    stepCounter += 1

    axDebugLog("PathNav/PPC: PRE-CALL FMIC", file: #file, function: #function, line: #line)

    axDebugLog("PathNav/PPC: Step \(stepCounter). After PRE-CALL FMIC. Before findMatchingChild call.")
    stepCounter += 1

    if let matchedChild = await findMatchingChild(
        currentElement: currentElement,
        criteriaToMatch: criteriaToMatch,
        pathComponentForLog: pathComponentString // Pass for logging inside elementMatchesAllCriteria
    ) {
        axDebugLog("PathNav/PPC: Step \(stepCounter). findMatchingChild returned non-nil.")
        return matchedChild
    }
    axDebugLog("PathNav/PPC: Step \(stepCounter). findMatchingChild returned nil. Before elementMatchesAllCriteria.")
    stepCounter += 1

    if await elementMatchesAllCriteria(currentElement, criteria: criteriaToMatch, forPathComponent: pathComponentString) {
         axDebugLog(
            "Current element \(briefDesc) itself matches component '\(pathComponentString)'. " +
                "Retaining current element for this step.",
            file: #file, function: #function, line: #line
        )
        axDebugLog("PathNav/PPC: Step \(stepCounter). elementMatchesAllCriteria on currentElement was true.")
        return currentElement
    }
    axDebugLog("PathNav/PPC: Step \(stepCounter). elementMatchesAllCriteria on currentElement was false. Before logNoMatchFound.")
    stepCounter += 1

    logNoMatchFound(
        briefDesc: briefDesc,
        pathComponentString: pathComponentString,
        currentPathSegmentForLog: currentPathSegmentForLog
    )
    axDebugLog("PathNav/PPC: Step \(stepCounter). After logNoMatchFound. Returning nil.")
    return nil
}

// Helper to log path component processing
@MainActor
private func logPathComponentProcessing(pathComponentString: String, briefDesc: String) {
    axDebugLog(
        "Navigating: Processing path component '\(pathComponentString)' " +
            "from current element: \(briefDesc)",
        file: #file,
        function: #function,
        line: #line
    )
}

// Helper to log when no match is found
@MainActor
private func logNoMatchFound(
    briefDesc: String,
    pathComponentString: String, // Changed from attributeName/expectedValue
    currentPathSegmentForLog: String
) {
    axDebugLog(
        "Neither current element \(briefDesc) nor its children (after all checks) " +
            "matched criteria for path component '\(pathComponentString)'. " +
            "Path: \(currentPathSegmentForLog) // CHILD_MATCH_FAILURE_MARKER",
        file: #file,
        function: #function,
        line: #line
    )
}

// Helper function to find a matching child element
@MainActor
private func findMatchingChild(
    currentElement: Element,
    criteriaToMatch: [String: String],
    pathComponentForLog: String // Pass for logging inside elementMatchesAllCriteria
) async -> Element? {
    axDebugLog("PathNav/FMIC: ABSOLUTE ENTRY", file: #file, function: #function, line: #line)

    axDebugLog("PathNav/FMIC: Entered function for component [\(pathComponentForLog)]. Criteria: \(criteriaToMatch)", file: #file, function: #function, line: #line)

    guard let children = await getChildrenFromElement(currentElement) else {
        return nil
    }

    if children.isEmpty {
        axDebugLog("PathNav/FMIC: Children array IS EMPTY for component [\(pathComponentForLog)]. No children to iterate.", file: #file, function: #function, line: #line)
        return nil
    }

    axDebugLog("PathNav/FMIC: Iterating \(children.count) children for component [\(pathComponentForLog)]. Criteria to match: \(criteriaToMatch)", file: #file, function: #function, line: #line)
    for (childIndex, child) in children.enumerated() {
        let childDescriptionForLog = child.briefDescription(option: .default)
        axDebugLog("PathNav/FMIC: Child [\(childIndex)]/[\(children.count - 1)]: [\(childDescriptionForLog)]. About to call EMAC for component [\(pathComponentForLog)].", file: #file, function: #function, line: #line)
        // Re-enable this check
        if await elementMatchesAllCriteria(child, criteria: criteriaToMatch, forPathComponent: pathComponentForLog) {
            axDebugLog("Matched component [\(pathComponentForLog)] to child: [\(childDescriptionForLog)]",
                       file: #file, function: #function, line: #line)
            return child
        }
    }
    axDebugLog("PathNav/FMIC: Loop finished or no match from EMAC. Returning nil.", file: #file, function: #function, line: #line)
    return nil
}

// Helper to get children from element
@MainActor
private func getChildrenFromElement(_ element: Element) async -> [Element]? {
    guard let children = await element.children() else {
        let currentElementDescForLog = element.briefDescription(option: .default)
        axDebugLog(
            "Current element [\(currentElementDescForLog)] has no children from Element.children() " +
                "or children array was nil.",
            file: #file,
            function: #function,
            line: #line
        )
        return nil
    }
    return children
}

// Helper to log child count
@MainActor
private func logChildCount(count: Int) {
    axDebugLog(
        "Child count from Element.children(): \(count)",
        file: #file,
        function: #function,
        line: #line
    )
}

// MARK: - Index-based Navigation (If still needed, would need careful review)
// The PathUtils.parseRichPathComponent currently does not produce index-based hints.
// If "@index" style hints are required, parseRichPathComponent and the matching logic
// would need to be extended. For now, focusing on attribute-based matching.

/*
    // Example of how index-based logic might be integrated if parseRichPathComponent supported it
    // (e.g., by returning a special key like "@index" in criteriaToMatch)

    // In processPathComponent, after trying findMatchingChild and elementMatchesAllCriteria(currentElement...):
    if let indexStr = criteriaToMatch["@index"], let index = Int(indexStr) {
        if let children = getChildrenFromElement(currentElement), index >= 0, index < children.count {
            let indexedChild = children[index]
            axDebugLog("Path component '\(pathComponentString)' resolved to child at index \(index): \(indexedChild.briefDescription())")
            return indexedChild
        } else {
            axDebugLog("Path component '\(pathComponentString)' (index \(index)) out of bounds for \(currentElement.briefDescription()) with \(getChildrenFromElement(currentElement)?.count ?? 0) children.")
            // logNoMatchFound would have been called if attribute matching failed before this.
            // If ONLY index was provided and it failed, this is the failure point.
            return nil
        }
    }
*/

// MARK: - Deprecated/Replaced original path navigation helpers

// The following functions were part of an older path navigation system or single-attribute matching
// and are now replaced by the richer criteria-based matching using elementMatchesAllCriteria.
// They are kept here commented out for reference during transition and can be removed later.

/*
@MainActor
internal func original_currentElementMatchesPathComponent( // Marked as original
    _ element: Element,
    attributeName: String,
    expectedValue: String
) -> Bool {
    if attributeName.isEmpty {
        axWarningLog("original_currentElementMatchesPathComponent: attributeName is empty.")
        return false
    }
    if let actualValue: String = element.attribute(Attribute(attributeName)) {
        if actualValue == expectedValue {
            return true
        }
    }
    return false
}

@MainActor
private func original_checkChildMatch( // Marked as original
    child: Element,
    attributeName: String,
    expectedValue: String
) -> Element? {
    let childBriefDescForLog = child.briefDescription(option: .default)

    guard let actualValue: String = child.attribute(Attribute(attributeName)) else {
        return nil
    }

    original_logChildCheck( // Use original log
        childDesc: childBriefDescForLog,
        attributeName: attributeName,
        actualValue: actualValue,
        expectedValue: expectedValue
    )

    if actualValue == expectedValue {
        original_logChildMatch( // Use original log
            childDesc: childBriefDescForLog,
            attributeName: attributeName,
            expectedValue: expectedValue
        )
        return child
    }
    return nil
}

@MainActor
private func original_logChildCheck( // Marked as original
    childDesc: String,
    attributeName: String,
    actualValue: String,
    expectedValue: String
) {
    let matchStatus = (actualValue == expectedValue) ? "==" : "!="
    axDebugLog(
        "Checking child: \(childDesc) | Attribute: \(attributeName) | Actual: '\(actualValue)' \(matchStatus) Expected: '\(expectedValue)'",
        file: #file,
        function: #function,
        line: #line
    )
}

@MainActor
private func original_logChildMatch( // Marked as original
    childDesc: String,
    attributeName: String,
    expectedValue: String
) {
    axDebugLog(
        "MATCHED child: \(childDesc) for \(attributeName):\(expectedValue)",
        file: #file,
        function: #function,
        line: #line
    )
}
*/
