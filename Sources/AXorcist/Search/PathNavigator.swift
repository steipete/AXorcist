// PathNavigator.swift - Contains logic for navigating element hierarchies using path hints

import ApplicationServices
import Foundation

// Note: Assumes Element, PathUtils, Attribute are available.

// Helper to check if the current element matches a specific attribute-value pair
@MainActor
internal func currentElementMatchesPathComponent(
    _ element: Element,
    attributeName: String,
    expectedValue: String
) -> Bool {
    if attributeName.isEmpty { // Should not happen if parsePathComponent is robust
        axWarningLog(
            "currentElementMatchesPathComponent: attributeName is empty.",
            file: #file,
            function: #function,
            line: #line
        )
        return false
    }
    // Element.attribute uses GlobalAXLogger internally
    if let actualValue: String = element.attribute(Attribute(attributeName)) {
        if actualValue == expectedValue {
            return true
        }
    }
    return false
}

// Updated navigateToElement to prioritize children
@MainActor
internal func navigateToElement(
    from startElement: Element,
    pathHint: [String],
    maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch // Added maxDepth with a default
) -> Element? {
    var currentElement = startElement
    var currentPathSegmentForLog = ""

    for (index, pathComponentString) in pathHint.enumerated() {
        currentPathSegmentForLog += (index > 0 ? " -> " : "") + pathComponentString

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

        let (attributeName, expectedValue) = PathUtils.parsePathComponent(pathComponentString)
        guard !attributeName.isEmpty else {
            axErrorLog(
                "CRITICAL_NAV_PARSE_FAILURE_MARKER: Empty attribute name from " +
                    "pathComponentString '\(pathComponentString)'",
                file: #file,
                function: #function,
                line: #line
            )
            return nil
        }

        // Process this path component
        if let nextElement = processPathComponent(
            currentElement: currentElement,
            pathComponentString: pathComponentString,
            attributeName: attributeName,
            expectedValue: expectedValue,
            currentPathSegmentForLog: currentPathSegmentForLog
        ) {
            currentElement = nextElement
        } else {
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
    pathComponentString: String,
    attributeName: String,
    expectedValue: String,
    currentPathSegmentForLog: String
) -> Element? {
    let briefDesc = currentElement.briefDescription(option: .default)
    logPathComponentProcessing(pathComponentString: pathComponentString, briefDesc: briefDesc)

    // Priority 1: Check children
    if let matchedChild = findMatchingChild(
        currentElement: currentElement,
        attributeName: attributeName,
        expectedValue: expectedValue
    ) {
        return matchedChild
    }

    // Priority 2: If no child matched, check current element itself
    if checkCurrentElementMatch(
        currentElement: currentElement,
        attributeName: attributeName,
        expectedValue: expectedValue,
        briefDesc: briefDesc
    ) {
        return currentElement
    }

    // No match found
    logNoMatchFound(
        briefDesc: briefDesc,
        attributeName: attributeName,
        expectedValue: expectedValue,
        currentPathSegmentForLog: currentPathSegmentForLog
    )
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

// Helper to check if current element matches
@MainActor
private func checkCurrentElementMatch(
    currentElement: Element,
    attributeName: String,
    expectedValue: String,
    briefDesc: String
) -> Bool {
    let matchResult = currentElementMatchesPathComponent(
        currentElement,
        attributeName: attributeName,
        expectedValue: expectedValue
    )

    if matchResult {
        axDebugLog(
            "Current element \(briefDesc) itself matches '\(attributeName):\(expectedValue)'. " +
                "Retaining current element for this step.",
            file: #file,
            function: #function,
            line: #line
        )
    }

    return matchResult
}

// Helper to log when no match is found
@MainActor
private func logNoMatchFound(
    briefDesc: String,
    attributeName: String,
    expectedValue: String,
    currentPathSegmentForLog: String
) {
    axDebugLog(
        "Neither current element \(briefDesc) nor its children (after all checks) " +
            "matched '\(attributeName):\(expectedValue)'. " +
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
    attributeName: String,
    expectedValue: String
) -> Element? {
    guard let children = getChildrenFromElement(currentElement) else {
        return nil
    }

    logChildCount(count: children.count)

    return findMatchInChildren(
        children: children,
        attributeName: attributeName,
        expectedValue: expectedValue
    )
}

// Helper to get children from element
@MainActor
private func getChildrenFromElement(_ element: Element) -> [Element]? {
    // Element.children() is now the sole source for child elements.
    // It internally prioritizes kAXChildrenAttribute and then checks alternatives.
    // Element.children() uses GlobalAXLogger internally
    guard let children = element.children() else {
        let briefDesc = element.briefDescription(option: .default)
        axDebugLog(
            "Current element \(briefDesc) has no children from Element.children() " +
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

// Helper to find a match in children array
@MainActor
private func findMatchInChildren(
    children: [Element],
    attributeName: String,
    expectedValue: String
) -> Element? {
    for child in children {
        if let matchedChild = checkChildMatch(
            child: child,
            attributeName: attributeName,
            expectedValue: expectedValue
        ) {
            return matchedChild
        }
    }
    return nil
}

// Helper to check if a child matches
@MainActor
private func checkChildMatch(
    child: Element,
    attributeName: String,
    expectedValue: String
) -> Element? {
    let childBriefDescForLog = child.briefDescription(option: .default)

    // Check if this child matches the current path component's criteria
    // Element.attribute() uses GlobalAXLogger internally
    guard let actualValue: String = child.attribute(Attribute(attributeName)) else {
        return nil
    }

    logChildCheck(
        childDesc: childBriefDescForLog,
        attributeName: attributeName,
        actualValue: actualValue,
        expectedValue: expectedValue
    )

    if actualValue == expectedValue {
        logChildMatch(
            childDesc: childBriefDescForLog,
            attributeName: attributeName,
            expectedValue: expectedValue
        )
        return child
    }

    return nil
}

// Helper to log child attribute check
@MainActor
private func logChildCheck(
    childDesc: String,
    attributeName: String,
    actualValue: String,
    expectedValue: String
) {
    axDebugLog(
        "  [Nav Child Check] Child: \(childDesc), " +
            "Attribute '\(attributeName)': [\(actualValue)] (Expected: [\(expectedValue)])",
        file: #file,
        function: #function,
        line: #line
    )
}

// Helper to log child match
@MainActor
private func logChildMatch(
    childDesc: String,
    attributeName: String,
    expectedValue: String
) {
    axDebugLog(
        "Matched child (from Element.children): \(childDesc) " +
            "for '\(attributeName):\(expectedValue)'",
        file: #file,
        function: #function,
        line: #line
    )
}
