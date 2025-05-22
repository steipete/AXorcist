// CommandExecutor.swift - Executes AXORC commands

import AXorcist
import Foundation

struct CommandExecutor {

    static func execute(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debug: Bool
    ) async -> String {

        var localDebugLogs: [String] = []

        if debug {
            localDebugLogs.append("Executing command: \(command.command)")
        }

        // Command execution logic will be moved here from the main run() function
        // This is a placeholder for the refactored command execution

        // For now, return a simple response
        let response = QueryResponse(
            success: false,
            commandId: command.command_id,
            command: command.command.rawValue,
            error: "Command execution not yet implemented in refactored structure",
            debugLogs: localDebugLogs
        )

        return encodeToJson(response) ?? "{\"error\": \"Failed to encode response\"}"
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
