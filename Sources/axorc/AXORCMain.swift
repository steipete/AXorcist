// AXORCMain.swift - Main entry point for AXORC CLI

import AXorcist
@preconcurrency import Commander
import CoreFoundation
import Foundation

@main
struct AXORCCommand: ParsableCommand {
    static func main() async {
        do {
            let parsedValues = try Self.parseCommandLineArguments()
            var command = AXORCCommand()
            try command.apply(parsedValues: parsedValues)
            try await command.run()
        } catch let error as CommanderError {
            Self.emitArgumentError(message: error.description)
            Foundation.exit(ExitCode.failure.rawValue)
        } catch let validation as ValidationError {
            Self.emitArgumentError(message: validation.description)
            Foundation.exit(ExitCode.failure.rawValue)
        } catch let exitCode as ExitCode {
            Foundation.exit(exitCode.rawValue)
        } catch {
            fputs("axorc error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        let version = MainActor.assumeIsolated { axorcVersion }
        return CommandDescription(
            commandName: "axorc",
            // Use axorcVersion from AXORCModels.swift or a shared constant place
            abstract: "AXORC CLI - Handles JSON commands via various input methods. Version \(version)")
    }

    // `--debug` now enables *normal* diagnostic output. Use the new `--verbose` flag for the extremely chatty logs.
    @Flag(name: .long, help: "Enable debug logging (normal detail level). Use --verbose for maximum detail.")
    var debug: Bool = false

    @Flag(name: .long, help: "Enable *verbose* debug logging – every internal step. Produces large output.")
    var verbose: Bool = false

    @Flag(name: .long, help: "Read JSON payload from STDIN.")
    var stdin: Bool = false

    @Option(name: .long, help: "Read JSON payload from the specified file path.")
    var file: String?

    @Option(name: .long, help: "Read JSON payload directly from this string argument, expecting a JSON string.")
    var json: String?

    @Option(name: .long, help: "Traversal timeout in seconds (overrides default 30).")
    var timeout: Int?

    @Flag(name: .long, help: "Traverse every node (ignore container role pruning). May be extremely slow.")
    var scanAll: Bool = false

    @Flag(name: .customLong("no-stop-first"), help: "Do not stop at first match; collect deeper matches as well.")
    var noStopFirst: Bool = false

    @Argument(
        help: logSegments(
            "Read JSON payload directly from this string argument.",
            "Ignored when other input flags (--stdin, --file, --json) are provided."))
    var directPayload: String?

    @MainActor
    private var suppressFinalLogDump = false

    // Helper function to process and execute a CommandEnvelope
    @MainActor private func processAndExecuteCommand(command: CommandEnvelope, axorcist: AXorcist, debugCLI: Bool) {
        if debugCLI {
            axDebugLog("Successfully parsed command: \(command.command) (ID: \(command.commandId))")
        }

        let resultJsonString = CommandExecutor.execute(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI)
        print(resultJsonString)
        fflush(stdout)

        if command.command == .observe {
            self.handleObserveCommand(resultJsonString: resultJsonString, debugCLI: self.debug)
        } else {
            axClearLogs()
        }
    }

    @MainActor
    private func handleObserveCommand(resultJsonString: String, debugCLI: Bool) {
        let observerSetupSucceeded = self.parseObserveSetup(resultJsonString)
        if observerSetupSucceeded {
            axInfoLog(
                logSegments(
                    "AXORCMain: Observer setup successful",
                    "Process will remain alive by running current RunLoop"))
            #if DEBUG
            axInfoLog("AXORCMain: DEBUG mode - entering RunLoop.current.run() for observer.")
            RunLoop.current.run()
            axInfoLog("AXORCMain: DEBUG mode - RunLoop.current.run() finished.")
            #else
            let errorPayload = [
                "{\"error\": \"The 'observe' command is intended for DEBUG builds or specific use cases.",
                " In release, it sets up the observer but will not keep the process alive indefinitely by itself.",
                " Exiting normally after setup.\"}\n",
            ].joined()
            fputs(errorPayload, stderr)
            fflush(stderr)
            #endif
        } else {
            axErrorLog(
                logSegments(
                    "AXORCMain: Observe command setup reported failure or result was not a success status",
                    "Exiting"))
        }
    }

    private func parseObserveSetup(_ jsonString: String) -> Bool {
        guard let resultData = jsonString.data(using: .utf8) else {
            axErrorLog("AXORCMain: Could not convert result JSON string to data for observe setup check.")
            return false
        }

        do {
            if
                let jsonOutput = try JSONSerialization.jsonObject(with: resultData, options: []) as?
                [String: Any],
                let success = jsonOutput["success"] as? Bool,
                let status = jsonOutput["status"] as? String
            {
                axInfoLog(
                    logSegments(
                        "AXORCMain: Parsed initial response for observe",
                        "success=\(success)",
                        "status=\(status)"))
                if success, status == "observer_started" {
                    axInfoLog("AXORCMain: Observer setup deemed SUCCEEDED for observe command.")
                    return true
                }
                axInfoLog(
                    logSegments(
                        "AXORCMain: Observer setup deemed FAILED for observe command",
                        "success=\(success)",
                        "status=\(status)"))
                return false
            }
            axErrorLog(
                logSegments(
                    "AXORCMain: Failed to parse expected fields (success, status)",
                    "from observe setup JSON"))
            return false
        } catch {
            axErrorLog(
                logSegments(
                    "AXORCMain: Could not parse result JSON from observe setup to check for success",
                    error.localizedDescription))
            return false
        }
    }

    mutating func run() async throws {
        try await MainActor.run {
            try self.runMain()
        }
    }

    @MainActor
    private mutating func runMain() throws {
        self.configureLogging()
        self.applyGlobalFlags()
        self.logDebugVersion()

        let inputResult = InputHandler.parseInput(
            stdin: self.stdin,
            file: self.file,
            json: self.json,
            directPayload: self.directPayload)
        axorcInputSource = inputResult.sourceDescription

        let axorcistInstance = AXorcist.shared

        if self.handleInputError(inputResult) {
            return
        }

        guard let jsonStringFromInput = inputResult.jsonString else {
            self.handleMissingInput()
            return
        }

        self.logDebug(
            logSegments(
                "AXORCMain Test: Received jsonStringFromInput",
                "[\(jsonStringFromInput)]",
                "length: \(jsonStringFromInput.count)"))

        try self.decodeAndExecute(
            jsonString: jsonStringFromInput,
            axorcist: axorcistInstance)

        if self.debug, self.commandShouldPrintLogsAtEnd() {
            self.flushDebugLogs()
        }
    }

    private func configureLogging() {
        if self.verbose {
            GlobalAXLogger.shared.isLoggingEnabled = true
            GlobalAXLogger.shared.detailLevel = .verbose
        } else if self.debug {
            GlobalAXLogger.shared.isLoggingEnabled = true
            GlobalAXLogger.shared.detailLevel = .normal
        } else {
            GlobalAXLogger.shared.isLoggingEnabled = false
            GlobalAXLogger.shared.detailLevel = .minimal
        }
    }

    private func applyGlobalFlags() {
        axorcScanAll = self.scanAll
        axorcStopAtFirstMatch = !self.noStopFirst
        if let timeout {
            axorcTraversalTimeout = TimeInterval(timeout)
        }
    }

    private func logDebugVersion() {
        guard self.debug || self.verbose else { return }
        let version = MainActor.assumeIsolated { axorcVersion }
        fputs(
            logSegments(
                "AXORCMain.run: AXorc version \(version) build \(axorcBuildStamp)",
                "Detail level: \(GlobalAXLogger.shared.detailLevel).") + "\n",
            stderr)
    }

    private func handleInputError(_ inputResult: InputHandler.Result) -> Bool {
        guard let error = inputResult.error else { return false }
        self.respondWithError(
            commandId: "input_error",
            error: error,
            logs: self.debug ? axGetLogsAsStrings(format: .text) : nil)
        return true
    }

    private func handleMissingInput() {
        self.respondWithError(
            commandId: "no_input",
            error: "No valid JSON input received",
            logs: self.debug ? axGetLogsAsStrings(format: .text) : nil)
    }

    private func respondWithError(commandId: String, error: String, logs: [String]?) {
        Self.printErrorResponse(commandId: commandId, error: error, logs: logs)
    }

    private mutating func decodeAndExecute(jsonString: String, axorcist: AXorcist) throws {
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        guard let data = jsonString.data(using: .utf8) else {
            axDebugLog("AXORCMain Test: Failed to convert jsonStringFromInput to data.")
            self.respondWithError(
                commandId: "data_conversion_error",
                error: "Failed to convert JSON string to data",
                logs: self.debug ? axGetLogsAsStrings() : nil)
            return
        }

        do {
            let commands = try decoder.decode([CommandEnvelope].self, from: data)
            self.suppressFinalLogDump = commands.contains { $0.command == .observe }
            if let command = commands.first {
                self.processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: self.debug)
                return
            }
            self.logDebug("AXORCMain Test: Decode attempt 1: Decoded [CommandEnvelope] but array was empty.")
            throw NSError(
                domain: "AXORCErrorDomain",
                code: 1001,
                userInfo: [NSLocalizedDescriptionKey: "Decoded empty command array from [CommandEnvelope] attempt."])
        } catch let arrayDecodeError {
            logDebug(
                logSegments(
                    "AXORCMain Test: Decode attempt 1 (as [CommandEnvelope]) FAILED",
                    "Error: \(arrayDecodeError)",
                    "Will try as single CommandEnvelope"))
            do {
                let command = try decoder.decode(CommandEnvelope.self, from: data)
                suppressFinalLogDump = command.command == .observe
                processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: debug)
            } catch let singleDecodeError {
                logDebug(
                    logSegments(
                        "AXORCMain Test: Decode attempt 2 (as single CommandEnvelope) ALSO FAILED",
                        "Error: \(singleDecodeError)",
                        "Original array decode error was: \(arrayDecodeError)"))
                respondWithError(
                    commandId: "decode_error",
                    error: "Failed to decode JSON input: \(singleDecodeError.localizedDescription)",
                    logs: debug ? axGetLogsAsStrings() : nil)
            }
        }
    }

    private func flushDebugLogs() {
        let logMessages = axGetLogsAsStrings(format: .text)
        guard !logMessages.isEmpty else { return }
        fputs("\n--- Debug Logs (axorc run end) ---\n", stderr)
        logMessages.forEach { fputs($0 + "\n", stderr) }
        fputs("--- End Debug Logs ---\n", stderr)
        fflush(stderr)
    }

    private func logDebug(_ message: String) {
        axDebugLog(message)
    }

    private func commandShouldPrintLogsAtEnd() -> Bool {
        !self.suppressFinalLogDump
    }
}

// MARK: - Commander Parsing

extension AXORCCommand {
    private static func parseCommandLineArguments() throws -> ParsedValues {
        let prototype = Self.init()
        let signature = CommandSignature.describe(prototype)
        let parser = CommandParser(signature: signature)
        let rawArguments = Array(CommandLine.arguments.dropFirst())
        return try parser.parse(arguments: rawArguments)
    }

    private mutating func apply(parsedValues: ParsedValues) throws {
        self.debug = parsedValues.flags.contains("debug")
        self.verbose = parsedValues.flags.contains("verbose")
        self.stdin = parsedValues.flags.contains("stdin")
        self.scanAll = parsedValues.flags.contains("scanAll")
        self.noStopFirst = parsedValues.flags.contains("noStopFirst")

        if let fileValue = parsedValues.options["file"]?.last {
            self.file = fileValue
        }

        if let jsonValue = parsedValues.options["json"]?.last {
            self.json = jsonValue
        }

        if let timeoutString = parsedValues.options["timeout"]?.last {
            guard let timeoutValue = Int(timeoutString) else {
                throw ValidationError("Invalid value for --timeout: \(timeoutString)")
            }
            self.timeout = timeoutValue
        }

        self.directPayload = parsedValues.positional.first
    }

    private static func emitArgumentError(message: String) {
        Self.printErrorResponse(commandId: "argument_error", error: message, logs: nil)
    }

    private static func printErrorResponse(commandId: String, error: String, logs: [String]?) {
        let errorResponse = ErrorResponse(commandId: commandId, error: error, debugLogs: logs)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.keyEncodingStrategy = .convertToSnakeCase
        if let jsonData = try? encoder.encode(errorResponse),
           let jsonString = String(data: jsonData, encoding: .utf8)
        {
            print(jsonString)
        } else {
            print("{\"error\": \"Failed to encode error response\"}")
        }
    }
}

// ErrorResponse struct is now defined in AXORCModels.swift
// struct ErrorResponse: Codable {
// var commandId: String
// var status: String = "error"
// var error: String
// var debugLogs: [String]?
// }
