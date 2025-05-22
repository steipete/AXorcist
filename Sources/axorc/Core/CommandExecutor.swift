// CommandExecutor.swift - Executes AXORC commands

import AXorcistLib
import Foundation

// TEMPORARY TEST STRUCT - REMOVED
// struct SimpleTestResponse: Codable {
//     var message: String
//     var logs: [String]?
// }

struct CommandExecutor {

    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debug: Bool
    ) async -> String {

        var localDebugLogs: [String] = []
        // Determine the effective debug logging state
        let effectiveDebugLogging = command.debug_logging ?? debug

        if effectiveDebugLogging { localDebugLogs.append("Executing command: \(command.command) (ID: \(command.command_id)), effectiveDebug: \(effectiveDebugLogging), cliDebug: \(debug), jsonDebug: \(String(describing: command.debug_logging))") }

        let ax = axorcist // Use the passed-in instance

        switch command.command {
        case .performAction:
            guard let actionName = command.action_name, let locator = command.locator else {
                let error = "Missing action_name or locator for performAction"
                localDebugLogs.append(error)
                return encodeToJson(QueryResponse(
                    success: false,
                    commandId: command.command_id,
                    command: command.command.rawValue,
                    error: error,
                    debugLogs: debug ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding error response failed\"}"
            }
            let handlerResponse: HandlerResponse = await ax.handlePerformAction(
                for: command.application,
                locator: locator,
                pathHint: command.path_hint,
                actionName: actionName,
                actionValue: command.action_value,
                maxDepth: command.max_elements,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding performAction response failed\"}"

        case .getFocusedElement:
            let handlerResponse: HandlerResponse = await ax.handleGetFocusedElement(
                for: command.application,
                requestedAttributes: command.attributes,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding getFocusedElement response failed\"}"

        case .getAttributes:
            guard let locator = command.locator else {
                let error = "Missing locator for getAttributes"
                localDebugLogs.append(error)
                return encodeToJson(QueryResponse(
                    success: false,
                    commandId: command.command_id,
                    command: command.command.rawValue,
                    error: error,
                    debugLogs: debug ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding error response failed\"}"
            }
            let handlerResponse: HandlerResponse = await ax.handleGetAttributes(
                for: command.application,
                locator: locator,
                requestedAttributes: command.attributes,
                pathHint: command.path_hint,
                maxDepth: command.max_elements,
                outputFormat: command.output_format,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding getAttributes response failed\"}"

        case .query:
            guard let locator = command.locator else {
                let error = "Missing locator for query"
                localDebugLogs.append(error)
                return encodeToJson(QueryResponse(
                    success: false,
                    commandId: command.command_id,
                    command: command.command.rawValue,
                    error: error,
                    debugLogs: debug ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding error response failed\"}"
            }
            let handlerResponse: HandlerResponse = await ax.handleQuery(
                for: command.application,
                locator: locator,
                pathHint: command.path_hint,
                maxDepth: command.max_elements,
                requestedAttributes: command.attributes,
                outputFormat: command.output_format,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding query response failed\"}"

        case .describeElement:
            guard let locator = command.locator else {
                let error = "Missing locator for describeElement"
                localDebugLogs.append(error)
                return encodeToJson(QueryResponse(
                    success: false,
                    commandId: command.command_id,
                    command: command.command.rawValue,
                    error: error,
                    debugLogs: debug ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding error response failed\"}"
            }
            let handlerResponse: HandlerResponse = await ax.handleDescribeElement(
                for: command.application,
                locator: locator,
                pathHint: command.path_hint,
                maxDepth: command.max_elements,
                outputFormat: command.output_format,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding describeElement response failed\"}"

        case .extractText:
            guard let locator = command.locator else {
                let error = "Missing locator for extractText"
                localDebugLogs.append(error)
                return encodeToJson(QueryResponse(
                    success: false,
                    commandId: command.command_id,
                    command: command.command.rawValue,
                    error: error,
                    debugLogs: debug ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding error response failed\"}"
            }
            let handlerResponse: HandlerResponse = await ax.handleExtractText(
                for: command.application,
                locator: locator,
                pathHint: command.path_hint,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding extractText response failed\"}"

        case .collectAll:
            let jsonStringResult = await ax.handleCollectAll(
                for: command.application,
                locator: command.locator,
                pathHint: command.path_hint,
                maxDepth: command.max_elements,
                requestedAttributes: command.attributes,
                outputFormat: command.output_format,
                commandId: command.command_id,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: localDebugLogs
            )
            return jsonStringResult

        case .batch:
            guard let subCommands = command.sub_commands else {
                let error = "Missing sub_commands for batch command"
                localDebugLogs.append(error)
                return encodeToJson(BatchResponse(
                    command_id: command.command_id,
                    success: false,
                    results: [],
                    error: error,
                    debug_logs: effectiveDebugLogging ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding batch error response failed\"}"
            }
            
            var batchDebugLogs = localDebugLogs
            let batchResults: [HandlerResponse] = await ax.handleBatchCommands(
                batchCommandID: command.command_id,
                subCommands: subCommands,
                isDebugLoggingEnabled: effectiveDebugLogging,
                currentDebugLogs: &batchDebugLogs
            )

            let overallSuccess = batchResults.allSatisfy { $0.error == nil }
            let batchResponse = BatchResponse(
                command_id: command.command_id,
                success: overallSuccess,
                results: batchResults,
                error: nil,
                debug_logs: effectiveDebugLogging ? batchDebugLogs : nil
            )
            return encodeToJson(batchResponse) ?? "{\"error\": \"Encoding batch response failed\"}"

        case .ping:
            if effectiveDebugLogging { localDebugLogs.append("Ping command received. Responding with pong.") }
            // Create an empty HandlerResponse for ping
            let pingHandlerResponse = HandlerResponse(
                data: nil, 
                error: nil, 
                debug_logs: nil // Ping-specific logs are already in localDebugLogs
            )
            // Construct QueryResponse using the HandlerResponse initializer
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: true, // Ping is always a success if reached
                command: command.command.rawValue,
                handlerResponse: pingHandlerResponse,
                debug_logs: effectiveDebugLogging ? localDebugLogs : nil 
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding ping response failed\"}"
        }
    }

    private static func encodeToJson<T: Codable>(_ object: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(object)
            return String(data: data, encoding: .utf8)
        } catch {
            // PRINT THE ERROR TO STDERR
            let errorDescription = "JSON ENCODING ERROR: \(error.localizedDescription). Details: \(error)"
            FileHandle.standardError.write(errorDescription.data(using: .utf8)!)
            return nil
        }
    }
}