// AXORCMain.swift - Main entry point for AXORC CLI

import ArgumentParser
import AXorcist // For AXorcist instance
import Foundation
import CoreFoundation

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

    // Helper function to process and execute a CommandEnvelope
    private func processAndExecuteCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) async {
        if debugCLI {
            axDebugLog("Successfully parsed command: \(command.command) (ID: \(command.commandId))")
        }

        let resultJsonString = await CommandExecutor.execute(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI
        )
        print(resultJsonString)
        fflush(stdout)

        if command.command == .observe {
            var observerSetupSucceeded = false
            if let resultData = resultJsonString.data(using: .utf8) {
                do {
                    if let json = try JSONSerialization.jsonObject(with: resultData, options: []) as? [String: Any],
                       let success = json["success"] as? Bool,
                       let status = json["status"] as? String {
                        axInfoLog("AXORCMain: Parsed initial response for observe: success=\(success), status=\(status)")
                        if success && status == "observer_started" {
                            observerSetupSucceeded = true
                            axInfoLog("AXORCMain: Observer setup deemed SUCCEEDED for observe command.")
                        } else {
                            axInfoLog("AXORCMain: Observer setup deemed FAILED for observe command (success=\(success), status=\(status)).")
                        }
                    } else {
                        axErrorLog("AXORCMain: Failed to parse expected fields (success, status) from observe setup JSON.")
                    }
                } catch {
                    axErrorLog("AXORCMain: Could not parse result JSON from observe setup to check for success: \(error.localizedDescription)")
                }
            } else {
                axErrorLog("AXORCMain: Could not convert result JSON string to data for observe setup check.")
            }

            if observerSetupSucceeded {
                axInfoLog("AXORCMain: Observer setup successful. Process will remain alive.")
                #if DEBUG
                axInfoLog("AXORCMain: DEBUG mode - launching dedicated run-loop thread for observer.")
                Thread.detachNewThread { CFRunLoopRun() }
                axInfoLog("AXORCMain: DEBUG mode - main task entering infinite sleep loop.")
                while true {
                    do { try await Task.sleep(nanoseconds: 3_600_000_000_000) }
                    catch { axInfoLog("AXORCMain: Main task sleep interrupted."); break }
                }
                #else
                fputs("{\"error\": \"The 'observe' command is intended for DEBUG builds or specific use cases and will not run indefinitely in this release build. Exiting.\"}\n", stderr)
                fflush(stderr)
                exit(1)
                #endif
            } else {
                axErrorLog("AXORCMain: Observe command setup reported failure or result was not a success status. Exiting.")
            }
        } else {
            await axClearLogs() // Clear logs for non-observe commands after execution
        }
    }

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
            let errorResponse = ErrorResponse(commandId: "input_error", error: error, debugLogs: collectedLogs)
            if let jsonData = try? JSONEncoder().encode(errorResponse), let jsonString = String(data: jsonData, encoding: .utf8) {
                print(jsonString)
            } else {
                print("{\"error\": \"Failed to encode error response\"}")
            }
            return
        }

        guard let jsonStringFromInput = inputResult.jsonString else {
            let collectedLogs = debug ? await GlobalAXLogger.shared.getLogsAsStrings(format: .text, includeTimestamps: true, includeLevels: true, includeDetails: true) : nil
            let errorResponse = ErrorResponse(commandId: "no_input", error: "No valid JSON input received", debugLogs: collectedLogs)
            if let jsonData = try? JSONEncoder().encode(errorResponse), let jsonStr = String(data: jsonData, encoding: .utf8) {
                print(jsonStr)
            } else {
                print("{\"error\": \"Failed to encode error response\"}")
            }
            return
        }
        axDebugLog("AXORCMain Test: Received jsonStringFromInput: [\(jsonStringFromInput)] (length: \(jsonStringFromInput.count))")

        if let data = jsonStringFromInput.data(using: .utf8) {
            let axorcist = AXorcist()
            let decoder = JSONDecoder()
            decoder.keyDecodingStrategy = .convertFromSnakeCase
            do {
                // Attempt 1: Decode as [CommandEnvelope]
                let commands = try decoder.decode([CommandEnvelope].self, from: data)
                if let command = commands.first {
                    axDebugLog("AXORCMain Test: Decode attempt 1: Successfully decoded [CommandEnvelope] and got first command.")
                    await processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: debug)
                } else {
                    axDebugLog("AXORCMain Test: Decode attempt 1: Decoded [CommandEnvelope] but array was empty.")
                    // Create a generic error to throw if this path is problematic
                    let anError = NSError(domain: "AXORCErrorDomain", code: 1001, userInfo: [NSLocalizedDescriptionKey: "Decoded empty command array from [CommandEnvelope] attempt."])
                    throw anError
                }
            } catch let arrayDecodeError {
                axDebugLog("AXORCMain Test: Decode attempt 1 (as [CommandEnvelope]) FAILED. Error: \(arrayDecodeError). Will try as single CommandEnvelope.")
                // Attempt 2: Decode as single CommandEnvelope
                do {
                    let command = try decoder.decode(CommandEnvelope.self, from: data) // data is still from jsonStringFromInput
                    axDebugLog("AXORCMain Test: Decode attempt 2: Successfully decoded as SINGLE CommandEnvelope.")
                    await processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: debug)
                } catch let singleDecodeError {
                     axDebugLog("AXORCMain Test: Decode attempt 2 (as single CommandEnvelope) ALSO FAILED. Error: \(singleDecodeError). Original array decode error was: \(arrayDecodeError)")
                    throw singleDecodeError // Throw the error from the single decode attempt as it's the most direct if input was not an array
                }
            }
        } else {
            axDebugLog("AXORCMain Test: Failed to convert jsonStringFromInput to data.")
            let anError = NSError(domain: "AXORCErrorDomain", code: 1002, userInfo: [NSLocalizedDescriptionKey: "Failed to convert jsonStringFromInput to data."])
            throw anError
        }
    }
}
