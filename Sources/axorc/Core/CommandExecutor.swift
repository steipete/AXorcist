// CommandExecutor.swift - Executes AXORC commands

import AXorcistLib
import Foundation

struct CommandExecutor {

    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debug: Bool
    ) async -> String {

        var localDebugLogs: [String] = []
        if debug { localDebugLogs.append("Executing command: \(command.command) (ID: \(command.command_id))") }

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
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: debug ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding performAction response failed\"}"

        case .getFocusedElement:
            let handlerResponse: HandlerResponse = await ax.handleGetFocusedElement(
                for: command.application,
                requestedAttributes: command.attributes,
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: debug ? localDebugLogs : nil
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
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: debug ? localDebugLogs : nil
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
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: debug ? localDebugLogs : nil
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
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: debug ? localDebugLogs : nil
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
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            let queryResponse = QueryResponse(
                command_id: command.command_id,
                success: handlerResponse.error == nil,
                command: command.command.rawValue,
                handlerResponse: handlerResponse,
                debug_logs: debug ? localDebugLogs : nil
            )
            return encodeToJson(queryResponse) ?? "{\"error\": \"Encoding extractText response failed\"}"

        case .collectAll:
            // AXorcist.handleCollectAll returns a String (JSON) directly.
            // It manages its own debug logs internally via recursiveCallDebugLogs.
            // The `currentDebugLogs` passed to it is for initial logs only.
            let jsonStringResult = await ax.handleCollectAll(
                for: command.application,
                locator: command.locator,
                pathHint: command.path_hint,
                maxDepth: command.max_elements,
                requestedAttributes: command.attributes,
                outputFormat: command.output_format,
                commandId: command.command_id,
                isDebugLoggingEnabled: debug,
                currentDebugLogs: localDebugLogs
            )
            return jsonStringResult

        case .batch:
            guard let subCommands = command.sub_commands else {
                let error = "Missing sub_commands for batch"
                localDebugLogs.append(error)
                return encodeToJson(QueryResponse(
                    success: false,
                    commandId: command.command_id,
                    command: command.command.rawValue,
                    error: error,
                    debugLogs: debug ? localDebugLogs : nil
                )) ?? "{\"error\": \"Encoding error response failed\"}"
            }
            let batchHandlerResponses: [HandlerResponse] = await ax.handleBatchCommands(
                batchCommandID: command.command_id,
                subCommands: subCommands,
                isDebugLoggingEnabled: debug,
                currentDebugLogs: &localDebugLogs
            )
            // Convert [HandlerResponse] to an array of QueryResponse objects
            let queryResponses = batchHandlerResponses.enumerated().map { index, hr -> QueryResponse in
                let subCommandId = index < subCommands.count ? subCommands[index].command_id : "batch_sub_\(index)"
                let subCommand = index < subCommands.count ? subCommands[index].command.rawValue : "unknown"
                return QueryResponse(
                    command_id: subCommandId,
                    success: hr.error == nil,
                    command: subCommand,
                    handlerResponse: hr,
                    debug_logs: hr.debug_logs
                )
            }
            // Determine overall success of the batch
            let overallSuccess = batchHandlerResponses.allSatisfy { $0.error == nil }
            // Return BatchOperationResponse
            let batchResponse = BatchOperationResponse(
                command_id: command.command_id,
                success: overallSuccess,
                results: queryResponses,
                debug_logs: debug ? localDebugLogs : nil
            )
            return encodeToJson(batchResponse) ?? "{\"error\": \"Encoding batch response failed\"}"

        case .ping:
            let appName = command.application ?? "N/A"
            let msg = "Ping received for \(appName). AXORC Version: \(AXORC_VERSION)"
            localDebugLogs.append(msg)
            return encodeToJson(SimpleSuccessResponse(
                command_id: command.command_id,
                success: true,
                status: "pong",
                message: msg,
                details: nil,
                debug_logs: debug ? localDebugLogs : nil
            )) ?? "{\"error\": \"Encoding ping response failed\"}"
        }
    }

    private static func encodeToJson<T: Codable>(_ object: T) -> String? {
        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted

        do {
            let data = try encoder.encode(object)
            return String(data: data, encoding: .utf8)
        } catch {
            return nil
        }
    }
}