import ApplicationServices
import AXorcist
@preconcurrency import Commander
import Foundation

enum CLIFrontend {
    struct UserError: Error {
        let message: String
        let exitCode: Int32
        let helpTopic: String?

        init(_ message: String, exitCode: Int32 = 2, helpTopic: String? = nil) {
            self.message = message
            self.exitCode = exitCode
            self.helpTopic = helpTopic
        }
    }

    private struct FindOptions: ParsableCommand {
        @Option(names: [.short("a"), .long("app")], help: "Application name, bundle identifier, PID, or 'focused'.")
        var app: String?

        @Option(name: .long, help: "Accessibility role, for example AXButton.")
        var role: String?

        @Option(name: .long, help: "Element title.")
        var title: String?

        @Option(name: .long, help: "Accessibility identifier.")
        var identifier: String?

        @Option(name: .long, help: "Element value.")
        var value: String?

        @Option(name: .long, help: "Attribute to include. Repeatable.")
        var attribute: String?

        @Option(name: .long, help: "Maximum traversal depth (default: 10).")
        var depth: String?

        @Flag(name: .long, help: "Use case-insensitive substring matching.")
        var contains = false

        @Flag(names: [.short("j"), .long("json")], help: "Emit the complete JSON response.")
        var json = false
    }

    private struct TreeOptions: ParsableCommand {
        @Option(names: [.short("a"), .long("app")], help: "Application name, bundle identifier, PID, or 'focused'.")
        var app: String?

        @Option(name: .long, help: "Maximum traversal depth (default: 3).")
        var depth: String?

        @Option(name: .long, help: "Only include elements with this accessibility role.")
        var role: String?

        @Flag(names: [.short("j"), .long("json")], help: "Emit the complete JSON response.")
        var json = false
    }

    private struct PermissionsOptions: ParsableCommand {
        @Flag(names: [.short("j"), .long("json")], help: "Emit JSON.")
        var json = false
    }

    @MainActor
    static func handle(arguments: [String]) throws -> Int32? {
        guard let first = arguments.first else {
            Swift.print(self.help())
            return 0
        }

        switch first {
        case "-h", "--help":
            Swift.print(self.help())
            return 0
        case "--version":
            Swift.print("axorc \(axorcVersion)")
            return 0
        case "help":
            let topic = arguments.dropFirst().first
            if let topic, !["permissions", "find", "tree", "raw"].contains(topic) {
                throw UserError("Unknown help topic '\(topic)'.")
            }
            Swift.print(self.help(topic: topic))
            return 0
        case "permissions":
            return try self.runPermissions(arguments: Array(arguments.dropFirst()))
        case "find":
            return try self.runFind(arguments: Array(arguments.dropFirst()))
        case "tree":
            return try self.runTree(arguments: Array(arguments.dropFirst()))
        case "raw":
            if arguments.dropFirst().contains(where: { $0 == "-h" || $0 == "--help" }) {
                Swift.print(self.help(topic: "raw"))
                return 0
            }
            return nil
        default:
            let trimmedFirst = first.trimmingCharacters(in: .whitespacesAndNewlines)
            if first.hasPrefix("-") || trimmedFirst.hasPrefix("{") || trimmedFirst.hasPrefix("[") {
                return nil
            }
            throw UserError("Unknown command '\(first)'.")
        }
    }

    static func rawArguments(from arguments: [String]) -> [String] {
        arguments.first == "raw" ? Array(arguments.dropFirst()) : arguments
    }

    static func emit(_ error: UserError) {
        fputs("Error: \(error.message)\n", stderr)
        let helpCommand = error.helpTopic.map { "axorc help \($0)" } ?? "axorc --help"
        fputs("Run '\(helpCommand)' for usage.\n", stderr)
        fflush(stderr)
    }

    static func responseSucceeded(_ response: String) -> Bool {
        guard let object = self.object(from: response) else { return false }
        if let success = object["success"] as? Bool {
            return success
        }
        if let status = object["status"] as? String {
            return status == "success" || status == "pong" || status == "observer_started"
        }
        return object["error"] == nil
    }

    @MainActor
    private static func runPermissions(arguments: [String]) throws -> Int32 {
        let parsed = try self.parse(PermissionsOptions(), arguments: arguments, topic: "permissions")
        let trusted = AXIsProcessTrusted()
        if parsed.flags.contains("json") {
            Swift.print("{\"accessibility\":\(trusted ? "true" : "false")}")
        } else {
            Swift.print("Accessibility: \(trusted ? "granted" : "missing")")
            if !trusted {
                Swift.print("Grant access in System Settings > Privacy & Security > Accessibility.")
            }
        }
        return trusted ? 0 : 1
    }

    @MainActor
    private static func runFind(arguments: [String]) throws -> Int32 {
        let parsed = try self.parse(FindOptions(), arguments: arguments, topic: "find")
        let app = try self.requiredOption("app", in: parsed, topic: "find")
        let depth = try self.depth(from: parsed, defaultValue: 10, topic: "find")
        let matchType: JSONPathHintComponent.MatchType = parsed.flags.contains("contains") ? .contains : .exact

        let criterionOptions = [
            ("role", "AXRole"),
            ("title", "AXTitle"),
            ("identifier", "AXIdentifier"),
            ("value", "AXValue"),
        ]
        let criteria = criterionOptions.compactMap { label, attribute -> Criterion? in
            guard let value = parsed.options[label]?.last else { return nil }
            return Criterion(attribute: attribute, value: value, matchType: matchType)
        }
        guard !criteria.isEmpty else {
            throw UserError(
                "Provide at least one of --role, --title, --identifier, or --value.",
                helpTopic: "find")
        }

        let defaultAttributes = ["AXRole", "AXTitle", "AXDescription", "AXIdentifier", "AXValue", "AXEnabled"]
        let attributes = parsed.options["attribute"] ?? defaultAttributes
        let envelope = CommandEnvelope(
            commandId: "find",
            command: .query,
            application: app,
            attributes: attributes,
            locator: Locator(criteria: criteria),
            maxDepth: depth)
        return try self.execute(envelope, json: parsed.flags.contains("json"), renderer: self.renderFind)
    }

    @MainActor
    private static func runTree(arguments: [String]) throws -> Int32 {
        let parsed = try self.parse(TreeOptions(), arguments: arguments, topic: "tree")
        let app = try self.requiredOption("app", in: parsed, topic: "tree")
        let depth = try self.depth(from: parsed, defaultValue: 3, topic: "tree")
        let role = parsed.options["role"]?.last
        let envelope = CommandEnvelope(
            commandId: "tree",
            command: .collectAll,
            application: app,
            attributes: ["AXRole", "AXTitle", "AXDescription", "AXIdentifier", "AXValue"],
            maxDepth: depth,
            filterCriteria: role.map { ["AXRole": $0] })
        let renderer = role == nil ? self.renderTree : self.renderFlatTree
        return try self.execute(envelope, json: parsed.flags.contains("json"), renderer: renderer)
    }

    @MainActor
    private static func execute(
        _ envelope: CommandEnvelope,
        json: Bool,
        renderer: ([String: Any]) throws -> String) throws -> Int32
    {
        let response = CommandExecutor.execute(
            command: envelope,
            axorcist: AXorcist.shared,
            debugCLI: false,
            traversalOptions: .standard)
        guard let object = self.object(from: response) else {
            throw UserError("AXorcist returned malformed JSON.", exitCode: 1)
        }
        guard self.responseSucceeded(response) else {
            if json {
                Swift.print(response)
                return 1
            }
            throw UserError(
                self.errorMessage(from: object) ?? "Accessibility operation failed.",
                exitCode: 1)
        }

        if json {
            Swift.print(response)
        } else {
            try Swift.print(renderer(object))
        }
        return 0
    }

    @MainActor
    private static func parse(
        _ command: some ParsableCommand,
        arguments: [String],
        topic: String) throws -> ParsedValues
    {
        if arguments.contains(where: { $0 == "-h" || $0 == "--help" }) {
            Swift.print(self.help(topic: topic))
            throw ExitCode.success
        }
        do {
            return try CommandParser(signature: CommandSignature.describe(command)).parse(arguments: arguments)
        } catch let error as CommanderError {
            throw UserError(error.description, helpTopic: topic)
        }
    }

    private static func requiredOption(_ name: String, in values: ParsedValues, topic: String) throws -> String {
        guard let value = values.options[name]?.last, !value.isEmpty else {
            throw UserError("Missing required option --\(name).", helpTopic: topic)
        }
        return value
    }

    private static func depth(from values: ParsedValues, defaultValue: Int, topic: String) throws -> Int {
        guard let raw = values.options["depth"]?.last else { return defaultValue }
        guard let value = Int(raw), (1...100).contains(value) else {
            throw UserError("--depth must be an integer from 1 through 100.", helpTopic: topic)
        }
        return value
    }

    private static func object(from response: String) -> [String: Any]? {
        guard let data = response.data(using: .utf8) else { return nil }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private static func errorMessage(from object: [String: Any]) -> String? {
        if let error = object["error"] as? String {
            return error
        }
        if let error = object["error"] as? [String: Any], let message = error["message"] as? String {
            return message
        }
        return object["message"] as? String
    }

    static func help(topic: String? = nil) -> String {
        switch topic {
        case "permissions": self.permissionsHelp
        case "find": self.findHelp
        case "tree": self.treeHelp
        case "raw": self.rawHelp
        default: self.rootHelp
        }
    }

    private static let permissionsHelp = """
    OVERVIEW: Check whether axorc can use macOS Accessibility.

    USAGE: axorc permissions [--json]

    OPTIONS:
      -j, --json  Emit JSON.
      -h, --help  Show help.
    """

    private static let findHelp = """
    OVERVIEW: Find one accessibility element.

    USAGE: axorc find --app <app> [criteria] [options]

    CRITERIA:
      --role <role>              Accessibility role, such as AXButton.
      --title <title>            Element title.
      --identifier <identifier>  Accessibility identifier.
      --value <value>            Element value.

    OPTIONS:
      -a, --app <app>            Name, bundle identifier, PID, or 'focused'.
      --contains                 Use case-insensitive substring matching.
      --attribute <name>         Attribute to include. Repeatable.
      --depth <number>           Traversal depth (default: 10).
      -j, --json                 Emit the complete JSON response.
      -h, --help                 Show help.

    EXAMPLE:
      axorc find --app Safari --role AXButton --title Back
    """

    private static let treeHelp = """
    OVERVIEW: Print an application's accessibility tree.

    USAGE: axorc tree --app <app> [options]

    OPTIONS:
      -a, --app <app>   Name, bundle identifier, PID, or 'focused'.
      --depth <number>  Traversal depth (default: 3).
      --role <role>     Only include this accessibility role.
      -j, --json        Emit the complete JSON response.
      -h, --help        Show help.

    EXAMPLE:
      axorc tree --app com.apple.dock --depth 3
    """

    private static let rawHelp = """
    OVERVIEW: Execute the stable JSON command protocol.

    USAGE:
      axorc raw --stdin
      axorc raw --file <path>
      axorc raw --json <payload>
      axorc raw '<payload>'

    RAW OPTIONS:
      --stdin          Read JSON from standard input.
      --file <path>    Read JSON from a file.
      --json <json>    Read JSON from an argument.
      --timeout <sec>  Override the 30-second traversal timeout.
      --scan-all       Disable container pruning.
      --no-stop-first  Continue below the first match.
      --debug          Include normal diagnostic logs.
      --verbose        Include maximum diagnostic logs.

    Every command requires command_id and command fields. Legacy root-level
    raw invocations remain supported.
    JSON uses collectAll/query, not the tree/find CLI names, and application/
    max_depth, not app/depth. See the README's JSON Protocol examples.

    EXAMPLE:
      echo '{"command_id":"health","command":"ping"}' | axorc raw --stdin
    """

    private static let rootHelp = """
    OVERVIEW: Inspect and automate macOS Accessibility from the shell.

    USAGE:
      axorc <command> [options]
      axorc raw <json-input-options>

    COMMANDS:
      permissions  Check Accessibility permission.
      find         Find one element by role, title, identifier, or value.
      tree         Print an application's accessibility tree.
      raw          Execute the complete JSON automation protocol.
      help         Show help for a command.

    OPTIONS:
      -h, --help  Show help.
      --version   Show the version.

    EXAMPLES:
      axorc permissions
      axorc tree --app com.apple.dock --depth 2
      axorc find --app Safari --role AXButton --title Back
      echo '{"command_id":"health","command":"ping"}' | axorc raw --stdin

    Accessibility permission required for inspection and automation.
    Documentation: https://github.com/openclaw/AXorcist#command-line-tool
    """
}
