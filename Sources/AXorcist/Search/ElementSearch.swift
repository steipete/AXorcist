// ElementSearch.swift - Contains search and element collection logic

import ApplicationServices
import Foundation
// GlobalAXLogger is assumed available

// JSONPathHintComponent is in Models/JSONPathHintComponent.swift

// MARK: - Main Element Finding Orchestration

/**
 Unified function to find a target element based on application, locator (criteria and/or JSON path hint).
 This is the primary entry point for handlers.
 */
@MainActor
public func findTargetElement(
    for appIdentifierOrNil: String?,
    locator: Locator,
    maxDepthForSearch: Int
) async -> (element: Element?, error: String?) {
    let appIdentifier = appIdentifierOrNil ?? AXMiscConstants.focusedApplicationKey
    
    let pathHintDebugString = locator.rootElementPathHint?.map { "(attr: \($0.attribute), val: \($0.value), depth: \($0.depth ?? -1))" }.joined(separator: "; ") ?? "nil"
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "[findTargetElement ENTRY] App=\(appIdentifier), Locator: criteria=\(locator.criteria), " +
        "jsonPathHint=[\(pathHintDebugString)]"
    ))

    guard let appElement = applicationElement(for: appIdentifier) else {
        let msg = "Application not found: \(appIdentifier)"
        await GlobalAXLogger.shared.log(AXLogEntry(level: .error, message: msg))
        return (nil, msg)
    }

    let jsonPathComponents = locator.rootElementPathHint ?? []
    let criteria = locator.criteria
    let appSpecificCriteriaKeys = ["bundleId", "application", "pid", "path"]
    let hasOnlyAppSpecificCriteria = criteria.isEmpty || criteria.keys.allSatisfy { appSpecificCriteriaKeys.contains($0) }

    if !jsonPathComponents.isEmpty && hasOnlyAppSpecificCriteria {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Using JSONPathHint primarily as criteria are app-specific or empty."))
        if let elementFromPath = await navigateToElementByJSONPathHint(
            pathHint: jsonPathComponents,
            initialSearchElement: appElement
        ) {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "findTargetElement: Found element directly via JSONPathHint: \(elementFromPath.briefDescription(option: .smart))"))
            if let descCrit = locator.descendantCriteria, !descCrit.isEmpty {
                await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Performing descendantCriteria search. DescCriteria: \(descCrit)"))
                let descLocator = Locator(criteria: descCrit)
                if let descendant = await traverseAndSearch(currentElement: elementFromPath,
                                                           locator: descLocator,
                                                           effectiveMaxDepth: maxDepthForSearch) {
                    return (descendant, nil)
                } else {
                    return (nil, "Descendant element not found matching: \(descCrit)")
                }
            }
            return (elementFromPath, nil)
        } else {
            let msg = "Element not found via JSONPathHint: [\(pathHintDebugString)]"
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: msg))
            return (nil, msg)
        }
    }

    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Proceeding with criteria-based search (JSONPathHint may refine start)."))
    if let foundElement = await findElementViaCriteriaAndJSONPathHint(
        application: appElement,
        locator: locator,
        maxDepth: maxDepthForSearch
    ) {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .info, message: "findTargetElement: Found via criteria (and/or JSONPathHint): \(foundElement.briefDescription(option: .smart))"))
        var baseElement = foundElement
        if let descCrit = locator.descendantCriteria, !descCrit.isEmpty {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "findTargetElement: Performing descendantCriteria search. DescCriteria: \(descCrit)"))
            let descLoc = Locator(criteria: descCrit)
            if let descendant = await traverseAndSearch(currentElement: baseElement,
                                                   locator: descLoc,
                                                   effectiveMaxDepth: maxDepthForSearch) {
                baseElement = descendant
            } else {
                let msg = "Descendant element not found matching: \(descCrit)"
                await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: msg))
                return (nil, msg)
            }
        }
        return (baseElement, nil)
    } else {
        let msg = "Element not found matching criteria: \(locator.criteria)"
        if !jsonPathComponents.isEmpty {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "\(msg) (JSONPathHint was: [\(pathHintDebugString)])"))
        } else {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: msg))
        }
        return (nil, msg)
    }
}

// MARK: - Core Search Logic

@MainActor
internal func navigateToElementByJSONPathHint(
    pathHint: [JSONPathHintComponent],
    initialSearchElement: Element
) async -> Element? {
    var currentElementInPath = initialSearchElement
    let pathHintDesc = pathHint.map { "(attr:\($0.attribute),val:\($0.value),d:\($0.depth ?? -1))" }.joined(separator: " -> ")
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "navigateToElementByJSONPathHint: Starting with \(pathHint.count) JSON components [\(pathHintDesc)] from " +
        "\(initialSearchElement.briefDescription(option: .smart))"
    ))

    for (index, component) in pathHint.enumerated() {
        guard let componentCriteria = component.simpleCriteria else {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "navigateToElementByJSONPathHint: Skipping component #\(index) (attr:\(component.attribute)) due to invalid/unresolved attribute type. Path broken."))
            return nil
        }
        let depthForThisStep = component.depth ?? JSONPathHintComponent.defaultDepthForSegment
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
            "navigateToElementByJSONPathHint: Processing component #\(index) {attr:\"\(component.attribute)\", val:\"\(component.value)\", depth:\(depthForThisStep)} " +
            "starting from \(currentElementInPath.briefDescription(option: .raw))."
        ))
        if let foundElementForThisStep = await findDescendantMatchingCriteria(
            startElement: currentElementInPath,
            criteria: componentCriteria,
            maxDepthForThisHintStep: depthForThisStep
        ) {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "navigateToElementByJSONPathHint: Matched component #\(index). Found: \(foundElementForThisStep.briefDescription(option: .raw)). Advancing."))
            currentElementInPath = foundElementForThisStep
        } else {
            await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "navigateToElementByJSONPathHint: Failed component #\(index) {attr:\"\(component.attribute)\", val:\"\(component.value)\"} from \(currentElementInPath.briefDescription(option: .raw)) depth \(depthForThisStep). Path broken."))
            return nil
        }
    }
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "navigateToElementByJSONPathHint: Successfully navigated all \(pathHint.count) JSON components. Final element: \(currentElementInPath.briefDescription(option: .smart))"))
    return currentElementInPath
}

@MainActor
private func findDescendantMatchingCriteria(
    startElement: Element,
    criteria: [String: String]?,
    maxDepthForThisHintStep: Int
) async -> Element? {
    guard let validCriteria = criteria, !validCriteria.isEmpty else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "findDescendantMatchingCriteria: Called with nil or empty criteria."))
        return nil
    }
    let tempLocator = Locator(criteria: validCriteria)
    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: tempLocator)
    var traversalState = TraversalState(maxDepth: maxDepthForThisHintStep, startElement: startElement)
    return await traverser.traverse(from: startElement, visitor: visitor, state: &traversalState)
}

@MainActor
private func traverseAndSearch(
    currentElement: Element,
    locator: Locator,
    effectiveMaxDepth: Int
) async -> Element? {
    if locator.criteria.isEmpty {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "traverseAndSearch: Called with empty criteria. Returning current element: \(currentElement.briefDescription(option: .smart))"))
        return currentElement 
    }
    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator)
    var traversalState = TraversalState(maxDepth: effectiveMaxDepth, startElement: currentElement)
    return await traverser.traverse(from: currentElement, visitor: visitor, state: &traversalState)
}

@MainActor
private func processPathHintAndDetermineStartElement(
    application: Element,
    locator: Locator
) async -> Element {
    guard let jsonPathComponents = locator.rootElementPathHint, !jsonPathComponents.isEmpty else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "processPathHint: No rootElementPathHint (JSON) provided or empty. Searching from app root."))
        return application
    }
    let pathHintDebug = jsonPathComponents.map { "(attr:\($0.attribute),val:\($0.value),d:\($0.depth ?? -1))" }.joined(separator: " -> ")
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "processPathHint: Starting JSON path hint navigation [\(pathHintDebug)] for search root. \(jsonPathComponents.count) components."))
    if let elementFromPathHint = await navigateToElementByJSONPathHint(
        pathHint: jsonPathComponents,
        initialSearchElement: application
    ) {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "processPathHint: JSON path hint navigation successful. New search start: \(elementFromPathHint.briefDescription(option: .smart))."))
        return elementFromPathHint
    } else {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "processPathHint: JSON path hint navigation failed [\(pathHintDebug)]. Full search will be from app root."))
        return application
    }
}

@MainActor
func findElementViaCriteriaAndJSONPathHint(
    application: Element,
    locator: Locator,
    maxDepth: Int
) async -> Element? {
    let pathHintForLog = locator.rootElementPathHint?.map { "(attr:\($0.attribute),val:\($0.value),d:\($0.depth ?? -1))" }.joined(separator: " -> ") ?? "nil"
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
        "[findElementViaCriteriaAndJSONPathHint ENTRY] AppPID: \(application.pid() ?? -1), Locator.criteria: \(locator.criteria), " +
        "JSONPathHint: [\(pathHintForLog)]"
    ))
    let searchStartElement = await processPathHintAndDetermineStartElement(application: application, locator: locator)
    if locator.criteria.isEmpty && (locator.rootElementPathHint != nil && !locator.rootElementPathHint!.isEmpty) {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[findElementViaCriteriaAndJSONPathHint] Criteria empty, JSON path hint used. Returning: \(searchStartElement.briefDescription(option: .smart))"))
        return searchStartElement
    }
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "[findElementViaCriteriaAndJSONPathHint] Search start: \(searchStartElement.briefDescription(option: .smart)). Applying criteria: \(locator.criteria)"))
    return await traverseAndSearch(
        currentElement: searchStartElement,
        locator: Locator(criteria: locator.criteria),
        effectiveMaxDepth: maxDepth
    )
}

// MARK: - Element Collection

@MainActor
internal func collectAllElements(
    from startElement: Element,
    matching locator: Locator, 
    appElementForContext: Element, 
    attributesToFetch: [String], 
    outputFormat: OutputFormat, 
    maxElements: Int?,
    maxSearchDepth: Int
) async -> [AXElementData] {
    let effectiveFilterCriteria = locator.criteria 

    let visitor = CollectAllVisitor(
        attributesToFetch: attributesToFetch,
        outputFormat: outputFormat,
        appElement: appElementForContext, 
        filterCriteria: effectiveFilterCriteria 
    )
    var traverser = TreeTraverser()
    var traversalState = TraversalState(maxDepth: maxSearchDepth, startElement: startElement)

    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CollectAll: Starting from \(startElement.briefDescription(option: .smart)), FilterCriteria: \(effectiveFilterCriteria), MaxDepth: \(maxSearchDepth)"))
    
    _ = await traverser.traverse(from: startElement, visitor: visitor, state: &traversalState)
    
    await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CollectAll: Visitor collected \(visitor.collectedElements.count) AXElementData items."))
    
    if let maxEl = maxElements, visitor.collectedElements.count > maxEl {
        await GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "CollectAll: Truncating to \(maxEl) elements."))
        return Array(visitor.collectedElements.prefix(maxEl))
    }
    return visitor.collectedElements
}

enum ElementMatchStatus {
    case fullMatch
    case partialMatchActionMissing
    case noMatch
}

@MainActor
internal func evaluateElementAgainstCriteria(
    element: Element,
    locator: Locator,
    actionToVerify: String?,
    depth: Int
) -> ElementMatchStatus {
    if !elementMatchesCriteria(element, criteria: locator.criteria, matchType: JSONPathHintComponent.MatchType.exact) {
        return .noMatch
    }

    if let actionName = actionToVerify, !actionName.isEmpty {
        if !element.isActionSupported(actionName) {
            GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: 
                "Element \(element.briefDescription()) matches criteria but is " +
                "missing required action '\(actionName)'."
            ))
            return .noMatch
        }
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element \(element.briefDescription()) matches criteria AND has required action '\(actionName)'."))
    } else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "Element \(element.briefDescription()) matches criteria. No specific action required by this check."))
    }

    return .fullMatch
}

@MainActor
public func search(element: Element,
                   locator: Locator,
                   requireAction: String?,
                   depth: Int = 0,
                   maxDepth: Int = AXMiscConstants.defaultMaxDepthSearch
) async -> Element? {
    var traverser = TreeTraverser()
    let visitor = SearchVisitor(locator: locator, requireAction: requireAction)
    var state = TraversalState(maxDepth: maxDepth, startElement: element)
    let result = await traverser.traverse(from: element, visitor: visitor, state: &state)
    return result
}

@MainActor
/* public -> internal */ internal func collectAll(
    appElement: Element,
    locator: Locator,
    currentElement: Element,
    depth: Int,
    maxDepth: Int,
    maxElements: Int?,
    visitor: CollectAllVisitor
) async -> [AXElementData]? {
    var traverser = TreeTraverser()
    var state = TraversalState(maxDepth: maxDepth, startElement: currentElement)
    _ = await traverser.traverse(from: currentElement, visitor: visitor, state: &state)
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "collectAll: Traversal complete. Collected \(visitor.collectedElements.count) elements."))
    return visitor.collectedElements
}

// Remaining functions in this file (like path navigation helpers if any outside findElementViaPathAndCriteria)
// would need similar review and refactoring if they use the old logging pattern.

// MARK: - Element Search Logic

// [REMOVED OLD findElement FUNCTION]

// MARK: - Path Navigator (Remains mostly the same, but uses TraversalContext for logging)

// [REMOVED OLD navigateToElementByPath FUNCTION]

// MARK: - Tree Traversal Utilities (SearchVisitor, TreeTraverser, TraversalState)
// SearchVisitor is now defined in TreeTraversal.swift to avoid duplication
