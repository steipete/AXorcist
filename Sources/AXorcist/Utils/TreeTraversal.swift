// TreeTraversal.swift - Unified accessibility tree traversal with cycle detection

import ApplicationServices
import Foundation

// MARK: - Core Traversal Types & Protocols

public enum TraversalAction {
    case continue_
    case found(Element)
    case stop
}

public protocol TreeVisitor {
    // Visit methods might need to be async if they perform async operations
    // or be marked with @MainActor if they interact with UI elements directly
    @MainActor func visit(element: Element, depth: Int, context: inout TraversalContext) -> TraversalAction
}

public struct TraversalContext {
    public let maxDepth: Int
    public let isDebugLoggingEnabled: Bool
    public var currentDebugLogs: [String]
    public let startElement: Element
    
    public init(maxDepth: Int, isDebugLoggingEnabled: Bool, currentDebugLogs: [String], startElement: Element) {
        self.maxDepth = maxDepth
        self.isDebugLoggingEnabled = isDebugLoggingEnabled
        self.currentDebugLogs = currentDebugLogs
        self.startElement = startElement
    }
}

// This is the actual data structure that CollectAllVisitor.collectedElements will contain.
// Moved here from CollectAllHandler as it's part of the traversal output.
public struct AXElementData: Codable {
    public var path: [String]? 
    public var attributes: [String: AnyCodable] 
    public var role: String?
    public var computedName: String?
}


// MARK: - Unified Tree Traverser

@MainActor
public struct TreeTraverser {
    private var visitedElements: Set<Element> = []
    
    public init() {}
    
    public mutating func traverse(from element: Element, visitor: TreeVisitor, context: inout TraversalContext) -> Element? {
        visitedElements.removeAll() 
        return _traverse(currentElement: element, depth: 0, visitor: visitor, context: &context)
    }

    private mutating func _traverse(currentElement: Element, depth: Int, visitor: TreeVisitor, context: inout TraversalContext) -> Element? {
        if depth > context.maxDepth {
            dLog("Max depth (\(context.maxDepth)) reached at \(currentElement.briefDescriptionForDebug(context: &context))", context: &context)
            return nil
        }

        if visitedElements.contains(currentElement) {
            dLog("Cycle detected at \(currentElement.briefDescriptionForDebug(context: &context)). Skipping.", context: &context)
            return nil
        }
        visitedElements.insert(currentElement)
        dLog("Visiting \(currentElement.briefDescriptionForDebug(context: &context)) at depth \(depth)", context: &context)

        // Since visitor.visit is @MainActor, this call is fine from @MainActor _traverse
        switch visitor.visit(element: currentElement, depth: depth, context: &context) {
            case .found(let foundElement):
                dLog("Element found by visitor: \(foundElement.briefDescriptionForDebug(context: &context))", context: &context)
                return foundElement
            case .stop:
                dLog("Traversal stopped by visitor at \(currentElement.briefDescriptionForDebug(context: &context))", context: &context)
                return nil
            case .continue_:
                break 
        }

        // Element.children is @MainActor, so this call is fine
        guard let children = currentElement.children(isDebugLoggingEnabled: context.isDebugLoggingEnabled, currentDebugLogs: &context.currentDebugLogs) else {
            dLog("No children for \(currentElement.briefDescriptionForDebug(context: &context)) or error fetching them.", context: &context)
            return nil
        }

        for child in children {
            if let found = _traverse(currentElement: child, depth: depth + 1, visitor: visitor, context: &context) {
                return found
            }
        }
        return nil
    }
}

// MARK: - Visitor Implementations

@MainActor // Ensures all methods in this class, including visit, are on the main actor
public class CollectAllVisitor: TreeVisitor {
    private let attributesToFetch: [String]
    private let outputFormat: OutputFormat // Keep for potential future use in formatting
    private let appElement: Element 
    public var collectedElements: [AXElementData] = []

    public init(attributesToFetch: [String], outputFormat: OutputFormat, appElement: Element) {
        self.attributesToFetch = attributesToFetch
        self.outputFormat = outputFormat
        self.appElement = appElement
    }

    // visit is implicitly @MainActor due to class annotation
    public func visit(element: Element, depth: Int, context: inout TraversalContext) -> TraversalAction {
        var tempDebugLogsForAttributeFetching: [String] = [] 
        // getElementAttributes is @MainActor
        let fetchedAttrs = getElementAttributes(
            element,
            requestedAttributes: attributesToFetch,
            forMultiDefault: true,
            targetRole: nil, 
            outputFormat: outputFormat, 
            isDebugLoggingEnabled: context.isDebugLoggingEnabled,
            currentDebugLogs: &tempDebugLogsForAttributeFetching 
        )
        context.currentDebugLogs.append(contentsOf: tempDebugLogsForAttributeFetching)

        // Element methods like generatePathArray, role, computedName are @MainActor
        let elementPath = element.generatePathArray(upTo: appElement, isDebugLoggingEnabled: context.isDebugLoggingEnabled, currentDebugLogs: &context.currentDebugLogs)

        let elementData = AXElementData(
            path: elementPath,
            attributes: fetchedAttrs,
            role: element.role(isDebugLoggingEnabled: context.isDebugLoggingEnabled, currentDebugLogs: &context.currentDebugLogs),
            computedName: element.computedName(isDebugLoggingEnabled: context.isDebugLoggingEnabled, currentDebugLogs: &context.currentDebugLogs)
        )
        collectedElements.append(elementData)
        return .continue_
    }
}

@MainActor // Ensures all methods in this class, including visit, are on the main actor
public class SearchVisitor: TreeVisitor {
    private let locator: Locator
    private let requireAction: String?

    public init(locator: Locator, requireAction: String? = nil) {
        self.locator = locator
        self.requireAction = requireAction
    }

    // visit is implicitly @MainActor due to class annotation
    public func visit(element: Element, depth: Int, context: inout TraversalContext) -> TraversalAction {
        // evaluateElementAgainstCriteria is @MainActor
        let matchStatus = evaluateElementAgainstCriteria(
            element: element,
            locator: locator,
            actionToVerify: requireAction ?? locator.requireAction,
            depth: depth,
            isDebugLoggingEnabled: context.isDebugLoggingEnabled,
            currentDebugLogs: &context.currentDebugLogs
        )

        switch matchStatus {
            case .fullMatch: 
                return .found(element)
            case .noMatch, .partialMatch_actionMissing: 
                return .continue_ 
            default:
                return .continue_
        }
    }
}

// MARK: - Logging Helper

@MainActor // dLog needs to be @MainActor as it calls Element.pidString which is @MainActor
func dLog(_ message: String, context: inout TraversalContext) {
    if context.isDebugLoggingEnabled {
        // AXorcist.formatDebugLogMessage is @MainActor
        // Element.pidString is @MainActor
        let logMessage = AXorcist.formatDebugLogMessage(message, applicationName: context.startElement.pidString(context: &context), commandID: nil, file: #file, function: #function, line: #line)
        context.currentDebugLogs.append(logMessage)
    }
}

// MARK: - Element Extensions for Traversal Context Logging

extension Element {
    @MainActor 
    func briefDescriptionForDebug(context: inout TraversalContext) -> String {
        return self.briefDescription(option: .default, isDebugLoggingEnabled: context.isDebugLoggingEnabled, currentDebugLogs: &context.currentDebugLogs)
    }
    
    @MainActor 
    func pidString(context: inout TraversalContext) -> String? {
        return self.pid(isDebugLoggingEnabled: context.isDebugLoggingEnabled, currentDebugLogs: &context.currentDebugLogs).map { String($0) }
    }
}

