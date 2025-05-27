// PathNavigationUtilities.swift - Utility functions for path navigation

import AppKit
import ApplicationServices
import Foundation
import Logging

// Define logger for this file
private let logger = Logger(label: "AXorcist.PathNavigationUtilities")

// MARK: - Application Element Utilities

@MainActor
public func getApplicationElement(for bundleIdentifier: String) -> Element? {
    GlobalAXLogger.shared.log(AXLogEntry(level: .debug, message: "PathNav/AppEl: Attempting to get application element for bundle identifier '\(bundleIdentifier)'."))

    guard let runningApp = NSWorkspace.shared.runningApplications.first(where: {
        $0.bundleIdentifier == bundleIdentifier
    }) else {
        GlobalAXLogger.shared.log(AXLogEntry(level: .warning, message: "PathNav/AppEl: Could not find running application with bundle identifier '\(bundleIdentifier)'."))
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

// MARK: - Path-based Search

@MainActor
func findDescendantAtPath(
    currentRoot: Element,
    pathComponents: [PathStep],
    maxDepth: Int,
    debugSearch: Bool
) -> Element? {
    var currentElement = currentRoot
    logger.debug("PathNav/findDescendantAtPath: Starting path navigation. Initial root: \(currentElement.briefDescription(option: .smart)). Path components: \(pathComponents.count)")

    for (pathComponentIndex, component) in pathComponents.enumerated() {
        logger.debug("PathNav/findDescendantAtPath: Processing component. Current: \(currentElement.briefDescription(option: .smart))")

        let searchVisitor = SearchVisitor(
            criteria: component.criteria,
            matchType: component.matchType ?? .exact,
            matchAllCriteria: component.matchAllCriteria ?? true,
            stopAtFirstMatch: true,
            maxDepth: component.maxDepthForStep ?? 1
        )

        // Children of the current element are where we search for the next path component
        logger.debug("PathNav/findDescendantAtPath: [Component \(pathComponentIndex + 1)] Current element for child search: \(currentElement.briefDescription(option: .smart))")

        guard let childrenToSearch = currentElement.children(strict: false), !childrenToSearch.isEmpty else {
            logger.warning("PathNav/findDescendantAtPath: [Component \(pathComponentIndex + 1)] No children found (or list was empty) for \(currentElement.briefDescription(option: .smart)). Path navigation cannot proceed further down this branch.")
            return nil
        }
        logger.debug("PathNav/findDescendantAtPath: [Component \(pathComponentIndex + 1)] Found \(childrenToSearch.count) children to search.")

        var foundMatchForThisComponent: Element?
        for child in childrenToSearch {
            searchVisitor.reset()
            traverseAndSearch(element: child, visitor: searchVisitor, currentDepth: 0, maxDepth: component.maxDepthForStep ?? 1)
            if let foundUnwrapped = searchVisitor.foundElement {
                logger.info("PathNav/findDescendantAtPath: [Component \(pathComponentIndex + 1)] MATCHED component criteria \(component.descriptionForLog()) on child: \(foundUnwrapped.briefDescription(option: ValueFormatOption.smart))")
                foundMatchForThisComponent = foundUnwrapped
                break
            }
        }

        if let nextElement = foundMatchForThisComponent {
            currentElement = nextElement
            logger.debug("PathNav/findDescendantAtPath: [Component \(pathComponentIndex + 1)] Advancing to next element: \(currentElement.briefDescription(option: .smart))")
        } else {
            logger.warning("PathNav/findDescendantAtPath: [Component \(pathComponentIndex + 1)] FAILED to find match for component criteria: \(component.descriptionForLog()) within children of \(currentElement.briefDescription(option: .smart))")
            return nil
        }
    }
    logger.info("PathNav/findDescendantAtPath: Successfully navigated full path. Final element: \(currentElement.briefDescription(option: .smart))")
    return currentElement
}
