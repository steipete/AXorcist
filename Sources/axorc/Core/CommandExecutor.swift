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
        axorcist: AXorcist
        // debug parameter removed
    ) async -> String {
        // Setup logging
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

        axDebugLog("Executing command: \(command.command) (ID: \(command.commandId)), cmdDebug: \(String(describing: command.debugLogging))")

        let responseString = await processCommand(command: command, axorcist: axorcist)

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

    private static func processCommand(command: CommandEnvelope, axorcist: AXorcist) async -> String {
        switch command.command {
        case .performAction:
            return await handlePerformActionCommand(command: command, axorcist: axorcist)

        case .getFocusedElement:
            return await handleSimpleCommand(command: command, axorcist: axorcist, executor: executeGetFocusedElement)

        case .getAttributes:
            return await handleSimpleCommand(command: command, axorcist: axorcist, executor: executeGetAttributes)

        case .query:
            return await handleSimpleCommand(command: command, axorcist: axorcist, executor: executeQuery)

        case .describeElement:
            return await handleSimpleCommand(command: command, axorcist: axorcist, executor: executeDescribeElement)

        case .extractText:
            return await handleSimpleCommand(command: command, axorcist: axorcist, executor: executeExtractText)

        case .collectAll:
            // Directly await the call to the now async axorcist.handleCollectAll
            return await axorcist.handleCollectAll(
                for: command.application,
                locator: command.locator,
                pathHint: command.pathHint, // from CommandEnvelope
                maxDepth: command.maxDepth,
                requestedAttributes: command.attributes,
                outputFormat: command.outputFormat,
                commandId: command.commandId
            )

        case .batch:
            return await handleBatchCommand(command: command, axorcist: axorcist)

        case .ping:
            return await handlePingCommand(command: command)

        case .getElementAtPoint:
            return await handleNotImplementedCommand(command: command, message: "getElementAtPoint command not yet implemented")
        }
    }

    private static func handlePerformActionCommand(command: CommandEnvelope, axorcist: AXorcist) async -> String {
        guard let actionName = command.actionName else {
            let error = "Missing actionName for performAction"
            axErrorLog(error) // Log error
            return encodeToJson(QueryResponse(
                success: false,
                commandId: command.commandId,
                command: command.command.rawValue,
                error: error,
                debugLogs: await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text) // Get logs if enabled
            )) ?? "{\"error\": \"Encoding error response failed\"}"
        }

        let handlerResponse = await executePerformAction(
            command: command,
            axorcist: axorcist,
            actionName: actionName
        )
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse
        )
    }

    private static func handleSimpleCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        executor: (CommandEnvelope, AXorcist) async -> HandlerResponse
    ) async -> String {
        let handlerResponse = await executor(command, axorcist)
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: handlerResponse
        )
    }

    private static func handleBatchCommand(command: CommandEnvelope, axorcist: AXorcist) async -> String {
        let batchResponse = await executeBatch(
            command: command,
            axorcist: axorcist
        )
        return encodeToJson(batchResponse) ?? "{\"error\": \"Encoding batch response failed\"}"
    }

    private static func handlePingCommand(command: CommandEnvelope) async -> String {
        axDebugLog("Ping command received. Responding with pong.")
        let pingHandlerResponse = HandlerResponse(
            data: nil,
            error: nil
        )
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: pingHandlerResponse
        )
    }

    private static func handleNotImplementedCommand(command: CommandEnvelope, message: String) async -> String {
        let notImplementedResponse = HandlerResponse(
            data: nil,
            error: message
        )
        return await finalizeAndEncodeResponse(
            commandId: command.commandId,
            commandType: command.command.rawValue,
            handlerResponse: notImplementedResponse
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
        axorcist: AXorcist
        // effectiveDebugLogging and localDebugLogs removed
    ) async -> BatchResponse {
        guard let subCommands = command.subCommands else {
            let error = "Missing subCommands for batch command"
            axErrorLog(error)
            // BatchResponse itself will get logs from GlobalAXLogger if enabled
            return BatchResponse(
                commandId: command.commandId,
                success: false,
                results: [],
                debugLogs: await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text)
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

        return BatchResponse(
            commandId: command.commandId,
            success: overallSuccess,
            results: queryResults,
            debugLogs: await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text) // All logs from the batch operation
        )
    }

    // MARK: - Helper Functions

    private static func finalizeAndEncodeResponse(
        commandId: String,
        commandType: String,
        handlerResponse: HandlerResponse
        // localDebugLogs and effectiveDebugLogging removed
    ) async -> String {

        // HandlerResponse no longer contains debug_logs.
        // Get logs from GlobalAXLogger if it's enabled.
        let collectedLogs = await GlobalAXLogger.shared.getLogsAsStringsIfEnabled(format: .text)

        let queryResponse = QueryResponse(
            commandId: commandId,
            success: handlerResponse.error == nil,
            command: commandType,
            handlerResponse: handlerResponse, // contains .data and .error
            debugLogs: collectedLogs // Logs from GlobalAXLogger
        )

        return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding \(commandType) response failed\"}"
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
