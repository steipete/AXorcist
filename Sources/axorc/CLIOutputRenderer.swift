import Foundation

extension CLIFrontend {
    static func renderFind(_ object: [String: Any]) throws -> String {
        guard let data = object["data"] as? [String: Any] else {
            throw UserError("Find response contained no element.", exitCode: 1)
        }
        if let description = data["brief_description"] as? String, !description.isEmpty {
            return self.sanitizeForTerminal(description)
        }
        if let text = data["textual_content"] as? String, !text.isEmpty {
            return self.sanitizeForTerminal(text)
        }
        throw UserError("Found an element, but it had no printable description.", exitCode: 1)
    }

    static func renderTree(_ object: [String: Any]) throws -> String {
        guard
            let data = object["data"] as? [String: Any],
            let elements = data["elements"] as? [[String: Any]]
        else {
            throw UserError("Tree response contained no elements.", exitCode: 1)
        }
        guard !elements.isEmpty else { return "No elements found." }

        let lines = elements.map { element -> (depth: Int, description: String) in
            let pathCount = (element["path"] as? [Any])?.count ?? 1
            let pathDepth = max(0, pathCount - 1)
            let description = element["brief_description"] as? String
                ?? element["textual_content"] as? String
                ?? "Unknown element"
            return (pathDepth, self.sanitizeForTerminal(description))
        }
        let minimumDepth = lines.map(\.depth).min() ?? 0
        return lines.map { line in
            String(repeating: "  ", count: line.depth - minimumDepth) + line.description
        }.joined(separator: "\n")
    }

    static func renderFlatTree(_ object: [String: Any]) throws -> String {
        guard
            let data = object["data"] as? [String: Any],
            let elements = data["elements"] as? [[String: Any]]
        else {
            throw UserError("Tree response contained no elements.", exitCode: 1)
        }
        guard !elements.isEmpty else { return "No elements found." }

        return elements.map { element in
            let description = element["brief_description"] as? String
                ?? element["textual_content"] as? String
                ?? "Unknown element"
            return self.sanitizeForTerminal(description)
        }.joined(separator: "\n")
    }

    static func sanitizeForTerminal(_ value: String) -> String {
        value.unicodeScalars.map { scalar in
            switch scalar.value {
            case 0x09: "\\t"
            case 0x0A: "\\n"
            case 0x0D: "\\r"
            case 0x2028: "\\u{2028}"
            case 0x2029: "\\u{2029}"
            default:
                if CharacterSet.controlCharacters.contains(scalar) {
                    "\\u{\(String(scalar.value, radix: 16, uppercase: true))}"
                } else {
                    String(scalar)
                }
            }
        }.joined()
    }
}
