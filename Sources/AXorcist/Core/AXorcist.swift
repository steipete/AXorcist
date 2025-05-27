import AppKit // For NSRunningApplication
import ApplicationServices
import Foundation

// Main class for AXorcist operations
@MainActor
public class AXorcist {
    @MainActor public init() {}

    public static let shared = AXorcist()
    private let logger = GlobalAXLogger.shared // Use the shared logger

    // Central command processing function
    public func runCommand(_ commandEnvelope: AXCommandEnvelope) -> AXResponse { // Removed async
        logger.log(AXLogEntry(level: .info, message: "AXorcist/RunCommand: ID '\(commandEnvelope.commandID)', Type: \(commandEnvelope.command.type)")) // Removed await

        let response: AXResponse
        switch commandEnvelope.command {
        case .query(let queryCommand):
            response = handleQuery(command: queryCommand, maxDepth: queryCommand.maxDepthForSearch)
        case .performAction(let actionCommand):
            response = handlePerformAction(command: actionCommand) // Removed await
        case .getAttributes(let getAttributesCommand):
            response = handleGetAttributes(command: getAttributesCommand) // Removed await
        case .describeElement(let describeCommand):
            response = handleDescribeElement(command: describeCommand) // Removed await
        case .extractText(let extractTextCommand):
            response = handleExtractText(command: extractTextCommand) // Removed await
        case .batch(let batchCommandEnvelope):
            // The batch command itself is an envelope, pass it directly to handleBatchCommands.
            response = handleBatchCommands(command: batchCommandEnvelope) // Removed await
        case .setFocusedValue(let setFocusedValueCommand):
            response = handleSetFocusedValue(command: setFocusedValueCommand) // Removed await
        case .getElementAtPoint(let getElementAtPointCommand):
            response = handleGetElementAtPoint(command: getElementAtPointCommand) // Removed await
        case .getFocusedElement(let getFocusedElementCommand):
            response = handleGetFocusedElement(command: getFocusedElementCommand) // Removed await
        case .observe(let observeCommand):
            response = handleObserve(command: observeCommand) // Removed await
        case .collectAll(let collectAllCommand):
            response = handleCollectAll(command: collectAllCommand)
            // Add other command types here
            // default:
            //     let errormsg = "AXorcist/RunCommand: Unknown command type: \(commandEnvelope.command.type)"
            //     logger.log(AXLogEntry(level: .error, message: errormsg))
            //     response = .errorResponse(message: errormsg, code: .unknownCommand)
        }

        logger.log(AXLogEntry(level: .info, message: "AXorcist/RunCommand ID '\(commandEnvelope.commandID)' completed. Status: \(response.status)")) // Removed await
        return response
    }

    // MARK: - CollectAll Handler (New)
    internal func handleCollectAll(command: CollectAllCommand) -> AXResponse {
        // Placeholder implementation - replace with actual logic
        logger.log(AXLogEntry(level: .info, message: "AXorcist/HandleCollectAll: Command received for app '\(command.appIdentifier ?? "nil")'. Not yet fully implemented."))
        // TODO: Implement actual collect all logic using command.appIdentifier, command.attributesToReturn, command.maxDepth, command.filterCriteria, command.valueFormatOption
        return .errorResponse(message: "CollectAll command not yet fully implemented.", code: .unknownCommand)
    }

    // MARK: - Logger Methods

    public func getLogs() -> [String] {
        return GlobalAXLogger.shared.getLogsAsStrings()
    }

    public func clearLogs() {
        GlobalAXLogger.shared.clearEntries()
        logger.log(AXLogEntry(level: .info, message: "AXorcist log history cleared."))
    }
}
