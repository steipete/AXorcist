// AnyCodable.swift - Type-erased Codable wrapper for mixed-type payloads

import Foundation

// MARK: - AnyCodable for mixed-type payloads or attributes

// Reverted to simpler AnyCodable with public 'value' to match widespread usage
public struct AnyCodable: Codable, @unchecked Sendable {
    public let value: Any

    public init<T>(_ value: T?) {
        self.value = value ?? ()
    }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self.value = ()
        } else if let bool = try? container.decode(Bool.self) {
            self.value = bool
        } else if let int = try? container.decode(Int.self) {
            self.value = int
        } else if let double = try? container.decode(Double.self) {
            self.value = double
        } else if let string = try? container.decode(String.self) {
            self.value = string
        } else if let array = try? container.decode([AnyCodable].self) {
            self.value = array.map { $0.value }
        } else if let dictionary = try? container.decode([String: AnyCodable].self) {
            self.value = dictionary.mapValues { $0.value }
        } else {
            throw DecodingError.dataCorruptedError(in: container, debugDescription: "AnyCodable value cannot be decoded")
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if value is () { // Our nil marker for explicit nil
            try container.encodeNil()
            return
        }
        switch value {
        case let bool as Bool:
            try container.encode(bool)
        case let int as Int:
            try container.encode(int)
        case let double as Double:
            try container.encode(double)
        case let string as String:
            try container.encode(string)
        case let array as [Any]:
            try container.encode(array.map { AnyCodable($0) })
        case let dictionary as [String: Any]:
            try container.encode(dictionary.mapValues { AnyCodable($0) })
        default:
            if let codableValue = value as? Encodable {
                // If the value conforms to Encodable, let it encode itself using the provided encoder.
                // This is the most flexible approach as the Encodable type can use any container type it needs.
                try codableValue.encode(to: encoder)
            } else if CFGetTypeID(value as CFTypeRef) == CFNullGetTypeID() {
                try container.encodeNil()
            } else {
                throw EncodingError.invalidValue(value, EncodingError.Context(codingPath: [], debugDescription: "AnyCodable value (\(type(of: value))) cannot be encoded and does not conform to Encodable."))
            }
        }
    }
}

// Helper struct for AnyCodable to properly encode intermediate Encodable values
// This might not be necessary if the direct (value as! Encodable).encode(to: encoder) works.
struct AnyCodablePośrednik<T: Encodable>: Encodable {
    let value: T
    init(_ value: T) { self.value = value }
    func encode(to encoder: Encoder) throws {
        try value.encode(to: encoder)
    }
}

// Helper protocol to check if a type is Optional
private protocol OptionalProtocol {
    static func isOptional() -> Bool
}

extension Optional: OptionalProtocol {
    static func isOptional() -> Bool {
        return true
    }
}
