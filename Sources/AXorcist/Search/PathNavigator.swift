// PathNavigator.swift - Contains logic for navigating element hierarchies using path hints

import ApplicationServices
import Foundation
import AppKit // Added for NSRunningApplication

// Note: Assumes Element, PathUtils, Attribute are available.

// New helper to check if an element matches all given criteria
@MainActor
private func elementMatchesAllCriteria(
    _ element: Element,
    criteria: [String: String],
    forPathComponent pathComponentForLog: String // For logging
) async -> Bool {
    let elementDescriptionForLog = element.briefDescription(option: .smart)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/EMAC: Checking element [\\(elementDescriptionForLog)] against criteria for component [\\(pathComponentForLog)]. Criteria count: \\(criteria.count). Criteria: \\(criteria)"))

    guard !criteria.isEmpty else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/EMAC: Criteria IS EMPTY for path component [\\(pathComponentForLog)] on element [\\(elementDescriptionForLog)]. Returning false as no criteria to match."))
        return false // If criteria is empty, technically nothing to match against.
    }

    for (key, expectedValue) in criteria {
        if key == "PID" { // Special handling for PID
            if element.role() == AXRoleNames.kAXApplicationRole {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] is AXApplication (role check). PID criterion '\\(expectedValue)' from path component '\\(pathComponentForLog)' considered met by context."))
                continue
            }

            guard let actualPid_t = element.pid() else {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] failed to provide PID (for path component [\\(pathComponentForLog)]). No match."))
                return false
            }
            let actualPid = Int(actualPid_t)
            guard let expectedPid = Int(expectedValue) else {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] PID criteria '\\(expectedValue)' is not a valid Int (for path component [\\(pathComponentForLog)]). No match."))
                return false
            }
            if actualPid != expectedPid {
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] PID [\\(actualPid)] != expected [\\(expectedPid)] (for path component [\\(pathComponentForLog)]). No match."))
                return false
            }
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] PID [\\(actualPid)] == expected [\\(expectedPid)] (for path component [\\(pathComponentForLog)]). Criterion met."))
        } else {
            let rawAttributeValue: Any? = element.attribute(Attribute<Any>(key))

            if key == AXAttributeNames.kAXDOMClassListAttribute {
                guard let domClassListValue = rawAttributeValue else {
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] attribute [\\(key)] (DOMClassList) was nil. No match."))
                    return false
                }
                let matchFound: Bool
                if let classListArray = domClassListValue as? [String] {
                    matchFound = classListArray.contains(expectedValue)
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] DOMClassList (Array: \\(classListArray)) contains '\\(expectedValue)': \\(matchFound)."))
                } else if let classListString = domClassListValue as? String {
                    matchFound = classListString.split(separator: " ").map(String.init).contains(expectedValue)
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] DOMClassList (String: '\\(classListString)') contains '\\(expectedValue)' as whole word: \\(matchFound)."))
                } else {
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] DOMClassList attribute was neither [String] nor String. Actual type: \\(type(of: domClassListValue)). No match."))
                    return false
                }
                if !matchFound {
                    return false
                }
            } else {
                let fetchedAttributeValue: String? = element.attribute(Attribute(key))
                GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/EMAC: For element [\\(elementDescriptionForLog)], component [\\(pathComponentForLog)], attr [\\(key)], fetched value is: [\\(String(describing: fetchedAttributeValue))]."))

                guard let actualValue = fetchedAttributeValue else {
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] lacks attribute [\\(key)] (value was nil after fetch) for path component [\\(pathComponentForLog)]. No match."))
                    return false
                }
                if actualValue != expectedValue {
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] attribute [\\(key)] value [\\(actualValue)] != expected [\\(expectedValue)] (for path component [\\(pathComponentForLog)]). No match."))
                    return false
                }
            }
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] attribute [\\(key)] value matched expected [\\(expectedValue)] (for path component [\\(pathComponentForLog)]). Criterion met."))
        }
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(elementDescriptionForLog)] matches ALL criteria for path component [\\(pathComponentForLog)]. Match!"))
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

        if index == 0 && pathComponentString.lowercased() == "application" {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Path component 'application' encountered. Using current element (app root) as context for next component."))
            continue
        }

        if index >= maxDepth {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Navigation aborted: Path hint index \\(index) reached maxDepth \\(maxDepth). Path so far: \\(currentPathSegmentForLog)"))
            return nil
        }

        let criteriaToMatch = PathUtils.parseRichPathComponent(pathComponentString)
        guard !criteriaToMatch.isEmpty else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: "CRITICAL_NAV_PARSE_FAILURE_MARKER: Empty or unparsable criteria from pathComponentString '\\(pathComponentString)'"))
            return nil
        }

        if let nextElement = await processPathComponent(
            currentElement: currentElement,
            pathComponentString: pathComponentString,
            criteriaToMatch: criteriaToMatch,
            currentPathSegmentForLog: currentPathSegmentForLog
        ) {
            currentElement = nextElement
        } else {
            return nil
        }
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Navigation successful. Final element: \\(currentElement.briefDescription(option: .smart))"))
    return currentElement
}

@MainActor
private func processPathComponent(
    currentElement: Element,
    pathComponentString: String,
    criteriaToMatch: [String: String],
    currentPathSegmentForLog: String
) async -> Element? {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC_DIRECT_LOG: Entered for \\(pathComponentString)"))

    var stepCounter = 0
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). Before briefDesc."))
    stepCounter += 1
    let briefDesc = currentElement.briefDescription(option: .smart)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). Before logPathComponentProcessing. BriefDesc: \\(briefDesc)"))
    stepCounter += 1
    logPathComponentProcessing(pathComponentString: pathComponentString, briefDesc: briefDesc)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). After logPathComponentProcessing. Before PRE-CALL FMIC."))
    stepCounter += 1

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: PRE-CALL FMIC"))

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). After PRE-CALL FMIC. Before findMatchingChild call."))
    stepCounter += 1

    if let matchedChild = await findMatchingChild(
        currentElement: currentElement,
        criteriaToMatch: criteriaToMatch,
        pathComponentForLog: pathComponentString
    ) {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). findMatchingChild returned non-nil."))
        return matchedChild
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). findMatchingChild returned nil. Before elementMatchesAllCriteria."))
    stepCounter += 1

    if await elementMatchesAllCriteria(currentElement, criteria: criteriaToMatch, forPathComponent: pathComponentString) {
         GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Current element \\(briefDesc) itself matches component '\\(pathComponentString)'. Retaining current element for this step."))
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). elementMatchesAllCriteria on currentElement was true."))
        return currentElement
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). elementMatchesAllCriteria on currentElement was false. Before logNoMatchFound."))
    stepCounter += 1

    logNoMatchFound(
        briefDesc: briefDesc,
        pathComponentString: pathComponentString,
        currentPathSegmentForLog: currentPathSegmentForLog
    )
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \\(stepCounter). After logNoMatchFound. Returning nil."))
    return nil
}

@MainActor
private func logPathComponentProcessing(pathComponentString: String, briefDesc: String) {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Navigating: Processing path component '\\(pathComponentString)' from current element: \\(briefDesc)"))
}

@MainActor
private func logNoMatchFound(
    briefDesc: String,
    pathComponentString: String,
    currentPathSegmentForLog: String
) {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Neither current element \\(briefDesc) nor its children (after all checks) matched criteria for path component '\\(pathComponentString)'. Path: \\(currentPathSegmentForLog) // CHILD_MATCH_FAILURE_MARKER"))
}

@MainActor
private func findMatchingChild(
    currentElement: Element,
    criteriaToMatch: [String: String],
    pathComponentForLog: String
) async -> Element? {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Entered. CurrentElement: \\(currentElement.briefDescription(option: .smart)). Component: \\(pathComponentForLog)"))
    guard let children = currentElement.children() else {
        let currentElementDescForLog = currentElement.briefDescription(option: .smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(currentElementDescForLog)] has no children (returned nil for .children())."))
        return nil
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Element \\(currentElement.briefDescription(option: .smart)) has \\(children.count) children. Iterating..."))

    for child in children {
        let childDesc = child.briefDescription(option: .smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Checking child [\\(childDesc)] against criteria for component [\\(pathComponentForLog)]."))
        if await elementMatchesAllCriteria(child, criteria: criteriaToMatch, forPathComponent: pathComponentForLog) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Child [\\(childDesc)] MATCHED for path component [\\(pathComponentForLog)]."))
            return child
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Child [\\(childDesc)] did NOT match criteria for [\\(pathComponentForLog)]. Continuing."))
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: No child of \\(currentElement.briefDescription(option: .smart)) matched criteria for [\\(pathComponentForLog)]. Returning nil."))
    return nil
}

@MainActor
private func getChildrenFromElement(_ element: Element) async -> [Element]? {
    guard let children = element.children() else {
        let currentElementDescForLog = element.briefDescription(option: .smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(currentElementDescForLog)] has no children (returned nil for .children())."))
        return nil
    }
    if children.isEmpty {
         GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\\(element.briefDescription(option: .smart))] has zero children (returned empty array for .children())."))
    }
    return children
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
    let childBriefDescForLog = child.briefDescription(option: .smart)

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

// MARK: - JSON Path Hint Navigation

// Main external entry point for JSON path hint navigation
@MainActor
func navigateToElementByJSONPathHint(
    from startElement: Element,
    pathHintComponents: [JSONPathHintComponent]
) async -> Element? {
    var currentElement = startElement
    let pathDescriptionForLog = pathHintComponents.map { "\($0.attribute):\($0.value)" }.joined(separator: " -> ")
    let initialMessage = "PathNav/JSON: Starting navigation with \\(pathHintComponents.count) JSON components from \\(currentElement.briefDescription(option: .smart)). Path: \\(pathDescriptionForLog)"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: initialMessage))

    for (index, component) in pathHintComponents.enumerated() {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON: Processing component \\(index + 1)/\\(pathHintComponents.count): [\\(component.attribute):\\(component.value)] from current element [\\(currentElement.briefDescription(option: .smart))]"))

        if let nextElement = await findDescendantMatchingCriteria(
            startingFrom: currentElement,
            hintComponent: component,
            pathComponentForLog: "JSONHintStep_\\(index)_\(component.attribute)"
        ) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON: Component \\(index + 1) matched. New current element: [\\(nextElement.briefDescription(option: .smart))]"))
            currentElement = nextElement
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/JSON: Component \\(index + 1) [\\(component.attribute):\\(component.value)] did NOT match any descendant from [\\(currentElement.briefDescription(option: .smart))]. Navigation failed."))
            return nil
        }
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/JSON: Navigation successful. Final element: [\\(currentElement.briefDescription(option: .smart))]"))
    return currentElement
}

// Searches descendants of `startingFrom` (inclusive of self if depth allows) for an element matching criteria in `hintComponent`.
@MainActor
private func findDescendantMatchingCriteria(
    startingFrom element: Element,
    hintComponent: JSONPathHintComponent,
    pathComponentForLog: String // For logging, e.g., "JSONHintStep_0_ROLE"
) async -> Element? {
    let currentElementDesc = element.briefDescription(option: .smart)
    let matchTypeRawValue = hintComponent.matchType?.rawValue ?? "exact_fallback"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FindDesc: Searching for [\\(hintComponent.attribute):\\(hintComponent.value)] starting from [\\(currentElementDesc)] with depth \\(hintComponent.depth ?? -1)"))

    // Convert JSONPathHintComponent to a [String: String] criteria map
    // This uses the mapped AXAttributeName (e.g., kAXRoleAttribute)
    var criteria: [String: String] = [:]
    if let axAttr = hintComponent.axAttributeName {
        criteria[axAttr] = hintComponent.value
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: "PathNav/FindDesc: Unknown attribute type '\\(hintComponent.attribute)' in JSON hint. Cannot build criteria."))
        return nil
    }

    let maxDepthToSearch = hintComponent.depth ?? JSONPathHintComponent.defaultDepthForSegment // Use component depth or default step depth

    // Use a breadth-first or depth-first search up to maxDepthToSearch
    // For simplicity, using a recursive depth-limited search helper.
    // This helper will check the current element first, then its children, respecting depth.
    return await searchRecursiveForCriteria(
        currentElement: element,
        criteria: criteria,
        matchType: hintComponent.matchType,
        currentDepth: 0,
        maxDepth: maxDepthToSearch,
        pathComponentForLog: pathComponentForLog
    )
}

// Recursive helper for findDescendantMatchingCriteria
@MainActor
private func searchRecursiveForCriteria(
    currentElement: Element,
    criteria: [String: String],
    matchType: JSONPathHintComponent.MatchType?,
    currentDepth: Int,
    maxDepth: Int,
    pathComponentForLog: String
) async -> Element? {
    let currentElementDesc = currentElement.briefDescription(option: .smart)
    let matchTypeRawValue = matchType?.rawValue ?? "exact_fallback"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/SearchRec: Visiting [\\(currentElementDesc)] at depth \\(currentDepth) (max: \\(maxDepth)) for criteria [\\(criteria)] (match: \\(matchTypeRawValue))"))

    // Check if current element matches
    // elementMatchesAllCriteria is now synchronous
    if await elementMatchesAllCriteria(currentElement, criteria: criteria, forPathComponent: pathComponentForLog) {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/SearchRec: [\\(currentElementDesc)] MATCHED criteria at depth \\(currentDepth). PathComponent: \\(pathComponentForLog)"))
        return currentElement
    }

    // If maxDepth reached or no children, stop descent
    if currentDepth >= maxDepth {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/SearchRec: Max depth \\(maxDepth) reached for [\\(currentElementDesc)]. PathComponent: \\(pathComponentForLog). No deeper search."))
        return nil
    }

    // Element.children() is now synchronous
    guard let children = currentElement.children(), !children.isEmpty else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/SearchRec: [\\(currentElementDesc)] has no children or children array is empty. PathComponent: \\(pathComponentForLog). No deeper search."))
        return nil
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/SearchRec: [\\(currentElementDesc)] has \\(children.count) children. Iterating..."))

    for child in children {
        // searchRecursiveForCriteria is now synchronous
        if let matchedElement = await searchRecursiveForCriteria(
            currentElement: child,
            criteria: criteria,
            matchType: matchType,
            currentDepth: currentDepth + 1,
            maxDepth: maxDepth,
            pathComponentForLog: pathComponentForLog
        ) {
            return matchedElement // Found in a descendant
        }
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/SearchRec: No match found in [\\(currentElementDesc)] or its descendants up to depth \\(maxDepth) for criteria. PathComponent: \\(pathComponentForLog)."))
    return nil // Not found in this branch
}

// Determines the starting element for a search based on path hints.
@MainActor
func processJSONPathHintAndDetermineStartElement(
    for appBundleID: String?,
    windowTitleHint: String?,
    pathHint: [JSONPathHintComponent]?
) async -> Element? {
    let logMessage = "PathNav/ProcJSONHint: app=\(appBundleID ?? "nil"), window=\(windowTitleHint ?? "nil"), hintCount=\(pathHint?.count ?? 0)"
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: logMessage))

    var startSearchElement: Element? = nil

    if let bundleID = appBundleID, !bundleID.isEmpty {
        // Element.application(bundleIdentifier:) is now synchronous if we recreate it or use a sync alternative
        // For now, assuming a synchronous way to get the app element:
        guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/ProcJSONHint: No running application found for bundle ID '\\(bundleID)'."))
            return nil
        }
        let appElement = Element(AXUIElementCreateApplication(runningApp.processIdentifier))
        // Basic check if appElement is valid (e.g., by trying to get its role)
        if appElement.role() == nil { // role() is sync
            GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/ProcJSONHint: Failed to create a valid application Element for PID \\(runningApp.processIdentifier) from bundleID '\\(bundleID)'. Role check failed."))
            return nil
        }
        startSearchElement = appElement
        let appDesc = startSearchElement?.briefDescription(option: .smart) ?? "nil"
        let appDescMessage = "PathNav/ProcJSONHint: Set start element to application [\\(bundleID)] - [\\(appDesc)]"
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: appDescMessage))

        if let titleHint = windowTitleHint, !titleHint.isEmpty {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/ProcJSONHint: Window title hint '\\(titleHint)' provided. Searching for window in [\\(bundleID)]."))
            // Search for the window within the application element
            // Element.windows() and Element.title() are now synchronous
            if let windows = startSearchElement?.windows() {
                var foundWindow: Element? = nil
                for window in windows {
                    if let windowTitle = window.title(), windowTitle.contains(titleHint) {
                        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/ProcJSONHint: Found matching window by title '\\(windowTitle)' (hint: '\\(titleHint)'))"))
                        foundWindow = window
                        break
                    }
                }
                if let window = foundWindow {
                    startSearchElement = window
                    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/ProcJSONHint: Updated start element to specific window [\\(window.briefDescription(option: .smart))]"))
                } else {
                    GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/ProcJSONHint: Window with title containing '\\(titleHint)' not found in application [\\(bundleID)]. "))
                    return nil // Window hint provided but not found
                }
            } else {
                GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/ProcJSONHint: Application [\\(bundleID)] has no windows or failed to retrieve them."))
                return nil // App has no windows
            }
        }
    } else {
        // No application specified, use system-wide element
        startSearchElement = Element.systemWide() // systemWide() is sync
        let systemWideDesc = startSearchElement?.briefDescription(option: .smart) ?? "nil"
        let systemWideMessage = "PathNav/ProcJSONHint: No app bundle ID. Defaulting start element to system-wide [\\(systemWideDesc)]"
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: systemWideMessage))
    }

    guard let nonNilStartElement = startSearchElement else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: "PathNav/ProcJSONHint: Could not determine a valid start search element."))
        return nil
    }

    // If there's a path hint, navigate from the determined start element
    if let hintComponents = pathHint, !hintComponents.isEmpty {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/ProcJSONHint: Path hint provided (\\(hintComponents.count) components). Navigating from [\\(nonNilStartElement.briefDescription(option: .smart))]"))
        // navigateToElementByJSONPathHint is now synchronous
        return await navigateToElementByJSONPathHint(from: nonNilStartElement, pathHintComponents: hintComponents)
    } else {
        // No path hint, so the start element (app or window or systemWide) is the target
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/ProcJSONHint: No path hint. Returning determined start element: [\\(nonNilStartElement.briefDescription(option: .smart))]"))
        return nonNilStartElement
    }
}
