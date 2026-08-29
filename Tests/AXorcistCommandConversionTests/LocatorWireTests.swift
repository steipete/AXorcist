import Foundation
import Testing
@testable import axorc
@testable import AXorcist

@Suite("Locator wire contract")
struct LocatorWireTests {
    @Test(arguments: [false, true])
    func `Published path key survives both decoder strategies`(snakeCase: Bool) throws {
        let json = """
        {"criteria":[],"path_from_root":[{"attribute":"AXTitle","value":"Main","depth":2}]}
        """
        let locator = try self.decode(json, snakeCase: snakeCase)
        let hint = try #require(locator.rootElementPathHint?.first)
        #expect(hint.attribute == "AXTitle")
        #expect(hint.value == "Main")
        #expect(hint.depth == 2)
    }

    @Test(arguments: [false, true])
    func `Path-only locator uses empty criteria`(snakeCase: Bool) throws {
        let locator = try self.decode(
            #"{"path_from_root":[{"attribute":"AXRole","value":"AXWindow"}]}"#,
            snakeCase: snakeCase)
        #expect(locator.criteria.isEmpty)
        #expect(locator.rootElementPathHint?.count == 1)
    }

    @Test(arguments: [false, true])
    func `Published encoding keeps path_from_root`(snakeCase: Bool) throws {
        let locator = Locator(rootElementPathHint: [
            JSONPathHintComponent(attribute: "AXTitle", value: "Main", depth: 2),
        ])
        let encoder = JSONEncoder()
        if snakeCase {
            encoder.keyEncodingStrategy = .convertToSnakeCase
        }
        let data = try encoder.encode(locator)
        let object = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        #expect(object["path_from_root"] != nil)
        #expect(object["pathFromRoot"] == nil)
        let json = try #require(String(data: data, encoding: .utf8))
        let decoded = try self.decode(json, snakeCase: snakeCase)
        #expect(decoded.rootElementPathHint?.first?.value == "Main")
    }

    @Test
    func `Documented query path and snake case options reach the library command`() throws {
        let json = """
        {"command_id":"path-query","command":"query","application":"Finder","max_depth":7,
         "locator":{"path_from_root":[{"attribute":"AXTitle","value":"Main","match_type":"prefix"}],
         "criteria":[{"attribute":"AXRole","value":"AXButton","match_type":"contains"}],
         "matchAll":false,"require_action":"AXPress","debug_path_search":true}}
        """
        let decoder = JSONDecoder()
        decoder.keyDecodingStrategy = .convertFromSnakeCase
        let envelope = try decoder.decode(CommandEnvelope.self, from: Data(json.utf8))
        guard case let .query(query) = envelope.command.toAXCommand(commandEnvelope: envelope) else {
            Issue.record("Expected query conversion")
            return
        }
        #expect(query.appIdentifier == "Finder")
        #expect(query.maxDepthForSearch == 7)
        #expect(query.locator.rootElementPathHint?.first?.matchType == .prefix)
        #expect(query.locator.criteria.first?.matchType == .contains)
        #expect(query.locator.matchAll == false)
        #expect(query.locator.requireAction == "AXPress")
        #expect(query.locator.debugPathSearch == true)
    }

    private func decode(_ json: String, snakeCase: Bool) throws -> Locator {
        let decoder = JSONDecoder()
        if snakeCase {
            decoder.keyDecodingStrategy = .convertFromSnakeCase
        }
        return try decoder.decode(Locator.self, from: Data(json.utf8))
    }
}
