// CommandExecutor.swift - Executes AXORC commands

import AppKit // For NSRunningApplication
import AXorcist
import Foundation
// import AXorcist instead of AXorcistLib

// TEMPORARY TEST STRUCT - REMOVED
// struct SimpleTestResponse: Codable {
//     var message: String
//     var logs: [String]?
// }

struct CommandExecutor {

    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool // Added debugCLI flag
    ) async -> String {
        // Setup logging based on command.debugLogging (per-command debug flag)
        // The debugCLI flag (from main CLI --debug) will be used for log *inclusion in output*.
        let (initialLoggingEnabled, initialDetailLevel) = await setupLogging(for: command)

        // Defer resetting logger to initial state
        defer {
            Task { // Must be in a Task for async calls
                await GlobalAXLogger.shared.setLoggingEnabled(initialLoggingEnabled)
                await GlobalAXLogger.shared.setDetailLevel(initialDetailLevel)
            }
        }

        // Update GlobalAXLogger operation details
        await GlobalAXLogger.shared.updateOperationDetails(commandID: command.commandId, appName: command.application)

        axDebugLog("Executing command: \(command.command) (ID: \(command.commandId)), cmdDebug: \(String(describing: command.debugLogging)), cliDebug: \(debugCLI)")

        // Pass debugCLI to processCommand
        let responseString = await processCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        // Clear logs for this specific operation after processing,
        // so next command in a batch (if any) or next CLI call starts fresh for its specific logs.
        await axClearLogs()
        await GlobalAXLogger.shared.updateOperationDetails(commandID: nil, appName: nil) // Reset context

        return responseString
    }

    private static func setupLogging(for command: CommandEnvelope) async -> (Bool, AXLogDetailLevel) {
        let initialLoggingEnabled = await GlobalAXLogger.shared.isLoggingEnabled()
        let initialDetailLevel = await GlobalAXLogger.shared.getDetailLevel()

        if let cmdDebug = command.debugLogging, cmdDebug {
            await GlobalAXLogger.shared.setLoggingEnabled(true)
            await GlobalAXLogger.shared.setDetailLevel(.verbose)
        }

        return (initialLoggingEnabled, initialDetailLevel)
    }

    private static func processCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        switch command.command {
        case .performAction:
            // Pass debugCLI to handler
            return await handlePerformActionCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .getFocusedElement:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeGetFocusedElement)

        case .getAttributes:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeGetAttributes)

        case .query:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeQuery)

        case .describeElement:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeDescribeElement)

        case .extractText:
            // Pass debugCLI to handler
            return await handleSimpleCommand(command: command, axorcist: axorcist, debugCLI: debugCLI, executor: executeExtractText)

        case .collectAll:
            // For collectAll, the AXorcist library function directly returns the JSON string.
            // This function needs to be made aware of debugCLI if its *returned JSON string*
            // is to conditionally omit logs. This is a deeper change.
            // The debugCLI flag is primarily for the CommandExecutor's own response wrapping.
            // We are now modifying handleCollectAll to accept debugCLI.
            axDebugLog("CollectAll called. debugCLI=\(debugCLI). Passing to axorcist.handleCollectAll.")
            return await axorcist.handleCollectAll(
                for: command.application,
                locator: command.locator,
                pathHint: command.pathHint, // from CommandEnvelope
                maxDepth: command.maxDepth,
                requestedAttributes: command.attributes,
                outputFormat: command.outputFormat,
                commandId: command.commandId,
                debugCLI: debugCLI // Pass the flag
            )

        case .batch:
            // Pass debugCLI to handler
            return await handleBatchCommand(command: command, axorcist: axorcist, debugCLI: debugCLI)

        case .ping:
            // Pass debugCLI to handler
            return await handlePingCommand(command: command, debugCLI: debugCLI)

        case .getElementAtPoint:
            // Pass debugCLI to handler
            return await handleNotImplementedCommand(command: command, message: "getElementAtPoint command not yet implemented", debugCLI: debugCLI)
        }
    }

    private static func handlePerformActionCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        guard let actionName = command.actionName else {
            let error = "Missing actionName for performAction"
            axErrorLog(error) // Log error
            // Conditionally include logs in error response based on debugCLI
            let logsToInclude = debugCLI ? await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text, includeTimestamps: false, includeLevels: false) : nil
            let queryResponse = QueryResponse(
                success: false,
                commandId: command.commandId,
                command: command.command.rawValue,
                error: error, // This is a String, QueryResponse legacy init handles String for error
                debugLogs: logsToInclude
            )
            let jsonString = encodeToJson(queryResponse)
            let fallbackJson = """
            {"error": "Encoding error response failed"}
            """
            return jsonString ?? fallbackJson
        }

        let handlerResponse = await executePerformAction(
            command: command,
            axorcist: axorcist,
            actionName: actionName
        )
        // Pass debugCLI to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI
        )
    }

    private static func handleSimpleCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool, // Added debugCLI
        executor: (CommandEnvelope, AXorcist) async -> HandlerResponse
    ) async -> String {
        let handlerResponse = await executor(command, axorcist)
        // Pass debugCLI to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse,
            debugCLI: debugCLI
        )
    }

    private static func handleBatchCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async -> String {
        // Batch response likely needs careful handling of debugCLI for its sub-responses
        // and the overall batch response.
        // Assuming executeBatch and its encoding handle this or need similar modifications.
        // For now, passing debugCLI down.
        axDebugLog("handleBatchCommand called with debugCLI: \(debugCLI). Further impl needed for log control in batch items.")
        let batchResponse = await executeBatch(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI
        )
        // The top-level batchResponse might also need conditional logging.
        // If BatchQueryResponse has a debugLogs field:
        // var modifiedBatchResponse = batchResponse
        // if !debugCLI { modifiedBatchResponse.debugLogs = nil } // Example

        let jsonString = encodeToJson(batchResponse)
        let fallbackJson = """
        {"error": "Encoding batch response failed"}
        """
        return jsonString ?? fallbackJson
    }

    private static func handlePingCommand(command: CommandEnvelope, debugCLI: Bool) async -> String {
        axDebugLog("Ping command received. Responding with pong.")
        let pingHandlerResponse = HandlerResponse(
            data: nil,
            error: nil
        )
        // Pass debugCLI to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: pingHandlerResponse,
            debugCLI: debugCLI
        )
    }

    private static func handleNotImplementedCommand(command: CommandEnvelope, message: String, debugCLI: Bool) async -> String {
        let notImplementedResponse = HandlerResponse(
            data: nil,
            error: message
        )
        // Pass debugCLI to finalizeAndEncodeResponse
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: notImplementedResponse,
            debugCLI: debugCLI
        )
    }

    // MARK: - Command Execution Functions (Refactored: no logging params)

    private static func executePerformAction(
        command: CommandEnvelope,
        axorcist: AXorcist,
        actionName: String
    ) async -> HandlerResponse {
        guard let locator = command.locator else {
            let error = "Missing locator for performAction"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }

        // Convert path_hint from [String] to [PathHintComponent] if needed
        var pathHintComponents: [PathHintComponent]?
        if let pathHints = command.pathHint {
            pathHintComponents = []
            for hint in pathHints {
                if let component = await PathHintComponent(pathSegment: hint) {
                    pathHintComponents?.append(component)
                }
            }
        }

        return await axorcist.handlePerformAction( // This handler uses GlobalAXLogger
            for: command.application,
            locator: locator,
            actionName: actionName,
            actionValue: command.actionValue,
            pathHint: pathHintComponents,
            maxDepth: command.maxElements
        )
    }

    private static func executeGetFocusedElement(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        return await axorcist.handleGetFocusedElement( // This handler uses GlobalAXLogger
            for: command.application,
            requestedAttributes: command.attributes
        )
    }

    private static func executeGetAttributes(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        guard let locator = command.locator else {
            let error = "Missing locator for getAttributes"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        return await axorcist.handleGetAttributes( // This handler uses GlobalAXLogger
            for: command.application,
            locator: locator,
            requestedAttributes: command.attributes,
            pathHint: command.pathHint,
            maxDepth: command.maxElements,
            outputFormat: command.outputFormat
        )
    }

    private static func executeQuery(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        guard let locator = command.locator else {
            let error = "Missing locator for query"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        return await axorcist.handleQuery( // This handler uses GlobalAXLogger
            for: command.application,
            locator: locator,
            pathHint: command.pathHint,
            maxDepth: command.maxElements,
            requestedAttributes: command.attributes,
            outputFormat: command.outputFormat
        )
    }

    private static func executeDescribeElement(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        guard let locator = command.locator else {
            let error = "Missing locator for describeElement"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        return await axorcist.handleDescribeElement( // This handler uses GlobalAXLogger
            for: command.application,
            locator: locator,
            pathHint: command.pathHint,
            maxDepth: command.maxElements,
            requestedAttributes: command.attributes,
            outputFormat: command.outputFormat
        )
    }

    private static func executeExtractText(
        command: CommandEnvelope,
        axorcist: AXorcist
    ) async -> HandlerResponse {
        guard let locator = command.locator else {
            let error = "Missing locator for extractText"
            axErrorLog(error)
            return HandlerResponse(data: nil, error: error)
        }
        // Convert path_hint from [String] to [PathHintComponent] if needed
        var pathHintComponents: [PathHintComponent]?
        if let pathHints = command.pathHint {
            pathHintComponents = []
            for hint in pathHints {
                if let component = await PathHintComponent(pathSegment: hint) {
                    pathHintComponents?.append(component)
                }
            }
        }

        return await axorcist.handleExtractText( // This handler uses GlobalAXLogger
            for: command.application,
            locator: locator,
            pathHint: pathHintComponents
        )
    }

    private static func executeBatch(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool // Added debugCLI
    ) async -> BatchResponse {
        guard let subCommands = command.subCommands else {
            let error = "Missing subCommands for batch command"
            axErrorLog(error)
            // Conditionally include logs in BatchResponse for error case
            let logsToInclude = debugCLI ? await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text, includeTimestamps: false, includeLevels: false) : nil
            return BatchResponse(
                commandId: command.commandId,
                success: false,
                results: [],
                debugLogs: logsToInclude
            )
        }

        // AXorcist.handleBatchCommands was refactored to use GlobalAXLogger internally.
        // It no longer takes isDebugLoggingEnabled or currentDebugLogs.
        // It will manage its own sub-command logging context.
        let batchResults: [HandlerResponse] = await axorcist.handleBatchCommands(
            batchCommandID: command.commandId, // Passed for potential top-level logging within handler
            subCommands: subCommands
        )

        let overallSuccess = batchResults.allSatisfy { $0.error == nil }

        let queryResults = batchResults.enumerated().map { index, handlerResp -> QueryResponse in
            let subCommandId = subCommands.indices.contains(index) ? subCommands[index].commandId : "sub_cmd_id_missing"
            let subCommandType = subCommands.indices.contains(index) ? subCommands[index].command.rawValue : "sub_cmd_type_missing"

            // HandlerResponse (handlerResp) no longer has debug_logs.
            // If sub-command specific logs are needed in QueryResponse,
            // GlobalAXLogger would need a mechanism to provide logs scoped to sub-operations,
            // or QueryResponse's debug_logs field should be populated by finalizeAndEncodeResponse logic if desired.
            // For now, individual QueryResponses in batch will not have scoped logs here.
            // The top-level BatchResponse will get all logs accumulated during the batch.
            return QueryResponse(
                commandId: subCommandId,
                success: handlerResp.error == nil,
                command: subCommandType,
                handlerResponse: handlerResp, // handlerResp.data, handlerResp.error
                debugLogs: nil // No individual debug logs here for sub-commands in this structure.
                // Logs will be part of the main BatchResponse.
            )
        }

        // Conditionally include logs in the final BatchResponse
        let finalLogsToInclude = debugCLI ? await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text, includeTimestamps: false, includeLevels: false) : nil
        return BatchResponse(
            commandId: command.commandId,
            success: overallSuccess,
            results: queryResults,
            debugLogs: finalLogsToInclude // All logs from the batch operation, conditional
        )
    }

    // MARK: - Helper Functions

    private static func finalizeAndEncodeResponse(
        commandId: String,
        commandType: String,
        handlerResponse: HandlerResponse, // This is from AXorcist library
        debugCLI: Bool // Added debugCLI
    ) async -> String {
        let logsToInclude = debugCLI ? await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text, includeTimestamps: false, includeLevels: false) : nil

        // Use the specialized QueryResponse initializer that takes a HandlerResponse
        let response = QueryResponse(
            commandId: commandId,
            success: handlerResponse.error == nil, // Success is determined by error presence
            command: commandType,
            handlerResponse: handlerResponse, // Pass the whole HandlerResponse
            debugLogs: logsToInclude
        )

        let jsonString = encodeToJson(response)
        let fallbackJson = """
        {"error": "Encoding response failed"}
        """
        return jsonString ?? fallbackJson
    }

    private static func encodeToJson<T: Codable>(_ object: T) -> String? {
        let encoder = JSONEncoder()
        // encoder.outputFormatting = .prettyPrinted // Keep for debug, can be removed for prod

        do {
            let data = try encoder.encode(object)
            return String(data: data, encoding: .utf8)
        } catch {
            let errorDescription = "JSON ENCODING ERROR: \(error.localizedDescription). Details: \(error)"
            // Standard error logging for the CLI tool itself, not part of JSON response normally
            FileHandle.standardError.write(errorDescription.data(using: .utf8) ?? Data())
            axCriticalLog("JSON ENCODING ERROR: \(error.localizedDescription). Details: \(error)") // Also log to GlobalAXLogger
            return nil
        }
    }
}

// Extension to GlobalAXLogger for convenience
extension GlobalAXLogger {
    func getLogsAsStringsIfEnabled(
        format: AXLogOutputFormat,
        includeTimestamps: Bool = true,
        includeLevels: Bool = true,
        includeDetails: Bool = false,
        includeAppName: Bool = false,
        includeCommandID: Bool = false
    ) async -> [String]? {
        if await self.isLoggingEnabled() {
            return await self.getLogsAsStrings(
                format: format,
                includeTimestamps: includeTimestamps,
                includeLevels: includeLevels,
                includeDetails: includeDetails,
                includeAppName: includeAppName,
                includeCommandID: includeCommandID
            )
        }
        return nil
    }
}
