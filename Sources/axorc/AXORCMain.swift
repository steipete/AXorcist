// AXORCMain.swift - Main entry point for AXORC CLI

import AXorcist
@preconcurrency import Commander
import CoreFoundation
import Foundation
import Logging

@main
struct AXORCCommand: ParsableCommand {
    static func main() async {
        let arguments = Array(CommandLine.arguments.dropFirst())
        Self.configureSwiftLogging(arguments: arguments)
        do {
            let frontendExitCode: Int32? = try await MainActor.run {
                try CLIFrontend.handle(arguments: arguments)
            }
            if let exitCode = frontendExitCode {
                Foundation.exit(exitCode)
            }

            let rawArguments = CLIFrontend.rawArguments(from: arguments)
            let parsedValues = try Self.parseCommandLineArguments(arguments: rawArguments)
            var command = AXORCCommand()
            try command.apply(parsedValues: parsedValues)
            try await command.run()
        } catch let error as CLIFrontend.UserError {
            CLIFrontend.emit(error)
            Foundation.exit(error.exitCode)
        } catch let error as CommanderError {
            Self.printErrorResponse(commandId: "argument_error", error: error.description, logs: nil)
            Foundation.exit(2)
        } catch let validation as ValidationError {
            Self.printErrorResponse(commandId: "argument_error", error: validation.description, logs: nil)
            Foundation.exit(2)
        } catch let exitCode as ExitCode {
            Foundation.exit(exitCode.rawValue)
        } catch {
            fputs("axorc error: \(error)\n", stderr)
            Foundation.exit(1)
        }
    }

    @preconcurrency nonisolated static var commandDescription: CommandDescription {
        CommandDescription(
            commandName: "axorc",
            abstract: "Inspect and automate macOS Accessibility from the shell.",
            version: axorcVersion)
    }

    /// `--debug` now enables *normal* diagnostic output. Use the new `--verbose` flag for the extremely chatty logs.
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

    /// Helper function to process and execute a CommandEnvelope
    @MainActor private func processAndExecuteCommand(
        command: CommandEnvelope,
        axorcist: AXorcist,
        debugCLI: Bool) throws
    {
        if debugCLI {
            axDebugLog("Successfully parsed command: \(command.command) (ID: \(command.commandId))")
        }

        let resultJsonString = CommandExecutor.execute(
            command: command,
            axorcist: axorcist,
            debugCLI: debugCLI)
        print(resultJsonString)
        fflush(stdout)

        guard CLIFrontend.responseSucceeded(resultJsonString) else {
            throw ExitCode.failure
        }

        if command.command == .observe {
            self.handleSuccessfulObserveCommand(owner: axorcist)
        } else {
            axClearLogs()
        }
    }

    @MainActor
    private func handleSuccessfulObserveCommand(owner: AXorcist) {
        axInfoLog(
            logSegments(
                "AXORCMain: Observer setup successful",
                "Process will remain alive by running current RunLoop"))
        withExtendedLifetime(owner) {
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
            throw ExitCode.failure
        }

        guard let jsonStringFromInput = inputResult.jsonString else {
            self.handleMissingInput()
            throw ExitCode.failure
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
            throw ExitCode.failure
        }

        let commands: [CommandEnvelope]
        do {
            commands = try decoder.decode([CommandEnvelope].self, from: data)
        } catch let arrayDecodeError {
            self.logDebug("Array decode failed: \(arrayDecodeError). Trying a single command.")
            do {
                commands = try [decoder.decode(CommandEnvelope.self, from: data)]
            } catch let singleDecodeError {
                self.logDebug("Single-command decode failed: \(singleDecodeError).")
                self.respondWithError(
                    commandId: "decode_error",
                    error: "Failed to decode JSON input: \(singleDecodeError.localizedDescription)",
                    logs: self.debug ? axGetLogsAsStrings() : nil)
                throw ExitCode.failure
            }
        }

        guard let command = commands.first else {
            self.respondWithError(
                commandId: "decode_error",
                error: "JSON command array must not be empty",
                logs: self.debug ? axGetLogsAsStrings() : nil)
            throw ExitCode.failure
        }

        self.suppressFinalLogDump = command.command == .observe
        try self.processAndExecuteCommand(command: command, axorcist: axorcist, debugCLI: self.debug)
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
    private static func parseCommandLineArguments(arguments: [String]) throws -> ParsedValues {
        let prototype = Self()
        let signature = CommandSignature.describe(prototype)
        let parser = CommandParser(signature: signature)
        return try parser.parse(arguments: arguments)
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

    private static func configureSwiftLogging(arguments: [String]) {
        let level: Logger.Level = if arguments.contains("--verbose") {
            .trace
        } else if arguments.contains("--debug") {
            .debug
        } else {
            .critical
        }

        LoggingSystem.bootstrap { label in
            var handler = StreamLogHandler.standardError(label: label)
            handler.logLevel = level
            return handler
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
