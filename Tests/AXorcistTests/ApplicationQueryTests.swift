import AppKit
import Testing
@testable import AXorcist

/// Helper type for decoding arbitrary JSON values
struct AnyDecodable: Decodable {
    let value: Any

    init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()

        if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyDecodable].self) {
            self.value = array.map(\.value)
        } else if let dict = try? container.decode([String: AnyDecodable].self) {
            var result: [String: Any] = [:]
            for (key, val) in dict {
                result[key] = val.value
            }
            self.value = result
        } else {
            self.value = NSNull()
        }
    }
}

@Suite("AXorcist Application Query Tests", .tags(.safe))
struct ApplicationQueryTests {
    @Test(
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    func `Collect all elements in the frontmost application`() throws {
        let command = CommandEnvelope(
            commandId: "test-get-all-apps",
            command: .collectAll,
            attributes: ["AXRole", "AXTitle", "AXIdentifier"],
            debugLogging: true,
            locator: Locator(criteria: [Criterion(attribute: "AXRole", value: "AXApplication")]),
            maxDepth: 3,
            outputFormat: .verbose)

        let encoder = JSONEncoder()
        encoder.outputFormatting = .prettyPrinted
        let jsonData = try encoder.encode(command)
        guard let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) else {
            throw TestError.generic("Failed to create JSON")
        }

        let result = try runAXORCCommand(arguments: [jsonString])

        #expect(result.exitCode == 0, "Command should succeed")
        #expect(result.output != nil, "Should have output")

        guard let output = result.output,
              let responseData = output.data(using: String.Encoding.utf8)
        else {
            throw TestError.generic("No output")
        }

        if let response = try? JSONDecoder().decode(QueryResponse.self, from: responseData) {
            #expect(response.success)
            if let data = response.data {
                #expect(data.attributes != nil, "Should have attributes")
            } else {
                Issue.record("CollectAll query response had no data payload")
            }
        } else if
            let jsonObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any],
            let data = jsonObject["data"] as? [String: Any],
            let count = data["count"] as? Int,
            let elements = data["elements"] as? [[String: Any]]
        {
            #expect(count > 0, "CollectAll response should report at least one element")
            #expect(!elements.isEmpty, "CollectAll response should include element payloads")
        } else {
            let fallback = String(data: responseData, encoding: .utf8) ?? "<non-UTF8>"
            Issue.record("Unexpected response payload for collectAll: \(fallback)")
        }
    }

    @Test(
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    func `CollectAll filters descendants without pruning their parents`() throws {
        let json = """
        {
          "command_id": "test-filter-descendants",
          "command": "collectAll",
          "application": "com.apple.dock",
          "attributes": ["AXRole", "AXTitle"],
          "max_depth": 3,
          "filter_criteria": {"AXRole": "AXDockItem"}
        }
        """
        let result = try runAXORCCommand(arguments: [json])

        #expect(result.exitCode == 0)
        let outputData = try #require(result.output?.data(using: String.Encoding.utf8))
        let object = try #require(JSONSerialization.jsonObject(with: outputData) as? [String: Any])
        let responseData = try #require(object["data"] as? [String: Any])
        let elements = try #require(responseData["elements"] as? [[String: Any]])
        #expect(!elements.isEmpty)
        #expect(elements.allSatisfy { $0["role"] as? String == "AXDockItem" })
    }

    @Test(
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    func `Human CLI resolves app names and returns requested attributes`() throws {
        let result = try runAXORCCommand(arguments: [
            "find",
            "--app", "Dock",
            "--role", "AXApplication",
            "--attribute", "AXRole",
            "--json",
        ])

        #expect(result.exitCode == 0)
        #expect(result.errorOutput?.isEmpty ?? true)
        let outputData = try #require(result.output?.data(using: String.Encoding.utf8))
        let object = try #require(JSONSerialization.jsonObject(with: outputData) as? [String: Any])
        let responseData = try #require(object["data"] as? [String: Any])
        let attributes = try #require(responseData["attributes"] as? [String: Any])
        let role = try #require(attributes["AXRole"] as? [String: Any])
        #expect(role["any_value"] as? String == "AXApplication")
    }

    @Test(
        .tags(.automation),
        .enabled(if: AXTestEnvironment.runAutomationScenarios))
    @MainActor
    func `List TextEdit windows`() async throws {
        await closeTextEdit()
        try await Task.sleep(for: .milliseconds(500))

        _ = try await setupTextEditAndGetInfo()
        defer {
            if let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.TextEdit").first {
                app.terminate()
            }
        }

        try await Task.sleep(for: .seconds(1))

        let command = CommandEnvelope(
            commandId: "test-get-windows",
            command: .query,
            application: "TextEdit",
            debugLogging: true,
            locator: Locator(criteria: [Criterion(attribute: "AXRole", value: "AXWindow")]),
            outputFormat: .verbose)

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(command)
        guard let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) else {
            throw TestError.generic("Failed to create JSON")
        }

        let result = try runAXORCCommand(arguments: [jsonString])
        #expect(result.exitCode == 0)

        guard let output = result.output,
              let responseData = output.data(using: String.Encoding.utf8)
        else {
            throw TestError.generic("No output")
        }

        let response = try JSONDecoder().decode(QueryResponse.self, from: responseData)

        #expect(response.success)
        if let data = response.data {
            if let roleValue = data.attributes?["AXRole"] {
                #expect(roleValue.stringValue == "AXWindow")
            }
            if let titleValue = data.attributes?["AXTitle"] {
                #expect(titleValue.stringValue != nil, "Window should have title")
            }
        }
    }

    @Test(.tags(.safe))
    func `Query non-existent application`() throws {
        let command = CommandEnvelope(
            commandId: "test-nonexistent",
            command: .query,
            application: "NonExistentApp12345",
            debugLogging: true,
            locator: Locator(criteria: [Criterion(attribute: "AXRole", value: "AXApplication")]))

        let encoder = JSONEncoder()
        let jsonData = try encoder.encode(command)
        guard let jsonString = String(data: jsonData, encoding: String.Encoding.utf8) else {
            throw TestError.generic("Failed to create JSON")
        }

        let result = try runAXORCCommand(arguments: [jsonString])

        #expect(result.exitCode == 1, "Missing applications should return a failure exit status")

        guard let output = result.output,
              let responseData = output.data(using: String.Encoding.utf8)
        else {
            throw TestError.generic("No output")
        }

        if let response = try? JSONDecoder().decode(SimpleSuccessResponse.self, from: responseData) {
            if response.success {
                let message = response.message
                #expect(
                    message.contains("No") || message.contains("not found") || message.isEmpty,
                    "Message should indicate no elements found or be empty")
            }
        } else if let jsonObject = try? JSONSerialization.jsonObject(with: responseData) as? [String: Any] {
            let message = (jsonObject["message"] as? String) ?? (jsonObject["error"] as? String) ?? ""
            #expect(
                message.contains("No") || message.contains("not found") || message.contains("error") || message.isEmpty,
                "Message should indicate no elements found or be empty")
        } else {
            let rawOutput = String(data: responseData, encoding: .utf8) ?? "<non-UTF8 response>"
            Issue.record("Unexpected response for nonexistent app: \(rawOutput)")
        }
    }
}
