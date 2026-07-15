import Foundation
import Testing
@testable import axorc
@testable import AXorcist

@Suite("axorc user-facing CLI", .tags(.safe))
struct CLIFrontendTests {
    @Test
    func `Help and version are discoverable`() throws {
        let help = try runAXORCCommand(arguments: ["--help", "--not-a-real-flag"])
        #expect(help.exitCode == 0)
        #expect(help.output?.contains("COMMANDS:") == true)
        #expect(help.output?.contains("permissions") == true)
        #expect(help.errorOutput?.isEmpty ?? true)

        let version = try runAXORCCommand(arguments: ["--version"])
        #expect(version.exitCode == 0)
        #expect(version.output?.hasPrefix("axorc 0.") == true)
        #expect(version.errorOutput?.isEmpty ?? true)
    }

    @Test
    func `Subcommand help ignores other arguments`() throws {
        let result = try runAXORCCommand(arguments: ["find", "--garbage", "--help"])
        #expect(result.exitCode == 0)
        #expect(result.output?.contains("USAGE: axorc find") == true)
        #expect(result.errorOutput?.isEmpty ?? true)
    }

    @Test
    func `Unknown commands use usage exit status and stderr`() throws {
        let result = try runAXORCCommand(arguments: ["frobnicate"])
        #expect(result.exitCode == 2)
        #expect(result.output?.isEmpty ?? true)
        #expect(result.errorOutput?.contains("Unknown command 'frobnicate'") == true)
        #expect(result.errorOutput?.contains("axorc --help") == true)
    }

    @Test
    func `Find validates required options before Accessibility access`() throws {
        let missingApp = try runAXORCCommand(arguments: ["find", "--role", "AXButton"])
        #expect(missingApp.exitCode == 2)
        #expect(missingApp.errorOutput?.contains("Missing required option --app") == true)

        let missingCriteria = try runAXORCCommand(arguments: ["find", "--app", "Finder"])
        #expect(missingCriteria.exitCode == 2)
        #expect(missingCriteria.errorOutput?.contains("Provide at least one") == true)
    }

    @Test
    func `Permissions JSON is stable and truthful`() throws {
        let result = try runAXORCCommand(arguments: ["permissions", "--json"])
        #expect(result.exitCode == 0 || result.exitCode == 1)
        #expect(result.errorOutput?.isEmpty ?? true)

        let data = try #require(result.output?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["accessibility"] is Bool)
    }

    @Test
    func `Raw subcommand and legacy invocation both execute JSON`() throws {
        let payload = "{\"command_id\":\"compat\",\"command\":\"ping\"}"
        let raw = try runAXORCCommand(arguments: ["raw", payload])
        let legacy = try runAXORCCommand(arguments: [payload])
        let whitespacePrefixedLegacy = try runAXORCCommand(arguments: [" \n\t\(payload)"])

        #expect(raw.exitCode == 0)
        #expect(legacy.exitCode == 0)
        #expect(whitespacePrefixedLegacy.exitCode == 0)
        #expect(raw.output?.contains("\"success\":true") == true)
        #expect(legacy.output?.contains("\"success\":true") == true)
        #expect(whitespacePrefixedLegacy.output?.contains("\"success\":true") == true)
    }

    @Test
    func `Malformed raw commands fail with JSON on stdout`() throws {
        let result = try runAXORCCommand(arguments: ["raw", "{\"command\":\"ping\"}"])
        #expect(result.exitCode == 1)
        #expect(result.errorOutput?.isEmpty ?? true)

        let data = try #require(result.output?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["success"] as? Bool == false)
        #expect(object["command_id"] as? String == "decode_error")
    }

    @Test
    func `JSON mode preserves operation failures as JSON`() throws {
        let result = try runAXORCCommand(arguments: [
            "find",
            "--app", "com.example.axorc.missing",
            "--role", "AXApplication",
            "--json",
        ])

        #expect(result.exitCode == 1)
        #expect(result.errorOutput?.isEmpty ?? true)
        let data = try #require(result.output?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["status"] as? String == "error")
        #expect(object["error"] is String)
    }

    @Test
    func `Raw argument failures remain structured JSON`() throws {
        let result = try runAXORCCommand(arguments: ["raw", "--file"])

        #expect(result.exitCode == 2)
        #expect(result.errorOutput?.isEmpty ?? true)
        let data = try #require(result.output?.data(using: .utf8))
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["success"] as? Bool == false)
        #expect(object["command_id"] as? String == "argument_error")
    }

    @Test
    func `Human output visibly escapes terminal controls`() {
        let input = "title\nnext\t\u{1B}]52;clipboard\u{7}"
        let sanitized = CLIFrontend.sanitizeForTerminal(input)

        #expect(sanitized == "title\\nnext\\t\\u{1B}]52;clipboard\\u{7}")
    }

    @Test
    func `Filtered tree output does not invent ancestry`() throws {
        let object: [String: Any] = [
            "data": [
                "elements": [
                    ["brief_description": "Sibling", "path": ["root", "first"]],
                    ["brief_description": "Unrelated deep match", "path": ["root", "second", "child"]],
                ],
            ],
        ]

        #expect(try CLIFrontend.renderFlatTree(object) == "Sibling\nUnrelated deep match")
    }
}
