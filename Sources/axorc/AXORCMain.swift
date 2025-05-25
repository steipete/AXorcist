// AXORCMain.swift - Main entry point for AXORC CLI

import ArgumentParser
import AXorcist // For AXorcist instance
import Foundation

@main
struct AXORCCommand: AsyncParsableCommand {
    static let configuration: CommandConfiguration = CommandConfiguration(
        commandName: "axorc",
        abstract: "AXORC CLI - Handles JSON commands via various input methods. Version \(axorcVersion)"
    )

    @Flag(name: .long, help: "Enable debug logging for the command execution.")
    var debug: Bool = false

    @Flag(name: .long, help: "Read JSON payload from STDIN.")
    var stdin: Bool = false

    @Option(name: .long, help: "Read JSON payload from the specified file path.")
    var file: String?

    @Option(name: .long, help: "Read JSON payload directly from this string argument, expecting a JSON string.")
    var json: String?

    @Argument(
        help: "Read JSON payload directly from this string argument. If other input flags (--stdin, --file, --json) are used, this argument is ignored."
    )
    var directPayload: String?

    mutating func run() async throws {
        // Configure GlobalAXLogger based on debug flag
        await GlobalAXLogger.shared.setLoggingEnabled(debug)
        await GlobalAXLogger.shared.setDetailLevel(debug ? .verbose : .minimal)

        // Parse input using InputHandler
        let inputResult = InputHandler.parseInput(
            stdin: stdin,
            file: file,
            json: json,
            directPayload: directPayload
        )

        // Handle input errors
        if let error = inputResult.error {
            let collectedLogs = debug ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text, includeTimestamps: true, includeLevels: true, includeDetails: true) : nil

            let errorResponse = ErrorResponse(
                commandId: "input_error",
                error: error,
                debugLogs: collectedLogs
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
            let collectedLogs = debug ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text, includeTimestamps: true, includeLevels: true, includeDetails: true) : nil

            let errorResponse = ErrorResponse(
                commandId: "no_input",
                error: "No valid JSON input received",
                debugLogs: collectedLogs
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
            // Clear logs after error
            await axClearLogs()
            print("{\"error\": \"Failed to convert JSON string to data\"}")
            return
        }

        if debug {
            axDebugLog("AXORCMain: jsonString before decode: [\(jsonString)]")
            axDebugLog("AXORCMain: jsonData.count before decode: \(jsonData.count)")
        }

        do {
            let command = try JSONDecoder().decode(CommandEnvelope.self, from: jsonData)

            if debug {
                axDebugLog("Successfully parsed command: \(command.command)")
            }

            // Execute command using CommandExecutor
            let axorcist = AXorcist()
            let result = await CommandExecutor.execute(
                command: command,
                axorcist: axorcist
            )

            print(result) // CommandExecutor.execute should return a string (JSON response)

            // Stop collecting logs after successful execution
            // Clear logs after error
            await axClearLogs()

        } catch {
            axErrorLog("DECODE_ERROR_DEBUG: Original jsonString that led to this error: [\(jsonString)]")
            axErrorLog("DECODE_ERROR_DEBUG: jsonData.count that led to this error: \(jsonData.count)")
            axErrorLog("DECODE_ERROR_DEBUG: Raw error.localizedDescription: \(error.localizedDescription)")
            axErrorLog("DECODE_ERROR_DEBUG: Full error object: \(error)")

            let errorMessage = "Failed to parse JSON command. Raw Error: \(error.localizedDescription). JSON Input (first 100 chars): \(jsonString.prefix(100))..."

            // For decode errors, always collect logs
            if !debug {
                await GlobalAXLogger.shared.setLoggingEnabled(true)
                await GlobalAXLogger.shared.setDetailLevel(.verbose)
            }
            let collectedLogs = await GlobalAXLogger.shared.getLogsAsStrings(format: .text, includeTimestamps: true, includeLevels: true, includeDetails: true)
            await axClearLogs()

            let errorResponse = ErrorResponse(
                commandId: "decode_error",
                error: errorMessage,
                debugLogs: collectedLogs
            )

            if let responseData = try? JSONEncoder().encode(errorResponse),
               let responseStr = String(data: responseData, encoding: .utf8) {
                print(responseStr)
            } else {
                // Fallback if even error encoding fails
                let fallbackErrorMsg = "{\"error\": \"Failed to encode error response. Original error for decode: \(error.localizedDescription). Input was: \(jsonString)\"}"
                print(fallbackErrorMsg)
            }
        }
    }
}
