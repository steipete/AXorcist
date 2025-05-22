// AXORCMain.swift - Main entry point for AXORC CLI

import ArgumentParser
import AXorcist
import Foundation

@main
struct AXORCCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = CommandConfiguration(
        commandName: "axorc",
        abstract: "AXORC CLI - Handles JSON commands via various input methods. Version \(AXORC_VERSION)"
    )

    @Flag(name: .long, help: "Enable debug logging for the command execution.")
    var debug: Bool = false

    @Flag(name: .long, help: "Read JSON payload from STDIN.")
    var stdin: Bool = false

    @Option(name: .long, help: "Read JSON payload from the specified file path.")
    var file: String?

    @Argument(
        help: "Read JSON payload directly from this string argument. If other input flags (--stdin, --file) are used, this argument is ignored."
    )
    var directPayload: String?

    mutating func run() async throws {
        // Parse input using InputHandler
        let inputResult = InputHandler.parseInput(
            stdin: stdin,
            file: file,
            directPayload: directPayload,
            debug: debug
        )

        var localDebugLogs = inputResult.debugLogs

        // Handle input errors
        if let error = inputResult.error {
            let errorResponse = ErrorResponse(
                command_id: "input_error",
                error: ErrorResponse.ErrorDetail(
                    message: error
                ),
                debug_logs: debug ? localDebugLogs : nil
            )

            if let jsonData = try? JSONEncoder().encode(errorResponse),
               let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                print("{\"error\": \"Failed to encode error response\"}")
            }
            return
        }

        guard let jsonString = inputResult.jsonString else {
            let errorResponse = ErrorResponse(
                command_id: "no_input",
                error: ErrorResponse.ErrorDetail(
                    message: "No valid JSON input received"
                ),
                debug_logs: debug ? localDebugLogs : nil
            )

            if let jsonData = try? JSONEncoder().encode(errorResponse),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print(jsonStr)
            } else {
                print("{\"error\": \"Failed to encode error response\"}")
            }
            return
        }

        // Parse JSON command
        guard let jsonData = jsonString.data(using: .utf8) else {
            print("{\"error\": \"Failed to convert JSON string to data\"}")
            return
        }

        do {
            let command = try JSONDecoder().decode(CommandEnvelope.self, from: jsonData)

            if debug {
                localDebugLogs.append("Successfully parsed command: \(command.command)")
            }

            // Execute command using CommandExecutor
            let axorcist = AXorcist()
            let result = await CommandExecutor.execute(
                command: command,
                axorcist: axorcist,
                debug: debug
            )

            print(result)

        } catch {
            let errorResponse = ErrorResponse(
                command_id: "decode_error",
                error: ErrorResponse.ErrorDetail(
                    message: "Failed to parse JSON command: \(error.localizedDescription)"
                ),
                debug_logs: debug ? localDebugLogs : nil
            )

            if let jsonData = try? JSONEncoder().encode(errorResponse),
               let jsonStr = String(data: jsonData, encoding: .utf8) {
                print(jsonStr)
            } else {
                print("{\"error\": \"Failed to encode error response\"}")
            }
        }
    }
}
