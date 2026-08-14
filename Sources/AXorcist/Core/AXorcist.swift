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
        self.runCommand(commandEnvelope, traversalOptions: .snapshotDefaults())
    }

    /// Executes an accessibility command with an immutable request-scoped traversal policy.
    public func runCommand(
        _ commandEnvelope: AXCommandEnvelope,
        traversalOptions: AXTraversalOptions) -> AXResponse
    {
        self.logger.log(AXLogEntry(
            level: .info,
            message: "RunCommand: ID '\(commandEnvelope.commandID)', Type: \(commandEnvelope.command.type)"))

        let response = self.execute(
            commandEnvelope: commandEnvelope,
            traversalOptions: traversalOptions)

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
        self.handleCollectAll(command: command, traversalOptions: .snapshotDefaults())
    }

    func handleCollectAll(
        command: CollectAllCommand,
        traversalOptions _: AXTraversalOptions) -> AXResponse
    {
        self.logger.log(AXLogEntry(
            level: .info,
            message: "HandleCollectAll: Starting collection for app '\(command.appIdentifier ?? "focused")' " +
                "with maxDepth: \(command.maxDepth)"))

        let rootElement: Element
        switch resolveApplicationTarget(appIdentifier: command.appIdentifier, pid: command.pid) {
        case let .success(resolvedTarget):
            rootElement = resolvedTarget.element
        case let .failure(error):
            self.logger.log(AXLogEntry(level: .error, message: error.message))
            return error.response
        }

        let attributesToFetch = command.attributesToReturn ?? AXMiscConstants.defaultAttributesToFetch
        let collectionContext = ElementCollectionContext(
            maxDepth: command.maxDepth,
            filterCriteria: command.filterCriteria,
            attributesToFetch: attributesToFetch)
        let collectedElements = self.collectElementData(
            from: rootElement,
            context: collectionContext)

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

    private func collectElementData(
        from root: Element,
        context: ElementCollectionContext) -> [AXElementData]
    {
        var collectedElements: [AXElementData] = []
        traverseAXTree(
            from: root,
            maxDepth: context.maxDepth,
            visit: { element, _ in
                let shouldInclude = context.filterCriteria.map { criteria in
                    elementMatchesCriteria(element, criteria: criteria)
                } ?? true
                if shouldInclude {
                    collectedElements.append(buildQueryResponse(
                        element: element,
                        attributesToFetch: context.attributesToFetch,
                        includeChildrenBrief: false))
                }
                return .continue
            })
        return collectedElements
    }

    // MARK: - Observation Ownership

    func resolveObservationTarget(
        appIdentifier: String?,
        pid: Int?,
        locator: Locator,
        maxDepth: Int,
        traversalOptions: AXTraversalOptions) -> Result<Element, AXCommandTargetError>
    {
        let target: AXApplicationTarget
        do {
            target = try AXApplicationTarget(appIdentifier: appIdentifier, pid: pid)
        } catch let error as AXCommandTargetError {
            return .failure(error)
        } catch {
            return .failure(.applicationNotFound("Unable to resolve observation target."))
        }

        if let observationTargetResolver = self.observationTargetResolver {
            let result = observationTargetResolver(target.lookupIdentifier, locator, maxDepth)
            if let element = result.element {
                return .success(element)
            }
            return .failure(.elementNotFound(
                result.error ?? "Element to observe was not found in \(target.description)."))
        }
        return resolveTargetElement(
            appIdentifier: appIdentifier,
            pid: pid,
            locator: locator,
            maxDepthForSearch: maxDepth,
            traversalOptions: traversalOptions)
    }

    func subscribeToObservation(
        pid: pid_t?,
        element: Element,
        notification: AXNotification,
        handler: @escaping AXNotificationSubscriptionHandler) -> Result<SubscriptionToken, AccessibilityError>
    {
        guard let pid = pid ?? element.pid() else {
            return .failure(.observerSetupFailed(
                details: "Observed accessibility element has no owning application PID"))
        }
        let result = self.observationRegistry.subscribeProcess(
            pid: pid,
            element: element,
            notification: notification,
            handler: handler)
        if case let .success(token) = result {
            self.observationTokens.insert(token)
        }
        return result
    }

    private func execute(
        commandEnvelope: AXCommandEnvelope,
        traversalOptions: AXTraversalOptions) -> AXResponse
    {
        if let response = executeQueryRelatedCommands(commandEnvelope, traversalOptions: traversalOptions) {
            return response
        }
        if let response = executeInteractionCommands(commandEnvelope, traversalOptions: traversalOptions) {
            return response
        }
        return self.executeObserverCommands(commandEnvelope, traversalOptions: traversalOptions)
    }

    private func executeQueryRelatedCommands(
        _ envelope: AXCommandEnvelope,
        traversalOptions: AXTraversalOptions) -> AXResponse?
    {
        switch envelope.command {
        case let .query(queryCommand):
            handleQuery(
                command: queryCommand,
                maxDepth: queryCommand.maxDepthForSearch,
                traversalOptions: traversalOptions)
        case let .getAttributes(getAttributesCommand):
            handleGetAttributes(command: getAttributesCommand, traversalOptions: traversalOptions)
        case let .describeElement(describeCommand):
            handleDescribeElement(command: describeCommand, traversalOptions: traversalOptions)
        case let .collectAll(collectAllCommand):
            self.handleCollectAll(command: collectAllCommand, traversalOptions: traversalOptions)
        default:
            nil
        }
    }

    private func executeInteractionCommands(
        _ envelope: AXCommandEnvelope,
        traversalOptions: AXTraversalOptions) -> AXResponse?
    {
        switch envelope.command {
        case let .performAction(actionCommand):
            handlePerformAction(command: actionCommand, traversalOptions: traversalOptions)
        case let .extractText(extractTextCommand):
            handleExtractText(command: extractTextCommand, traversalOptions: traversalOptions)
        case let .setFocusedValue(setFocusedValueCommand):
            handleSetFocusedValue(command: setFocusedValueCommand, traversalOptions: traversalOptions)
        default:
            nil
        }
    }

    private func executeObserverCommands(
        _ envelope: AXCommandEnvelope,
        traversalOptions: AXTraversalOptions) -> AXResponse
    {
        switch envelope.command {
        case let .batch(batchCommandEnvelope):
            handleBatchCommands(command: batchCommandEnvelope, traversalOptions: traversalOptions)
        case let .getElementAtPoint(getElementAtPointCommand):
            handleGetElementAtPoint(command: getElementAtPointCommand)
        case let .getFocusedElement(getFocusedElementCommand):
            handleGetFocusedElement(command: getFocusedElementCommand)
        case let .observe(observeCommand):
            handleObserve(command: observeCommand, traversalOptions: traversalOptions)
        default:
            .errorResponse(
                message: "Unsupported command type: \(envelope.command.type)",
                code: .unknownCommand)
        }
    }

    private struct ElementCollectionContext {
        let maxDepth: Int
        let filterCriteria: [String: String]?
        let attributesToFetch: [String]
    }
}
