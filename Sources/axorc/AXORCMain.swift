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

        guard var jsonStringFromInput = inputResult.jsonString else {
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
        axDebugLog("AXORCMain: jsonStringFromInput (from InputHandler): [\(jsonStringFromInput)] (length: \(jsonStringFromInput.count))")

        // Ensure we are working with a "concrete" String instance to avoid Substring/StringProtocol ambiguities
        var jsonString = String(jsonStringFromInput)
        axDebugLog("AXORCMain: jsonString (after String(jsonStringFromInput)): [\(jsonString)] (length: \(jsonString.count))")
        
        // Log first/last chars of the concrete jsonString
        if !jsonString.isEmpty {
            axDebugLog("AXORCMain: First char of concrete jsonString: \(jsonString.first!) (ASCII: \(jsonString.first!.asciiValue ?? 0)), Last char: \(jsonString.last!) (ASCII: \(jsonString.last!.asciiValue ?? 0))")
        }

        // Parse JSON command
        var dataToDecode = jsonString.data(using: .utf8) // Default to using the concrete jsonString
        var didAttemptUnwrap = false

        if jsonString.hasPrefix("[") && jsonString.hasSuffix("]") && jsonString.count > 2 { // Use concrete jsonString for checks
            let innerContentString = String(jsonString.dropFirst().dropLast())
            axDebugLog("AXORCMain: Original concrete jsonString appeared to be an array. Attempting to use its inner content: [\(innerContentString)]")
            if let innerData = innerContentString.data(using: .utf8) {
                dataToDecode = innerData
                didAttemptUnwrap = true
            } else {
                axDebugLog("AXORCMain: Failed to convert innerContentString to data. Will use original concrete jsonString data.")
            }
        } else {
            axDebugLog("AXORCMain: Original concrete jsonString does not appear to be a simple array wrapper. Proceeding with it for data conversion.")
        }
        
        // axDebugLog("AXORCMain: effectiveJsonString after unwrap attempt: [\(effectiveJsonString)]") // Old log, dataToDecode is now key

        guard let jsonData = dataToDecode else {
            // Clear logs after error
            await axClearLogs()
            print("{\"error\": \"Failed to convert JSON string to data\"}")
            return
        }

        if debug {
            axDebugLog("AXORCMain: jsonData.count before decode (this is from effective/unwrapped data if unwrap occurred): \(jsonData.count)")
        }
        
        let axorcist = AXorcist() // Initialize once, outside the do-catch for broader scope

        do {
            // This is the primary attempt, using `jsonData` (derived from `dataToDecode`, 
            // which is from `jsonString` after faulty unwrap attempt due to string issues)
            let command = try JSONDecoder().decode(CommandEnvelope.self, from: jsonData)
            axDebugLog("AXORCMain: Decode attempt 1 (from jsonData derived from potentially pre-unwrapped jsonString) successful.")
            await processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: debug)
        } catch let error1 {
            axDebugLog("AXORCMain: Decode attempt 1 (from jsonData) FAILED. Error: \(error1). jsonStringFromInput (raw from InputHandler) was: [\(jsonStringFromInput)]")
            // Fallback: Assume jsonStringFromInput is "[{...}]" because InputHandler (via ArgumentParser) seems to yield this.
            // Try to extract "{...}" and decode that as a single CommandEnvelope.
            if jsonStringFromInput.count > 2 { // Basic check for "[]" at least
                let potentiallyInnerJsonString = String(jsonStringFromInput.dropFirst().dropLast())
                axDebugLog("AXORCMain: Fallback: Extracted potentiallyInnerJsonString from jsonStringFromInput: [\(potentiallyInnerJsonString)]")
                if let innerData = potentiallyInnerJsonString.data(using: .utf8) {
                    do {
                        let command = try JSONDecoder().decode(CommandEnvelope.self, from: innerData)
                        axDebugLog("AXORCMain: Decode attempt 2 (from inner content of jsonStringFromInput) SUCCESSFUL.")
                        await processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: debug)
                    } catch let error2 {
                        axDebugLog("AXORCMain: Decode attempt 2 (from inner content of jsonStringFromInput) FAILED. Error: \(error2). Will rethrow original error from attempt 1.")
                        throw error1 // Rethrow original error from attempt 1
                    }
                } else {
                    axDebugLog("AXORCMain: Fallback: Failed to convert potentiallyInnerJsonString to data. Will rethrow original error from attempt 1.")
                    throw error1 // Rethrow original error from attempt 1
                }
            } else {
                axDebugLog("AXORCMain: Fallback: jsonStringFromInput too short to be '[{...}]'. Will rethrow original error from attempt 1.")
                throw error1 // Rethrow original error from attempt 1
            }
        }
        // Removed the final generic catch to ensure errors propagate to ArgumentParser if not handled by the specific fallback.
    }
}
