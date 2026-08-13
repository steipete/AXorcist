import AppKit // For NSRunningApplication
import ApplicationServices
import Foundation

/// The main class for AXorcist accessibility automation operations.
///
/// AXorcist provides a comprehensive interface for interacting with macOS accessibility APIs.
/// It supports querying UI elements, performing actions, extracting text, and batch operations.
///
/// ## Usage
///
/// ```swift
/// let axorcist = AXorcist.shared
/// let command = AXCommandEnvelope(commandID: "test", command: .query(queryCommand))
/// let response = axorcist.runCommand(command)
/// ```
///
/// ## Topics
///
/// ### Getting Started
/// - ``runCommand(_:)``
/// - ``shared``
///
/// ### Command Types
/// - ``AXCommandEnvelope``
/// - ``AXResponse``
@MainActor
public class AXorcist {
    typealias ObservationTargetResolver = @MainActor (
        _ appIdentifier: String,
        _ locator: Locator,
        _ maxDepth: Int) -> (element: Element?, error: String?)

    // MARK: Lifecycle

    /// Creates a new AXorcist instance.
    @MainActor public init() {
        self.observationRegistry = AXObserverCenter.shared
        self.observationTargetResolver = nil
    }

    init(
        observationRegistry: any AXObservationRegistry,
        observationTargetResolver: @escaping ObservationTargetResolver)
    {
        self.observationRegistry = observationRegistry
        self.observationTargetResolver = observationTargetResolver
    }

    deinit {
        let registry = self.observationRegistry
        let tokens = self.observationTokens
        Task { @MainActor in
            for token in tokens {
                try? registry.unsubscribe(token: token)
            }
        }
    }

    // MARK: Public

    /// The shared singleton instance of AXorcist.
    ///
    /// Use this shared instance for most accessibility operations to ensure
    /// consistent state and avoid unnecessary resource allocation.
    public static let shared = AXorcist()

    /// Executes an accessibility command and returns the response.
    ///
    /// This is the central method for all AXorcist operations. It processes
    /// various types of accessibility commands including queries, actions,
    /// attribute retrieval, and batch operations.
    ///
    /// - Parameter commandEnvelope: The command envelope containing the command to execute
    /// - Returns: An ``AXResponse`` containing the result of the operation
    ///
    /// ## Example
    ///
    /// ```swift
    /// let queryCommand = QueryCommand(
    ///     appIdentifier: "Finder",
    ///     locator: Locator(criteria: [Criterion(attribute: "AXRole", value: "AXWindow")]))
    /// let envelope = AXCommandEnvelope(
    ///     commandID: "find-window",
    ///     command: .query(queryCommand)
    /// )
    /// let response = AXorcist.shared.runCommand(envelope)
    /// ```
    public func runCommand(_ commandEnvelope: AXCommandEnvelope) -> AXResponse {
        self.logger.log(AXLogEntry(
            level: .info,
            message: "RunCommand: ID '\(commandEnvelope.commandID)', Type: \(commandEnvelope.command.type)"))

        let response = self.execute(commandEnvelope: commandEnvelope)

        self.logger.log(AXLogEntry(
            level: .info,
            message: "RunCommand ID '\(commandEnvelope.commandID)' completed. Status: \(response.status)"))
        return response
    }

    // MARK: - Logger Methods

    public func getLogs() -> [String] {
        GlobalAXLogger.shared.getLogsAsStrings()
    }

    public func clearLogs() {
        GlobalAXLogger.shared.clearEntries()
        self.logger.log(AXLogEntry(level: .info, message: "Log history cleared."))
    }

    /// Stops every accessibility observation owned by this AXorcist instance.
    public func stopObserving() {
        let tokens = self.observationTokens
        self.observationTokens.removeAll()
        for token in tokens {
            do {
                try self.observationRegistry.unsubscribe(token: token)
            } catch {
                self.logger.log(AXLogEntry(
                    level: .warning,
                    message: "Failed to stop observation token \(token.id): \(error.localizedDescription)"))
            }
        }
    }

    // MARK: Internal

    // MARK: - CollectAll Handler (New)

    func handleCollectAll(command: CollectAllCommand) -> AXResponse {
        self.logger.log(AXLogEntry(
            level: .info,
            message: "HandleCollectAll: Starting collection for app '\(command.appIdentifier ?? "focused")' " +
                "with maxDepth: \(command.maxDepth)"))

        // Find the target application element
        let rootElement: Element
        if let appId = command.appIdentifier, appId != "focused" {
            // Find specific application
            if let appPid = pid(forAppIdentifier: appId),
               let app = Element.application(for: appPid)
            {
                rootElement = app
            } else {
                let errorMessage = "HandleCollectAll: Could not find application '\(appId)'."
                self.logger.log(AXLogEntry(level: .error, message: errorMessage))
                return .errorResponse(message: errorMessage, code: .applicationNotFound)
            }
        } else {
            // Use focused application
            if let app = Element.focusedApplication() {
                rootElement = app
            } else {
                let errorMessage = "HandleCollectAll: No focused application found."
                self.logger.log(AXLogEntry(level: .error, message: errorMessage))
                return .errorResponse(message: errorMessage, code: .applicationNotFound)
            }
        }

        // Collect all elements recursively
        var collectedElements: [AXElementData] = []
        var visitedElements: Set<UInt> = []
        let attributesToFetch = command.attributesToReturn ?? AXMiscConstants.defaultAttributesToFetch
        let collectionContext = ElementCollectionContext(
            maxDepth: command.maxDepth,
            filterCriteria: command.filterCriteria,
            attributesToFetch: attributesToFetch)

        self.collectElementsRecursively(
            element: rootElement,
            currentDepth: 0,
            context: collectionContext,
            visited: &visitedElements,
            collectedElements: &collectedElements)

        self.logger.log(AXLogEntry(
            level: .info,
            message: "HandleCollectAll: Collected \(collectedElements.count) elements"))

        return .successResponse(payload: AnyCodable([
            "elements": collectedElements,
            "count": collectedElements.count,
        ]))
    }

    // MARK: Private

    private let logger = GlobalAXLogger.shared // Use the shared logger
    private let observationRegistry: any AXObservationRegistry
    private let observationTargetResolver: ObservationTargetResolver?
    private var observationTokens: Set<SubscriptionToken> = []

    // MARK: - Observation Ownership

    func resolveObservationTarget(
        appIdentifier: String,
        locator: Locator,
        maxDepth: Int) -> (element: Element?, error: String?)
    {
        if let observationTargetResolver = self.observationTargetResolver {
            return observationTargetResolver(appIdentifier, locator, maxDepth)
        }
        return findTargetElement(
            for: appIdentifier,
            locator: locator,
            maxDepthForSearch: maxDepth)
    }

    func subscribeToObservation(
        pid: pid_t?,
        element: Element,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        let result = self.observationRegistry.subscribe(
            pid: pid,
            element: element,
            notification: notification,
            handler: handler)
        if case let .success(token) = result {
            self.observationTokens.insert(token)
        }
        return result
    }

    private func execute(commandEnvelope: AXCommandEnvelope) -> AXResponse {
        if let response = executeQueryRelatedCommands(commandEnvelope) {
            return response
        }
        if let response = executeInteractionCommands(commandEnvelope) {
            return response
        }
        return self.executeObserverCommands(commandEnvelope)
    }

    private func executeQueryRelatedCommands(_ envelope: AXCommandEnvelope) -> AXResponse? {
        switch envelope.command {
        case let .query(queryCommand):
            handleQuery(command: queryCommand, maxDepth: queryCommand.maxDepthForSearch)
        case let .getAttributes(getAttributesCommand):
            handleGetAttributes(command: getAttributesCommand)
        case let .describeElement(describeCommand):
            handleDescribeElement(command: describeCommand)
        case let .collectAll(collectAllCommand):
            self.handleCollectAll(command: collectAllCommand)
        default:
            nil
        }
    }

    private func executeInteractionCommands(_ envelope: AXCommandEnvelope) -> AXResponse? {
        switch envelope.command {
        case let .performAction(actionCommand):
            handlePerformAction(command: actionCommand)
        case let .extractText(extractTextCommand):
            handleExtractText(command: extractTextCommand)
        case let .setFocusedValue(setFocusedValueCommand):
            handleSetFocusedValue(command: setFocusedValueCommand)
        default:
            nil
        }
    }

    private func executeObserverCommands(_ envelope: AXCommandEnvelope) -> AXResponse {
        switch envelope.command {
        case let .batch(batchCommandEnvelope):
            handleBatchCommands(command: batchCommandEnvelope)
        case let .getElementAtPoint(getElementAtPointCommand):
            handleGetElementAtPoint(command: getElementAtPointCommand)
        case let .getFocusedElement(getFocusedElementCommand):
            handleGetFocusedElement(command: getFocusedElementCommand)
        case let .observe(observeCommand):
            handleObserve(command: observeCommand)
        default:
            .errorResponse(
                message: "Unsupported command type: \(envelope.command.type)",
                code: .unknownCommand)
        }
    }

    private func collectElementsRecursively(
        element: Element,
        currentDepth: Int,
        context: ElementCollectionContext,
        visited: inout Set<UInt>,
        collectedElements: inout [AXElementData])
    {
        // Check depth limit
        guard currentDepth <= context.maxDepth else { return }

        // Prevent infinite loops caused by cyclic AX hierarchies (Window → App → Window …)
        let hashValue = CFHash(element.underlyingElement)
        guard visited.insert(hashValue).inserted else { return }

        // A filter controls which elements are returned, not which branches are traversed.
        // Descendants can match even when their parent does not.
        let shouldInclude = context.filterCriteria.map { criteria in
            elementMatchesCriteria(element, criteria: criteria)
        } ?? true
        if shouldInclude {
            let elementData = buildQueryResponse(
                element: element,
                attributesToFetch: context.attributesToFetch,
                includeChildrenBrief: false)
            collectedElements.append(elementData)
        }

        // Recursively collect children
        if let children = element.children() {
            for child in children {
                self.collectElementsRecursively(
                    element: child,
                    currentDepth: currentDepth + 1,
                    context: context,
                    visited: &visited,
                    collectedElements: &collectedElements)
            }
        }
    }

    private struct ElementCollectionContext {
        let maxDepth: Int
        let filterCriteria: [String: String]?
        let attributesToFetch: [String]
    }
}
