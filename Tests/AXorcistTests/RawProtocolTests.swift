import Foundation
import Testing

/// Subprocess waits must leave MainActor free for observer lifecycle tests running alongside this suite.
@Suite("Raw JSON wire protocol", .tags(.safe), .serialized)
nonisolated struct RawProtocolTests {
    @Test(arguments: ["json", "stdin", "file"])
    func `Every protocol command reaches dispatch through every input source`(source: String) throws {
        let commands = [
            "ping", "query", "getAttributes", "describeElement", "getElementAtPoint", "getFocusedElement",
            "performAction", "batch", "observe", "collectAll", "stopObservation", "isProcessTrusted",
            "isAXFeatureEnabled", "setFocusedValue", "extractText", "setNotificationHandler",
            "removeNotificationHandler", "getElementDescription",
        ]
        for command in commands {
            let payload = self.payload(command: command)
            let result = try self.run(payload, source: source)
            let object = try self.response(result)
            #expect(object["command_id"] as? String == command, "\(command), \(source): \(object)")
            #expect(result.errorOutput?.isEmpty ?? true)
            #expect(result.exitCode == 0 || result.exitCode == 1)
        }
    }

    @Test(arguments: ["json", "stdin", "file"])
    func `Path-only locators decode without criteria`(source: String) throws {
        let payload = """
        {"command_id":"path-only","command":"query","application":"com.example.axorc.protocol-test-missing",
         "locator":{"path_from_root":[{"attribute":"AXRole","value":"AXWindow"}]}}
        """
        let result = try self.run(payload, source: source)
        let object = try self.response(result)
        #expect(object["command_id"] as? String == "path-only")
        #expect(object["command_type"] as? String == "query")
        #expect(result.exitCode == 1) // The nonexistent application fails after decoding.
    }

    @Test(arguments: ["tree", "find"])
    func `CLI-only names explain the invalid command`(command: String) throws {
        let result = try self.run(
            "{\"command_id\":\"invalid\",\"command\":\"\(command)\",\"app\":\"Finder\",\"depth\":3}",
            source: "json")
        let message = try self.decodeError(result)
        #expect(message.contains(command))
        #expect(message.contains("at command"))
    }

    @Test(arguments: [false, true])
    func `Malformed nested fields report their actual path for objects and arrays`(array: Bool) throws {
        let payload = """
        {"command_id":"invalid-path","command":"query","locator":{"criteria":[],"path_from_root":"invalid"}}
        """
        let result = try self.run(array ? "[\(payload)]" : payload, source: "json")
        let message = try self.decodeError(result)
        #expect(message.contains("locator.pathFromRoot"))
        #expect(message.contains("Type mismatch"))
        if array {
            #expect(message.contains("Index 0"))
        }
    }

    @Test
    func `Nested batch decode errors retain the subcommand path`() throws {
        let payload = """
        {"command_id":"batch","command":"batch","sub_commands":[
          {"command_id":"bad","command":"query","locator":{"criteria":"invalid"}}]}
        """
        let message = try self.decodeError(self.run(payload, source: "json"))
        #expect(message.contains("subCommands.Index 0.locator.criteria"))
    }

    @Test(arguments: [false, true])
    func `Valid command arrays still decode including a UTF8 BOM`(bom: Bool) throws {
        let payload = (bom ? "\u{FEFF}" : "") + " \n[{\"command_id\":\"array\",\"command\":\"ping\"}]"
        let result = try self.run(payload, source: "json")
        let object = try self.response(result)
        #expect(object["command_id"] as? String == "array")
        #expect(result.exitCode == 0)
    }

    @Test
    func `Empty command arrays remain a structured error`() throws {
        let message = try self.decodeError(self.run("[]", source: "json"))
        #expect(message == "JSON command array must not be empty")
    }

    private func payload(command: String) -> String {
        // A nonexistent application keeps action and observer dispatch safe on developer machines.
        let target = "com.example.axorc.protocol-test-missing"
        let options = switch command {
        case "performAction": #", "action_name":"AXPress""#
        case "setFocusedValue": #", "action_value":"test value""#
        case "getElementAtPoint": #", "point":[500,300]"#
        case "observe": #", "notifications":["AXValueChanged"], "watch_children":false"#
        case "batch": """
            ,"sub_commands":[
              {"command_id":"nested-query","command":"query","application":"\(target)"},
              {"command_id":"nested-value","command":"setFocusedValue","application":"\(target)",
               "action_value":"test value"}]
            """
        default: ""
        }
        return """
        {"command_id":"\(command)","command":"\(command)","application":"\(target)",
         "locator":{"criteria":[{"attribute":"AXRole","value":"AXButton","match_type":"exact"}]},
         "attributes":["AXRole","AXTitle"],"max_depth":3\(options)}
        """
    }

    private func run(_ payload: String, source: String) throws -> CommandResult {
        #expect(!Thread.isMainThread, "Blocking subprocess waits must not occupy the main actor")
        switch source {
        case "stdin":
            return try runAXORCCommandWithStdin(inputJSON: payload, arguments: ["raw", "--timeout", "1"])
        case "file":
            let path = try createTempFile(content: payload)
            defer { try? FileManager.default.removeItem(atPath: path) }
            return try runAXORCCommand(arguments: ["raw", "--file", path, "--timeout", "1"])
        default:
            return try runAXORCCommand(arguments: ["raw", "--json", payload, "--timeout", "1"])
        }
    }

    private func response(_ result: CommandResult) throws -> [String: Any] {
        let data = try #require(result.output?.data(using: .utf8))
        return try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    private func decodeError(_ result: CommandResult) throws -> String {
        let object = try self.response(result)
        #expect(result.exitCode == 1)
        #expect(result.errorOutput?.isEmpty ?? true)
        #expect(object["command_id"] as? String == "decode_error")
        #expect(object["success"] as? Bool == false)
        let error = try #require(object["error"] as? [String: Any])
        return try #require(error["message"] as? String)
    }
}
