// PathNavigator.swift - Contains logic for navigating element hierarchies using path hints

import ApplicationServices
import Foundation
import AppKit // Added for NSRunningApplication
import Logging // Import Logging

// Note: Assumes Element, PathUtils, Attribute, AXMiscConstants are available.

// Define logger for this file
private let logger = Logger(label: "AXorcist.PathNavigator")

// New helper to check if an element matches all given criteria
@MainActor
private func elementMatchesAllCriteria(
    _ element: Element,
    criteria: [String: String],
    forPathComponent pathComponentForLog: String // For logging
) -> Bool {
    let elementDescriptionForLog = element.briefDescription(option: ValueFormatOption.smart)
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/EMAC_START: Checking element [\(elementDescriptionForLog)] for component [\(pathComponentForLog)]. Criteria: \(criteria)"))

    if criteria.isEmpty {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/EMAC: Criteria empty for component [\(pathComponentForLog)]. Element [\(elementDescriptionForLog)] considered a match by default."))
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/EMAC_END: Element [\(elementDescriptionForLog)] MATCHED (empty criteria) for component [\(pathComponentForLog)]."))
        return true
    }

    for (key, expectedValue) in criteria {
        let matchTypeForKey: JSONPathHintComponent.MatchType = (key.lowercased() == AXAttributeNames.kAXDOMClassListAttribute.lowercased()) ? .contains : .exact
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/EMAC_CRITERION: Checking criterion '\(key): \(expectedValue)' (matchType: \(matchTypeForKey.rawValue)) on element [\(elementDescriptionForLog)] for component [\(pathComponentForLog)]."))

        let criterionDidMatch = matchSingleCriterion(element: element, key: key, expectedValue: expectedValue, matchType: matchTypeForKey, elementDescriptionForLog: elementDescriptionForLog)
        let message = "PathNav/EMAC_CRITERION_RESULT: Criterion '\(key): \(expectedValue)' on [\(elementDescriptionForLog)] for [\(pathComponentForLog)]: \(criterionDidMatch ? "MATCHED" : "FAILED")"
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))

        if !criterionDidMatch {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/EMAC: Element [\(elementDescriptionForLog)] FAILED to match criterion '\(key): \(expectedValue)' for component [\(pathComponentForLog)]."))
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/EMAC_END: Element [\(elementDescriptionForLog)] FAILED for component [\(pathComponentForLog)]."))
            return false
        }
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/EMAC: Element [\(elementDescriptionForLog)] successfully MATCHED ALL criteria for component [\(pathComponentForLog)]."))
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/EMAC_END: Element [\(elementDescriptionForLog)] MATCHED ALL criteria for component [\(pathComponentForLog)]."))
    return true
}

// Updated navigateToElement to prioritize children
@MainActor
internal func navigateToElement(
    from startElement: Element,
    pathHint: [String],
    maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch 
) -> Element? {
    var currentElement = startElement
    var currentPathSegmentForLog = ""

    for (index, pathComponentString) in pathHint.enumerated() {
        currentPathSegmentForLog += (index > 0 ? " -> " : "") + pathComponentString

        if index == 0 && pathComponentString.lowercased() == "application" {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Path component 'application' encountered. Using current element (app root) as context for next component."))
            continue
        }

        if index >= maxDepth {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Navigation aborted: Path hint index \(index) reached maxDepth \(maxDepth). Path so far: \(currentPathSegmentForLog)"))
            return nil
        }

        let criteriaToMatch = PathUtils.parseRichPathComponent(pathComponentString)
        guard !criteriaToMatch.isEmpty else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: "CRITICAL_NAV_PARSE_FAILURE_MARKER: Empty or unparsable criteria from pathComponentString '\(pathComponentString)'"))
            return nil
        }

        if let nextElement = processPathComponent(
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

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Navigation successful. Final element: \(currentElement.briefDescription(option: ValueFormatOption.smart))"))
    return currentElement
}

@MainActor
private func processPathComponent(
    currentElement: Element,
    pathComponentString: String,
    criteriaToMatch: [String: String],
    currentPathSegmentForLog: String
) -> Element? {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC_DIRECT_LOG: Entered for \(pathComponentString)"))

    var stepCounter = 0
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). Before briefDesc."))
    stepCounter += 1
    let briefDesc = currentElement.briefDescription(option: ValueFormatOption.smart)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). Before logPathComponentProcessing. BriefDesc: \(briefDesc)"))
    stepCounter += 1
    logPathComponentProcessing(pathComponentString: pathComponentString, briefDesc: briefDesc)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). After logPathComponentProcessing. Before PRE-CALL FMIC."))
    stepCounter += 1

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: PRE-CALL FMIC"))

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). After PRE-CALL FMIC. Before findMatchingChild call."))
    stepCounter += 1

    if let matchedChild = findMatchingChild(
        currentElement: currentElement,
        criteriaToMatch: criteriaToMatch,
        pathComponentForLog: pathComponentString
    ) {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). findMatchingChild returned non-nil."))
        return matchedChild
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). findMatchingChild returned nil. Before elementMatchesAllCriteria."))
    stepCounter += 1

    if elementMatchesAllCriteria(currentElement, criteria: criteriaToMatch, forPathComponent: pathComponentString) {
         GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Current element \(briefDesc) itself matches component '\(pathComponentString)'. Retaining current element for this step."))
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). elementMatchesAllCriteria on currentElement was true."))
        return currentElement
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). elementMatchesAllCriteria on currentElement was false. Before logNoMatchFound."))
    stepCounter += 1

    logNoMatchFound(
        briefDesc: briefDesc,
        pathComponentString: pathComponentString,
        currentPathSegmentForLog: currentPathSegmentForLog
    )
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/PPC: Step \(stepCounter). After logNoMatchFound. Returning nil."))
    return nil
}

@MainActor
private func logPathComponentProcessing(pathComponentString: String, briefDesc: String) {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Navigating: Processing path component '\(pathComponentString)' from current element: \(briefDesc)"))
}

@MainActor
private func logNoMatchFound(
    briefDesc: String,
    pathComponentString: String,
    currentPathSegmentForLog: String
) {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Neither current element \(briefDesc) nor its children (after all checks) matched criteria for path component '\(pathComponentString)'. Path: \(currentPathSegmentForLog) // CHILD_MATCH_FAILURE_MARKER"))
}

@MainActor
private func findMatchingChild(
    currentElement: Element,
    criteriaToMatch: [String: String],
    pathComponentForLog: String
) -> Element? {
    let parentElementDesc = currentElement.briefDescription(option: ValueFormatOption.smart)
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/FMC_START: Searching children of [\(parentElementDesc)] for component [\(pathComponentForLog)]. Criteria: \(criteriaToMatch)"))

    guard let children = currentElement.children() else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Element [\(parentElementDesc)] has no children (returned nil for .children())."))
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/FMC_END: No children for [\(parentElementDesc)]. Returning nil."))
        return nil
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Element \(parentElementDesc) has \(children.count) children. Iterating..."))

    if children.isEmpty {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Element \(parentElementDesc) has an empty children array."))
        GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/FMC_END: Empty children array for [\(parentElementDesc)]. Returning nil."))
        return nil
    }

    for (childIndex, child) in children.enumerated() {
        let childDesc = child.briefDescription(option: ValueFormatOption.smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC_CHILD: [Child \(childIndex + 1)/\(children.count)] Processing child [\(childDesc)] of [\(parentElementDesc)] for component [\(pathComponentForLog)]."))
        
        let childMatched = elementMatchesAllCriteria(child, criteria: criteriaToMatch, forPathComponent: pathComponentForLog)
        let message = "PathNav/FMC_CHILD_RESULT: Child [\(childDesc)] of [\(parentElementDesc)] for [\(pathComponentForLog)]: \(childMatched ? "MATCHED" : "DID NOT MATCH")"
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: message))

        if childMatched {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Child [\(childDesc)] MATCHED for path component [\(pathComponentForLog)]."))
            GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/FMC_END: Found matching child [\(childDesc)] for [\(parentElementDesc)]. Returning child."))
            return child
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: Child [\(childDesc)] did NOT match criteria for [\(pathComponentForLog)]. Continuing."))
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FMC: No child of \(parentElementDesc) matched criteria for [\(pathComponentForLog)]."))
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/FMC_END: No matching child found for [\(parentElementDesc)]. Returning nil."))
    return nil
}

@MainActor
private func getChildrenFromElement(_ element: Element) -> [Element]? {
    guard let children = element.children() else {
        let currentElementDescForLog = element.briefDescription(option: ValueFormatOption.smart)
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\(currentElementDescForLog)] has no children (returned nil for .children())."))
        return nil
    }
    if children.isEmpty {
         GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element [\(element.briefDescription(option: ValueFormatOption.smart))] has zero children (returned empty array for .children())."))
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
    if let indexStr = criteriaToMatch[\"@index\"], let index = Int(indexStr) {
        if let children = await getChildrenFromElement(currentElement), index >= 0, index < children.count { // Added await
            let indexedChild = children[index]
            await axDebugLog(\"Path component \'\\(pathComponentString)\' resolved to child at index \\(index): \\(await indexedChild.briefDescription())\") // Added await
            return indexedChild
        } else {
            await axDebugLog(\"Path component \'\\(pathComponentString)\' (index \\(index)) out of bounds for \\(await currentElement.briefDescription()) with \\(await getChildrenFromElement(currentElement)?.count ?? 0) children.\") // Added await
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
) async -> Bool { // Made async
    if attributeName.isEmpty {
        await axWarningLog(\"original_currentElementMatchesPathComponent: attributeName is empty.\") // Added await
        return false
    }
    // ... (rest of original function would need similar async/await updates for attribute access and logging) ...
}
*/


// MARK: - JSON PathHint Navigation

// Helper to convert JSONPathHintComponent.AttributeName to actual AXAttribute string
// This might be better placed in a utility struct/enum for AttributeName if it becomes complex
// For now, a simple switch based on the rawValue of the enum.
// UPDATE: This function is problematic because JSONPathHintComponent.AttributeName does not exist.
// The `attribute` in JSONPathHintComponent is already a String.
// This function might have been intended for an earlier version of JSONPathHintComponent.
// Keeping it commented out for now. If direct attribute string usage in JSONPathHintComponent is correct, this is not needed.
/*
private func jsonPathHintAttrToAXAttribute(_ attrName: JSONPathHintComponent.AttributeName) -> String {
    switch attrName {
    case .role: return AXAttributeNames.kAXRoleAttribute
    case .subrole: return AXAttributeNames.kAXSubroleAttribute
    case .identifier: return AXAttributeNames.kAXIdentifierAttribute
    case .title: return AXAttributeNames.kAXTitleAttribute
    case .value: return AXAttributeNames.kAXValueAttribute
    case .description: return AXAttributeNames.kAXDescriptionAttribute
    // Add other cases as necessary from JSONPathHintComponent.AttributeName
    default:
        // Fallback or error for unhandled cases
        // For now, using the rawValue, but this implies AttributeName has a rawValue or is a string itself.
        // This needs to be aligned with the actual definition of JSONPathHintComponent.AttributeName.
        // If attrName is already the string (e.g. "AXRole"), then this function is not needed.
        // The error "String has no member rawValue" likely points to this.
        // If JSONPathHintComponent.attribute is already a String, this function becomes:
        // private func jsonPathHintAttrToAXAttribute(_ attrName: String) -> String { return attrName }
        // ... or it's just used directly.
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "jsonPathHintAttrToAXAttribute: Unhandled or direct-use attribute name '\(attrName)'. Using rawValue if available, otherwise direct string."))
        // Assuming attrName might conform to RawRepresentable<String> if it's an enum
        // Or if it's already a string, this part is overly complex.
        if let raw = (attrName as? any RawRepresentable)?.rawValue as? String {
            return raw
        }
        return String(describing: attrName) // Fallback, likely incorrect if attrName isn't directly the string.
    }
}
*/


// Updated navigateToElementByJSONPathHint to use the new Element API and logging
@MainActor
internal func navigateToElementByJSONPathHint(
    from startElement: Element,
    jsonPathHint: [JSONPathHintComponent],
    overallMaxDepth: Int = AXMiscConstants.defaultMaxDepthSearch,
    initialPathSegmentForLog: String = "Root"
) -> Element? {
    var currentElement = startElement
    var currentPathSegmentForLog = initialPathSegmentForLog
    let pathHintCount = jsonPathHint.count

    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON_NAV_START: From [\(startElement.briefDescription(option: ValueFormatOption.smart))] with hint (count: \(pathHintCount)): \(jsonPathHint.map { $0.descriptionForLog() }.joined(separator: " -> "))"))

    for (index, pathComponent) in jsonPathHint.enumerated() {
        let componentDescForLog = pathComponent.descriptionForLog()
        currentPathSegmentForLog += (index > 0 ? " -> " : " (Start) -> ") + componentDescForLog
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON_NAV_COMPONENT [\(index + 1)/\(pathHintCount)]: Processing '\(componentDescForLog)'. Current path: [\(currentPathSegmentForLog)]"))

        let depthForThisStep = pathComponent.depth ?? AXMiscConstants.defaultMaxDepthSearchForHintStep

        if index >= overallMaxDepth {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON_NAV: Path hint index \(index) reached overallMaxDepth \(overallMaxDepth). Path so far: \(currentPathSegmentForLog)"))
            return nil
        }
        
        let attributeToMatch = pathComponent.attribute
        let valueToMatch = pathComponent.value
        let matchType = pathComponent.matchType ?? .exact

        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON_NAV_COMPONENT_DETAILS: Attribute: '\(attributeToMatch)', Value: '\(valueToMatch)', MatchType: '\(matchType.rawValue)', DepthForStep: \(depthForThisStep)"))

        let searchCriteria = [Criterion(attribute: attributeToMatch, value: valueToMatch, matchType: matchType)]
        
        let foundElement = findDescendantMatchingCriteria(
            startElement: currentElement,
            criteria: searchCriteria,
            maxDepth: depthForThisStep,
            stopAtFirstMatch: true,
            pathComponentForLog: componentDescForLog
        )

        if let nextElement = foundElement {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON_NAV_MATCH: Component '\(componentDescForLog)' matched by [\(nextElement.briefDescription(option: ValueFormatOption.smart))]. Updating current element."))
            currentElement = nextElement
        } else {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/JSON_NAV_NO_MATCH: Component '\(componentDescForLog)' did not match any element from [\(currentElement.briefDescription(option: ValueFormatOption.smart))] within depth \(depthForThisStep). Path: \(currentPathSegmentForLog)"))
            return nil
        }
    }

    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/JSON_NAV_SUCCESS: Navigation successful. Final element: [\(currentElement.briefDescription(option: ValueFormatOption.smart))] after path: [\(currentPathSegmentForLog)]"))
    return currentElement
}

@MainActor
private func findDescendantMatchingCriteria(
    startElement: Element,
    criteria: [Criterion],
    maxDepth: Int,
    stopAtFirstMatch: Bool,
    pathComponentForLog: String
) -> Element? {

    if elementMatchesAllCriteria(element: startElement, criteria: criteria) {
         GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/FDMC: Start element [\(startElement.briefDescription(option: ValueFormatOption.smart))] itself matches criteria for path component '\(pathComponentForLog)'."))
        return startElement
    }

    if maxDepth <= 0 {
        return nil
    }

    guard let children = startElement.children() else {
        return nil
    }

    for child in children {
        if let found = findDescendantMatchingCriteria(
            startElement: child,
            criteria: criteria,
            maxDepth: maxDepth - 1,
            stopAtFirstMatch: stopAtFirstMatch,
            pathComponentForLog: pathComponentForLog
        ) {
            if stopAtFirstMatch {
                return found
            }
        }
    }
    return nil
}

// MARK: - Application Root Element Navigation

@MainActor
public func getApplicationElement(for bundleIdentifier: String) -> Element? {
    guard let runningApp = NSRunningApplication.runningApplications(withBundleIdentifier: bundleIdentifier).first else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/AppEl: No running application found for bundle ID '\(bundleIdentifier)'."))
        return nil
    }
    let pid = runningApp.processIdentifier
    let appElement = Element(AXUIElementCreateApplication(pid))
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/AppEl: Obtained application element for '\(bundleIdentifier)' (PID: \(pid)): [\(appElement.briefDescription(option: ValueFormatOption.smart))]"))
    return appElement
}

@MainActor
public func getApplicationElement(for processId: pid_t) -> Element? {
    let appElement = Element(AXUIElementCreateApplication(processId))
    let bundleIdMessagePart: String
    if let runningApp = NSRunningApplication(processIdentifier: processId), let bId = runningApp.bundleIdentifier {
        bundleIdMessagePart = " (\(bId))"
    } else {
        bundleIdMessagePart = ""
    }
    GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "PathNav/AppEl: Obtained application element for PID \(processId)\(bundleIdMessagePart): [\(appElement.briefDescription(option: ValueFormatOption.smart))]"))
    return appElement
}

// MARK: - Element from Path (High-Level)

@MainActor
public func getElement(
    appIdentifier: String,
    pathHint: [Any],
    maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch
) -> Element? {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/GetEl: Attempting to get element for app '\(appIdentifier)' with path hint (count: \(pathHint.count))."))

    let startElement: Element?
    if let pid = pid_t(appIdentifier) {
        startElement = getApplicationElement(for: pid)
    } else {
        startElement = getApplicationElement(for: appIdentifier)
    }

    guard let rootElement = startElement else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/GetEl: Could not get root application element for '\(appIdentifier)'."))
        return nil
    }
    
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/GetEl: Root element for '\(appIdentifier)' is [\(rootElement.briefDescription(option: ValueFormatOption.smart))]. Processing path hint."))

    if let stringPathHint = pathHint as? [String] {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/GetEl: Interpreting path hint as [String]. Count: \(stringPathHint.count). Hint: \(stringPathHint.joined(separator: " -> "))"))
        return navigateToElement(from: rootElement, pathHint: stringPathHint, maxDepth: maxDepth)
    } else if let jsonPathHint = pathHint as? [JSONPathHintComponent] {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/GetEl: Interpreting path hint as [JSONPathHintComponent]. Count: \(jsonPathHint.count). Hint: \(jsonPathHint.map { $0.descriptionForLog() }.joined(separator: " -> "))"))
        let initialLogSegment = rootElement.role() == AXRoleNames.kAXApplicationRole ? "Application" : rootElement.briefDescription(option: ValueFormatOption.smart)
        return navigateToElementByJSONPathHint(from: rootElement, jsonPathHint: jsonPathHint, overallMaxDepth: maxDepth, initialPathSegmentForLog: initialLogSegment)
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: "PathNav/GetEl: Path hint type is not [String] or [JSONPathHintComponent]. Hint: \(pathHint). Cannot navigate."))
        return nil
    }
}

@MainActor
func findDescendantAtPath(
    currentRoot: Element,
    pathComponents: [PathStep],
    maxDepth: Int,
    debugSearch: Bool
) -> Element? {
    var currentElement = currentRoot
    logger.debug("PathNav/findDescendantAtPath: Starting path navigation. Initial root: \\(currentElement.briefDescription(option: .smart)). Path components: \\(pathComponents.count)")

    for (_, component) in pathComponents.enumerated() {
        // Log messages will use pathComponents.count if needed, index isn't critical for current logging
        logger.debug("PathNav/findDescendantAtPath: Processing component. Current: \\(currentElement.briefDescription(option: .smart))")
        
        let searchVisitor = SearchVisitor(
            criteria: component.criteria,
            matchType: component.matchType ?? .exact,
            matchAllCriteria: component.matchAllCriteria ?? true,
            stopAtFirstMatch: true,
            maxDepth: component.maxDepthForStep ?? 1
        )

        // Children of the current element are where we search for the next path component
        logger.debug("PathNav/findDescendantAtPath: [Component \\(pathComponentIndex + 1)] Current element for child search: \\(currentElement.briefDescription(option: .smart))")
        
        guard let childrenToSearch = currentElement.children(strict: false), !childrenToSearch.isEmpty else {
            logger.warning("PathNav/findDescendantAtPath: [Component \\(pathComponentIndex + 1)] No children found (or list was empty) for \\(currentElement.briefDescription(option: .smart)). Path navigation cannot proceed further down this branch.")
            return nil
        }
        logger.debug("PathNav/findDescendantAtPath: [Component \\(pathComponentIndex + 1)] Found \\(childrenToSearch.count) children to search.")

        var foundMatchForThisComponent: Element? = nil
        for child in childrenToSearch {
            searchVisitor.reset()
            traverseAndSearch(element: child, visitor: searchVisitor, currentDepth: 0, maxDepth: component.maxDepthForStep ?? 1)
            if let foundUnwrapped = searchVisitor.foundElement {
                logger.info("PathNav/findDescendantAtPath: [Component \\(pathComponentIndex + 1)] MATCHED component criteria \\(component.descriptionForLog()) on child: \\(foundUnwrapped.briefDescription(option: ValueFormatOption.smart))")
                foundMatchForThisComponent = foundUnwrapped
                break
            }
        }

        if let nextElement = foundMatchForThisComponent {
            currentElement = nextElement
            logger.debug("PathNav/findDescendantAtPath: [Component \\(pathComponentIndex + 1)] Advancing to next element: \\(currentElement.briefDescription(option: .smart))")
        } else {
            logger.warning("PathNav/findDescendantAtPath: [Component \\(pathComponentIndex + 1)] FAILED to find match for component criteria: \\(component.descriptionForLog()) within children of \\(currentElement.briefDescription(option: .smart))")
            return nil
        }
    }
    logger.info("PathNav/findDescendantAtPath: Successfully navigated full path. Final element: \\(currentElement.briefDescription(option: .smart))")
    return currentElement
}
